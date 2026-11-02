"""Read existing JSON files only. No upstream APIs, authentication or model calls."""
import argparse
from datetime import datetime
import json
import os
import re
from pathlib import Path
import subprocess
import time
from .history import Store

PROVIDERS=('zhipu','opencode','deepseek','tencent','codex','cursor','mimo','jev','gha')
def number(value):
    # Python JSON integers are arbitrary precision; do not round via float.
    if value is None or isinstance(value,bool): return None
    if isinstance(value,int): return value
    if isinstance(value,str) and re.fullmatch(r'[+-]?\d+',value.strip()): return int(value)
    try:
        result=float(value)
        import math
        return result if math.isfinite(result) else None
    except (ValueError,TypeError,OverflowError): return None
def timestamp(value):
    if isinstance(value,(int,float)): return value
    if isinstance(value,str):
        try:
            dt=datetime.fromisoformat(value.replace('Z','+00:00'))
            # Existing now() strings are Beijing-local, not this host's timezone.
            if dt.tzinfo is None:
                from datetime import timezone,timedelta
                dt=dt.replace(tzinfo=timezone(timedelta(hours=8)))
            return dt.timestamp()
        except ValueError: pass
    return None

def normalize(data, source, observed, provider=None):
    def row(p,a,w,unit,values=None,ts=None,raw=None,error=None):
        v=values or {}
        return dict(provider=p,account=str(a),source=source,window=w,units=unit,source_time=timestamp(ts),observed_time=observed,used=number(v.get('used')),remaining=number(v.get('remaining')),limit=number(v.get('limit')),reset_at=timestamp(v.get('reset_at')),reset_basis=v.get('reset_basis'),raw=raw or v,error=error)
    def accounts(p,block):
        ts=block.get('observedAt',block.get('updated_at',block.get('updated')))
        if block.get('lastError') or block.get('error'):
            yield row(p,'default','collection','unknown',ts=block.get('lastCheckAt',ts),error='source_error')
        if p=='cursor' and isinstance(block.get('percentages'),dict):
            for k,v in block['percentages'].items():
                yield row(p,'default',k,'percent',{'used':v,'limit':100,'reset_at':block.get('billingCycleEnd')},ts,{'used':v,'billingCycleEnd':block.get('billingCycleEnd')})
        if p=='gha':
            for name in ('personal','org'):
                q=block.get(name)
                if isinstance(q,dict): yield row(p,name,'billing','minutes',{'used':q.get('used'),'remaining':q.get('left'),'limit':q.get('included')},ts)
        for a in block.get('accounts') or []:
            name=a.get('n','default'); t=a.get('ts',ts); found=False
            for key in ('fh','sd'):
                q=a.get(key)
                if isinstance(q,dict):
                    found=True
                    yield row(p,name,key,'percent',{'used':q.get('u'),'limit':100,'reset_at':q.get('reset_at')},t,q)
            if isinstance(a.get('quota'),dict):
                found=True; q=dict(a['quota'])
                yield row(p,name,'subscription','credits',q,t,dict(q,plan_expires_at=block.get('periodEndUTC')))
            if isinstance(a.get('bal'),dict):
                found=True; q=a['bal']; yield row(p,name,'balance',q.get('cur') or 'unknown',{'remaining':q.get('amt')},t)
            if not found and not (p=='mimo' and block.get('items')): yield row(p,name,'unstructured','unknown',ts=t,raw={'rem':a.get('rem')})
        if p=='mimo' and not any(isinstance(a.get('quota'),dict) for a in block.get('accounts') or []):
            for q in block.get('items') or []:
                if not isinstance(q,dict): continue
                name='MiMo-'+str(block['plan'])+'-'+str(q.get('name','unknown')) if block.get('plan') else str(q.get('name','unknown'))
                yield row(p,name,'subscription','credits',q,ts,dict(q,plan_expires_at=block.get('periodEndUTC')))
    if provider:
        yield from accounts(provider,data)
        return
    if isinstance(data.get('accounts'),dict):
        ts=data.get('collected_at')
        for p,a in data['accounts'].items():
            if p not in PROVIDERS or not isinstance(a,dict): continue
            if p in ('deepseek','tencent'):
                yield row(p,'default','balance',a.get('currency') or 'unknown',{'remaining':a.get('amount')},ts)
            elif p=='cursor':
                for key in ('total_percent','api_percent','auto_percent'):
                    if key in a: yield row(p,'default',key,'percent',{'used':a[key],'limit':100,'reset_at':a.get('cycle_end')},ts)
                if 'included_used' in a:
                    # Source unit undocumented; keep it distinct, never call it dollars.
                    yield row(p,'default','included','source_units',{'used':a.get('included_used'),'limit':a.get('included_limit'),'reset_at':a.get('cycle_end')},ts)
                for key,unit in [('gpt_tokens','tokens'),('gpt_cents','cents')]:
                    if key in a: yield row(p,'default',key,unit,{'used':a[key],'reset_at':a.get('cycle_end')},ts)
            else:
                for w,q in a.items():
                    if not isinstance(q,dict): continue
                    if 'percent' in q: v={'used':q['percent'],'limit':100}; unit='percent'
                    else: v={'used':q.get('used'),'limit':q.get('total')}; unit='source_units'
                    # MM-DD source reset has no year: preserve raw, don't invent epoch.
                    yield row(p,'default',w,unit,v,ts,dict(v,reset=q.get('reset')))
        for p in data.get('errors') or {}:
            if p in PROVIDERS: yield row(p,'default','collection','unknown',ts=ts,error='source_error')
        yield from normalize(data.get('push') or {},source+':push',observed)
    else:
        for p,block in data.items():
            if p in PROVIDERS and isinstance(block,dict): yield from accounts(p,block)

