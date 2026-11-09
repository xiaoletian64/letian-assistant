"""Daily owner-only digest. Reads existing data; never calls inference or billing APIs."""
import argparse
from datetime import datetime, timedelta
import hashlib
import json
import math
from urllib.parse import quote
from pathlib import Path
import sqlite3
import subprocess
import sys
from zoneinfo import ZoneInfo

TZ = ZoneInfo('Asia/Shanghai')
PLATFORMS = ('taobao', 'jd', 'pinduoduo', 'meituan', 'douyin_mall')
NAMES = {'taobao':'淘宝', 'jd':'京东', 'pinduoduo':'拼多多', 'meituan':'美团', 'douyin_mall':'抖音商城', 'codex':'Codex', 'cursor':'Cursor', 'mimo':'MiMo', 'opencode':'OpenCode', 'zhipu':'智谱', 'deepseek':'DeepSeek', 'tencent':'腾讯', 'jev':'JEV', 'gha':'GitHub Actions'}

def instant(value):
    try:
        if isinstance(value, bool) or value is None: return None
        if isinstance(value, (int, float)): return float(value) if math.isfinite(value) else None
        d = datetime.fromisoformat(value.replace('Z', '+00:00'))
        return d.replace(tzinfo=TZ).timestamp() if d.tzinfo is None else d.timestamp()
    except (ValueError, TypeError, OverflowError): return None

def source_export(path='/opt/letian-purchases/state/orders.sqlite', now=None):
    """Private fixed RPC: no order titles, IDs, credentials or selectable owner."""
    now = now or datetime.now(TZ)
    day = now.date() - timedelta(days=1)
    start = datetime.combine(day, datetime.min.time(), TZ).timestamp()
    end = start + 86400
    result = {'day':str(day), 'status':'partial', 'paid_by_currency':{}, 'paid_orders':0,
              'unknown_paid_at':0, 'unknown_amount':0, 'ambiguous_parent_rows':0, 'accounts':[]}
    try:
        with sqlite3.connect('file:'+quote(str(Path(path).resolve()))+'?mode=ro', uri=True) as c:
            c.execute('PRAGMA query_only=ON')
            rows = [json.loads(r[0]) for r in c.execute('SELECT payload FROM orders WHERE owner=?', ('1',))]
            for platform, state, sync, coverage in c.execute('SELECT platform,state,last_sync,coverage FROM accounts WHERE owner=?', ('1',)):
                result['accounts'].append({'platform':platform, 'state':state, 'last_sync':sync, 'coverage':json.loads(coverage)})
        parents = {(r['account_id'], r['source_parent_order_id']) for r in rows if r.get('source_parent_order_id')}
        ids = {(r['account_id'], r['source_order_id']) for r in rows}
        for r in rows:
            key = (r['account_id'], r['source_order_id'])
            parent = (r['account_id'], r.get('source_parent_order_id'))
            # Exclude ambiguous trees from totals rather than guess a statistical level.
            if key in parents or parent in ids:
                result['ambiguous_parent_rows'] += 1
                continue
            paid = instant(r.get('paid_at'))
            if paid is None:
                result['unknown_paid_at'] += 1
                continue
            if not start <= paid < end: continue
            amount, currency = r.get('paid_amount_minor'), r.get('currency')
            if type(amount) is not int or amount < 0 or currency not in ('CNY','USD'):
                result['unknown_amount'] += 1
                continue
            result['paid_orders'] += 1
            result['paid_by_currency'][currency] = result['paid_by_currency'].get(currency, 0) + amount
    except (OSError, sqlite3.Error, ValueError, KeyError, TypeError):
        return {'day':str(day), 'status':'unavailable'}
    return result

