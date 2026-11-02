"""Private timer worker: existing caches and fixed monitor targets only."""
from dataclasses import replace
import argparse
import json
import os
from pathlib import Path
import sqlite3
import time
from .rules import series_key
from .store import Store
from .service import NotificationService
from .delivery import deliver
from .gateway import GatewaySender,configuration,push_status
from .observations import quota_observations,server_observations

def process_observations(path,observations):
 result=[]
 with Store(path) as store:
  c=store.connection;c.execute('CREATE TABLE IF NOT EXISTS notification_observation(series_key TEXT PRIMARY KEY,payload TEXT NOT NULL)');c.commit()
  for original in observations:
   o=original;key=series_key(o);r=c.execute('SELECT payload FROM notification_observation WHERE series_key=?',(key,)).fetchone();previous=json.loads(r[0]) if r else {}
   if o.source_time<=previous.get('source_time',float('-inf')):continue
   boundary=previous.get('boundary');used=previous.get('used')
   if o.valid and o.fresh and o.kind=='subscription' and previous and o.source_time-previous['source_time']<=5400 and o.cycle!=previous.get('cycle') and boundary is not None and previous['source_time']<boundary<=o.source_time and used is not None and o.current_used is not None and o.current_used<used:
    o=replace(o,reset_evidence='verified_cycle',reset_boundary=boundary,previous_used=used)
   result.extend(store.process(o))
   if original.valid and original.fresh:
    baseline={'source_time':original.source_time,'cycle':original.cycle,'boundary':original.reset_boundary,'used':original.current_used}
    c.execute('INSERT INTO notification_observation VALUES(?,?) ON CONFLICT(series_key) DO UPDATE SET payload=excluded.payload',(key,json.dumps(baseline,allow_nan=False)));c.commit()
 return result

def main():
 p=argparse.ArgumentParser();p.add_argument('--db',required=True);p.add_argument('--quota-cache',required=True);p.add_argument('--monitor-config',required=True);a=p.parse_args()
 NotificationService(a.db)
 now=time.time();raw=json.loads(Path(a.quota_cache).read_text())
 from server.monitor.aggregator import load_private
 snapshot=load_private(a.monitor_config).snapshot()
 events=process_observations(a.db,[*quota_observations(raw,now),*server_observations(snapshot,now)])
 results=deliver(a.db,GatewaySender(configuration()),now=time.time())
 print(json.dumps({'ok':True,'new_events':len(events),'delivery_attempts':len(results),'source':'existing_caches_and_fixed_monitor','push':push_status()}))
if __name__=='__main__':main()
