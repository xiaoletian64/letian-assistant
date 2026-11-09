"""Bounded private push outbox. Acceptance never means device receipt."""
import json
import hashlib
import sqlite3
import time
from .service import CATEGORIES

def enabled(kind,settings):
 category='daily' if kind=='daily_digest' else 'server' if kind.startswith(('server_','monitor_')) else 'balance' if kind.startswith('balance_') else 'quota'
 return settings.get(category,True) and (not kind.endswith('_recovered') or settings.get('recovery',True)) and (kind!='quota_reset' or settings.get('reset',True))

def deliver(path,sender,now=None,account_id="1"):
 if str(account_id)!='1':raise ValueError('unconfigured_notification_owner')
 now=time.time() if now is None else now;results=[]
 with sqlite3.connect(path,timeout=8) as c:
  c.execute('''CREATE TABLE IF NOT EXISTS notification_delivery(event_id TEXT NOT NULL,installation_id TEXT NOT NULL,status TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,next_attempt REAL NOT NULL DEFAULT 0,updated_at REAL NOT NULL,PRIMARY KEY(event_id,installation_id))''')
  # A worker lost after claiming may already have delivered. Never blindly replay.
  c.execute("UPDATE notification_delivery SET status='unknown',updated_at=? WHERE status='sending' AND updated_at<?",(now,now-300))
  events=c.execute('SELECT id,account_id,source_time,payload FROM alert_events WHERE account_id=? AND source_time>=? ORDER BY source_time,id LIMIT 500',(str(account_id),now-300)).fetchall()
  latest={}
  for eid,owner,ts,payload in events:
   e=json.loads(payload);latest[(owner,e['series_id'])]=eid
  for eid,owner,ts,payload in events:
   e=json.loads(payload)
   row=c.execute('SELECT payload FROM notification_settings WHERE account_id=?',(owner,)).fetchone();settings=dict(CATEGORIES,**(json.loads(row[0]) if row else {}))
   if latest[(owner,e['series_id'])]!=eid or not enabled(e['type'],settings):continue
   for installation, in c.execute('SELECT installation_id FROM notification_devices WHERE account_id=? AND active=1',(owner,)).fetchall():
    c.execute("INSERT OR IGNORE INTO notification_delivery(event_id,installation_id,status,updated_at) VALUES(?,?,'queued',?)",(eid,installation,now))
  c.commit()
  pending=c.execute("SELECT q.event_id,q.installation_id,q.attempts,e.account_id,e.source_time,e.payload,d.platform,d.token FROM notification_delivery q JOIN alert_events e ON e.id=q.event_id JOIN notification_devices d ON d.installation_id=q.installation_id AND d.account_id=e.account_id AND d.active=1 WHERE e.account_id=? AND q.status IN ('queued','retry','not_configured') AND q.next_attempt<=? ORDER BY e.source_time LIMIT 50",(str(account_id),now,)).fetchall()
  for eid,installation,attempts,owner,ts,raw,platform,token in pending:
   e=json.loads(raw)
   row=c.execute('SELECT payload FROM notification_settings WHERE account_id=?',(owner,)).fetchone();settings=dict(CATEGORIES,**(json.loads(row[0]) if row else {}))
   if ts<now-300 or latest.get((owner,e['series_id']))!=eid or not enabled(e['type'],settings):
    c.execute("UPDATE notification_delivery SET status='expired',updated_at=? WHERE event_id=? AND installation_id=?",(now,eid,installation));c.commit();continue
   c.execute('BEGIN IMMEDIATE')
   current=c.execute('SELECT platform,token FROM notification_devices WHERE installation_id=? AND account_id=? AND active=1',(installation,owner)).fetchone()
   if not current:
    c.execute("UPDATE notification_delivery SET status='cancelled',updated_at=? WHERE event_id=? AND installation_id=?",(now,eid,installation));c.commit();continue
   platform,token=current
   sent_token_hash=hashlib.sha256(token.encode()).hexdigest()
   claimed=c.execute("UPDATE notification_delivery SET status='sending',attempts=attempts+1,updated_at=? WHERE event_id=? AND installation_id=? AND status IN ('queued','retry','not_configured')",(now,eid,installation)).rowcount;c.commit()
   if not claimed:continue
   payload={'aps':{'alert':{'title':'乐天助手状态提醒','body':'请打开乐天助手查看最新状态'},'sound':'default'},'event_id':eid}
   try:r=sender({'platform':platform,'token':token,'installation_id':installation},payload);status=r.get('status','unknown')
   except Exception:status='unknown'
   if status not in ('accepted','not_configured','invalid_token','retry','rejected','unknown'):status='unknown'
   if status=='retry' and attempts>=2:status='rejected'
   delay=60*(2**min(attempts,2)) if status=='retry' else 60 if status=='not_configured' else 0
   c.execute('UPDATE notification_delivery SET status=?,next_attempt=?,updated_at=? WHERE event_id=? AND installation_id=?',(status,now+delay,now,eid,installation))
   if status=='invalid_token':c.execute('UPDATE notification_devices SET active=0,token=? WHERE installation_id=? AND platform=? AND token_hash=?',('',installation,platform,sent_token_hash))
   c.commit();results.append({'event_id':eid,'status':status})
 return results