def quotas(cache, now):
    from server.quota_history.collector import normalize
    result = []
    # A provider's push block supersedes its aggregate mirror as a whole. Never add mirrors.
    selected = dict(cache)
    selected['push'] = dict(cache.get('push', {}))
    selected['accounts'] = {p:b for p,b in cache.get('accounts', {}).items() if p not in cache.get('push', {})}
    # Cursor structured aggregate is usable only after explicit account-ID equality.
    cursor = cache.get('accounts', {}).get('cursor', {})
    mirrors = cache.get('push', {}).get('cursor', {}).get('accounts', [])
    if cursor.get('account_id') and len(mirrors)==1 and mirrors[0].get('account_id')==cursor['account_id']:
        selected['accounts']['cursor'] = cursor
        selected['push'].pop('cursor', None)
    for r in normalize(selected, 'existing_cache', now.timestamp()):
        if r['provider']=='cursor' and r['window'] in ('included','gpt_tokens','gpt_cents'):continue
        provider = NAMES.get(r['provider'], r['provider'])
        window = {'five_hour':'5小时窗口','rolling':'滚动窗口','monthly':'每月窗口','mcp':'工具调用','fh':'来源窗口','sd':'每周窗口','weekly':'每周窗口','daily':'每日窗口','subscription':'套餐','balance':'余额','collection':'采集状态','total_percent':'总用量','api_percent':'指定模型','auto_percent':'自动模型','billing':'账期','unstructured':'额度'}.get(r['window'], '来源窗口')
        if r['provider']=='codex' and r['raw'].get('window_seconds'):
            window = {18000:'5小时窗口',604800:'每周窗口'}.get(r['raw']['window_seconds'],'来源窗口')
        account = '' if r['account']=='default' else ' · '+r['account'].replace('(prolite)','')
        if r['provider']=='mimo': account = ' · 当前套餐'
        if r['provider']=='gha': account = {'personal':' · 个人账户','org':' · 组织账户'}.get(r['account'],'')
        label = f"{provider}{account} · {window}"
        age = now.timestamp() - r['source_time'] if r['source_time'] is not None else None
        if r['error'] or age is None or age < -60 or age > 5400:
            result.append(f'{label}：未获取当前有效数据' + ('（缓存过期）' if age is not None and age > 5400 else ''))
            continue
        remain = r['remaining']
        if remain is None and r['units'] == 'percent' and r['used'] is not None and 0 <= r['used'] <= 100:
            remain = 100 - r['used']
        when = datetime.fromtimestamp(r['source_time'], TZ).strftime('%m-%d %H:%M')
        if remain is None:
            result.append(f'{label}：剩余额度未返回（采集 {when}）')
        else:
            unit = {'percent':'%', 'credits':' Credit', 'tokens':' token','minutes':' 分钟'}.get(r['units'], ' '+r['units'])
            if r['provider']=='mimo':unit = ' 来源计量值（单位待核验）'
            kind = '账户余额' if r['window'] == 'balance' else '套餐剩余'
            amount = f'{remain:,.1f}'.removesuffix('.0') if r['units']=='percent' else f'{remain:,}'
            result.append(f'{label}：{kind} {amount}{unit}（采集 {when}）')
    return result or ['额度缓存未获取']

def billing_lines(data, day, now):
    """Only explicitly complete provider daily bills qualify as actual costs."""
    lines=[]
    entries=data.get('entries',[]) if isinstance(data,dict) else []
    for server in ('106','124','114'):
        rows=[r for r in entries if isinstance(r,dict) and r.get('server_id')==server and r.get('day')==day]
        valid=[]
        for row in rows:
            observed=instant(row.get('observed_at'))
            if (row.get('basis')=='official_daily_bill' and row.get('coverage_complete') is True
                and type(row.get('amount_minor')) is int and row['amount_minor']>=0
                and row.get('currency') in ('CNY','USD') and row.get('evidence_ref')
                and observed is not None and -60<=now.timestamp()-observed<=172800): valid.append(row)
        # Conflicting/duplicate bill entries are unknown, never summed.
        if len(valid)==1 and len(rows)==1:
            row=valid[0]
            lines.append(f"{server}：官方日账单 {row['amount_minor']/100:.2f} {row['currency']}（完整账单）")
        else:lines.append(f'{server}：未获取可核验的官方昨日完整账单')
    return lines

