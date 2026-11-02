"""Authenticated account-scoped notification inbox and device registry.

The host supplies the authenticated numeric account ID. No client chooses it.
Push tokens are private delivery credentials, never returned in API responses.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import time
from .store import Store

CATEGORIES={'quota':True,'balance':True,'server':True,'reset':True,'recovery':True}
TITLES={'quota_low':'订阅额度不足','quota_recovered':'订阅额度恢复','quota_reset':'订阅额度已重置','balance_low':'账户余额不足','balance_recovered':'账户余额恢复','monitor_unreachable':'服务器监控不可达','server_anomaly':'服务器资源异常','server_recovered':'服务器状态恢复'}
ID=re.compile(r'^[A-Za-z0-9_-]{1,128}$')

class NotificationService:
 def __init__(self,path,push_status=None):
  self.path=str(path);self.push_status=push_status or {'ios':'not_configured','android':'client_monitor'}
  Path(path).parent.mkdir(mode=0o700,parents=True,exist_ok=True)
  with Store(path):pass
  os.chmod(path,0o600)
  with self.db() as c:c.executescript('''
   CREATE TABLE IF NOT EXISTS notification_settings(account_id TEXT PRIMARY KEY,payload TEXT NOT NULL);
   CREATE TABLE IF NOT EXISTS notification_reads(account_id TEXT NOT NULL,event_id TEXT NOT NULL,read_at REAL NOT NULL,PRIMARY KEY(account_id,event_id));
   CREATE TABLE IF NOT EXISTS notification_devices(installation_id TEXT PRIMARY KEY,account_id TEXT NOT NULL,platform TEXT NOT NULL,token TEXT NOT NULL,token_hash TEXT NOT NULL,active INTEGER NOT NULL,updated_at REAL NOT NULL);
   CREATE UNIQUE INDEX IF NOT EXISTS notification_active_token ON notification_devices(platform,token_hash) WHERE active=1;
  ''')
 def db(self):return sqlite3.connect(self.path,timeout=8)
 def handle(self,method,path,account_id,body):
  if account_id is None:return 401,{'error':'authentication_required'}
  # Existing quota and monitor sources are personal-owner-only; do not widen them.
  if type(account_id) is not int or account_id!=1:return 403,{'error':'notifications_owner_only'}
  if not isinstance(body,dict):return 400,{'error':'invalid_body'}
  owner=str(account_id)
  with self.db() as c:
   if method=='GET' and path=='/api/hub/notifications':
    row=c.execute('SELECT payload FROM notification_settings WHERE account_id=?',(owner,)).fetchone()
    settings=dict(CATEGORIES,**(json.loads(row[0]) if row else {}))
    rows=c.execute('SELECT e.payload,r.read_at FROM alert_events e LEFT JOIN notification_reads r ON r.account_id=e.account_id AND r.event_id=e.id WHERE e.account_id=? ORDER BY e.source_time DESC,e.id LIMIT 100',(owner,)).fetchall()
    items=[]
    for payload,read_at in rows:
     e=json.loads(payload);items.append({k:e.get(k) for k in ('id','series_id','type','source_time','window')})
     items[-1].update(title=TITLES.get(e.get('type'),'状态更新'),read=read_at is not None)
    unread=c.execute('SELECT count(*) FROM alert_events e LEFT JOIN notification_reads r ON r.account_id=e.account_id AND r.event_id=e.id WHERE e.account_id=? AND r.read_at IS NULL',(owner,)).fetchone()[0]
    return 200,{'items':items,'unread':unread,'settings':settings,'push':self.push_status,'thresholds':{'CNY':5,'USD':1,'subscription_remaining_percent':10}}
   if method=='POST' and path=='/api/hub/notifications/settings':
    if not body or set(body)-CATEGORIES.keys() or any(type(v) is not bool for v in body.values()):return 400,{'error':'invalid_settings'}
    row=c.execute('SELECT payload FROM notification_settings WHERE account_id=?',(owner,)).fetchone();settings=dict(CATEGORIES,**(json.loads(row[0]) if row else {}));settings.update(body)
    c.execute('INSERT INTO notification_settings VALUES(?,?) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload',(owner,json.dumps(settings)))
    return 200,{'settings':settings}
   if method=='POST' and path=='/api/hub/notifications/read':
    ids=body.get('ids')
    if set(body)!={'ids'} or not isinstance(ids,list) or not 1<=len(ids)<=100 or any(not isinstance(v,str) or not ID.fullmatch(v) for v in ids):return 400,{'error':'invalid_event_ids'}
    for eid in set(ids):c.execute('INSERT OR IGNORE INTO notification_reads SELECT account_id,id,? FROM alert_events WHERE account_id=? AND id=?',(time.time(),owner,eid))
    return 200,{'ok':True}
   if method in ('POST','DELETE') and path=='/api/hub/notifications/devices':
    installation=body.get('installation_id')
    if not isinstance(installation,str) or not ID.fullmatch(installation):return 400,{'error':'invalid_installation'}
    if method=='DELETE':
     if set(body)!={'installation_id'}:return 400,{'error':'invalid_body'}
     c.execute('UPDATE notification_devices SET active=0,token=?,updated_at=? WHERE installation_id=? AND account_id=?',('',time.time(),installation,owner))
     return 200,{'ok':True}
    platform=body.get('platform');token=body.get('token')
    if set(body)!={'installation_id','platform','token'} or platform not in ('ios','android') or not isinstance(token,str):return 400,{'error':'invalid_device'}
    if platform=='ios' and not re.fullmatch(r'[0-9a-fA-F]{64}',token) or platform=='android' and not re.fullmatch(r'[A-Za-z0-9:_-]{20,4096}',token):return 400,{'error':'invalid_token'}
    if platform=='ios':token=token.lower()
    digest=hashlib.sha256(token.encode()).hexdigest()
    c.execute('BEGIN IMMEDIATE')
    existing=c.execute('SELECT account_id,active FROM notification_devices WHERE installation_id=?',(installation,)).fetchone()
    if existing and existing[0]!=owner and existing[1]:return 409,{'error':'installation_belongs_to_other_account'}
    # Replace a rotated token without retaining the old credential or duplicate delivery.
    c.execute('UPDATE notification_devices SET active=0,token=? WHERE platform=? AND token_hash=?',('',platform,digest))
    c.execute('INSERT INTO notification_devices VALUES(?,?,?,?,?,1,?) ON CONFLICT(installation_id) DO UPDATE SET account_id=excluded.account_id,platform=excluded.platform,token=excluded.token,token_hash=excluded.token_hash,active=1,updated_at=excluded.updated_at',(installation,owner,platform,token,digest,time.time()))
    return 200,{'ok':True,'channel':self.push_status.get(platform,'not_configured')}
  return 404,{'error':'notification_route_not_found'}