def collect(store, local_root=None, push=None, aggregate=None):
    local_root=Path(local_root or os.environ.get('QUOTA_HISTORY_CACHE_DIR',str(Path.home()/'.local/state/quota-reporter')))
    push=Path(push or os.environ.get('QUOTA_HISTORY_PUSH_FILE','/var/lib/quota-reporter/quota_push.json'))
    observed=time.time(); count=0
    sources=[(p+'_cache',p,local_root/(p+'.json')) for p in ('codex','cursor','mimo')]
    sources.append(('106_push',None,push))
    for source,p,path in sources:
        try:
            for s in normalize(json.loads(path.read_text()),source,observed,p): store.append(s); count+=1
        except Exception:
            store.append(dict(provider=p or 'aggregate',account='default',source=source,window='collection',units='unknown',source_time=None,observed_time=observed,error='cache_read_failed'))
    if aggregate is not None:
        try:
            # Fixed argv and remote command only. Never import/call quota_collect().
            host=os.environ.get('QUOTA_HISTORY_SECONDARY_HOST','monitor-secondary')
            if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.@-]{0,200}',host): raise ValueError('invalid configured host')
            raw=subprocess.run(['ssh','-o','BatchMode=yes','-o','ConnectTimeout=8',host,'cat /opt/notes-site/quota_cache.json'],check=True,capture_output=True,timeout=15).stdout
            for s in normalize(json.loads(raw),'124_cache',observed): store.append(s); count+=1
        except Exception:
            for p in PROVIDERS:
                store.append(dict(provider=p,account='default',source='124_cache',window='collection',units='unknown',source_time=None,observed_time=observed,error='aggregate_cache_read_failed'))
    return count

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--db',default='/var/lib/quota-history/history.sqlite3'); ap.add_argument('--include-124-cache',action='store_true'); args=ap.parse_args()
    print(json.dumps({'appended_or_existing':collect(Store(args.db),aggregate=True if args.include_124_cache else None)}))
if __name__=='__main__': main()