def build(cache, purchases, now=None, billing=None):
    now = now or datetime.now(TZ)
    yesterday = str(now.date() - timedelta(days=1))
    lines = [f'乐天早报 · {now:%Y-%m-%d}', f'统计时区：北京时间；昨日：{yesterday}', '', 'AI 剩余额度']
    try: lines.extend(quotas(cache, now))
    except (ValueError, TypeError, KeyError): lines.append('额度缓存格式不可用')
    lines += ['订阅额度和账户余额均不等于官方按量账单。', '', '昨日购物消费']
    if purchases.get('status') == 'unavailable' or purchases.get('day') != yesterday:
        lines.append('未获取昨日消费数据，不能判断是否为零。')
    else:
        paid = purchases.get('paid_by_currency', {})
        if paid:
            lines.append('已核验支付时间的局部实付：' + '；'.join(f'{v/100:.2f} {k}' for k,v in paid.items()))
        else: lines.append('未取得可按昨日支付时间核验的实付记录，昨日总额未知。')
        lines.append(f"支付时间缺失 {purchases.get('unknown_paid_at', 0)} 条；昨日金额缺失 {purchases.get('unknown_amount', 0)} 条；父子归属待核验 {purchases.get('ambiguous_parent_rows', 0)} 条。")
        lines.append('退款不在此推算；尚不能计算昨日净支出。')
        for platform in PLATFORMS:
            accounts = [a for a in purchases.get('accounts', []) if a['platform'] == platform]
            syncs = [a['last_sync'] for a in accounts if a.get('last_sync')]
            sync = instant(max(syncs)) if syncs else None
            when = datetime.fromtimestamp(sync,TZ).strftime('%m-%d %H:%M') if sync is not None else '未获取'
            lines.append(f"{NAMES[platform]}：最近入库 {when}；昨日全量覆盖未验证")
    lines += ['', '昨日服务器费用', *billing_lines(billing,yesterday,now), '余额变动、套餐购入价或资源使用率不能当作昨日实际费用。']
    return {'day':str(now.date()), 'title':f'乐天早报 · {now:%m-%d}', 'body':'\n'.join(lines), 'generated_at':now.timestamp()}

def publish(report, path, now=None):
    from .service import NotificationService
    now = now or datetime.now(TZ)
    if set(report) != {'day','title','body','generated_at'} or report['day'] != str(now.date()): raise ValueError('invalid_daily_report')
    if not isinstance(report['body'], str) or len(report['body'].encode('utf-8')) > 24000: raise ValueError('invalid_daily_body')
    if not isinstance(report['title'], str) or len(report['title']) > 100: raise ValueError('invalid_daily_title')
    stamp = instant(report['generated_at'])
    if stamp is None or not -60 <= now.timestamp()-stamp <= 300: raise ValueError('stale_daily_report')
    service = NotificationService(path)
    identity = hashlib.sha256(('morning:1:'+report['day']).encode()).hexdigest()
    event = dict(id=identity, account_id='1', series_id='daily-morning', type='daily_digest',
                 source_time=stamp, window=report['day'], title=report['title'], body=report['body'])
    with service.db() as c:
        row = c.execute('SELECT payload FROM notification_settings WHERE account_id=?', ('1',)).fetchone()
        if row and json.loads(row[0]).get('daily') is False: return {'status':'disabled'}
        inserted = c.execute('INSERT OR IGNORE INTO alert_events VALUES(?,?,?,?)', (identity,'1',stamp,json.dumps(event,ensure_ascii=False))).rowcount
    return {'status':'created' if inserted else 'already_exists', 'event_id':identity}

def main():
    p = argparse.ArgumentParser()
    p.add_argument('mode', choices=('sources','preview','run'))
    p.add_argument('--cache', default='/opt/notes-site/quota_cache.json')
    p.add_argument('--db', default='/var/lib/letian-notifications/notifications.sqlite3')
    p.add_argument('--sources-file')
    p.add_argument('--billing',default='/var/lib/letian-notifications/server-billing.json')
    a = p.parse_args()
    if a.mode == 'sources':
        print(json.dumps(source_export(), ensure_ascii=False)); return
    try: cache = json.loads(Path(a.cache).read_text())
    except (OSError, ValueError): cache = {}
    try:
        if a.sources_file: purchases = json.loads(Path(a.sources_file).read_text())
        else:
            r = subprocess.run(['ssh','-oBatchMode=yes','-oConnectTimeout=8','monitor-primary',
                'cd /opt/letian-notifications && /usr/bin/python3 -m server.notifications.morning sources'], capture_output=True, timeout=25, check=True)
            purchases = json.loads(r.stdout)
    except (OSError, ValueError, subprocess.SubprocessError): purchases = {'status':'unavailable'}
    try: billing=json.loads(Path(a.billing).read_text())
    except (OSError,ValueError): billing=None
    report = build(cache, purchases,billing=billing)
    if a.mode == 'preview': print(json.dumps(report,ensure_ascii=False)); return
    result = publish(report, a.db)
    from .delivery import deliver
    from .gateway import configuration, GatewaySender
    results = deliver(a.db, GatewaySender(configuration()))
    print(json.dumps(dict(result, delivery_attempts=len(results)),ensure_ascii=False))

if __name__ == '__main__': main()
