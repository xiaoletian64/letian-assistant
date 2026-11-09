import json
from datetime import datetime
from pathlib import Path
import sqlite3
import tempfile
import unittest
from server.notifications.morning import TZ, build, publish, source_export
from server.notifications.service import NotificationService
from server.notifications.delivery import enabled

class MorningTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)/'db.sqlite'
        self.now = datetime(2026,11,9,9,30,tzinfo=TZ)

    def test_unknown_is_not_zero_and_deduplicated_in_owner_inbox(self):
        r = build({}, {'status':'unavailable'}, self.now)
        self.assertIn('昨日总额', build({}, {'day':'2026-11-08'}, self.now)['body'])
        self.assertIn('114：未获取', r['body'])
        self.assertNotIn('166', r['body'])
        self.assertEqual(publish(r,self.path,self.now)['status'],'created')
        self.assertEqual(publish(r,self.path,self.now)['status'],'already_exists')
        service = NotificationService(self.path)
        code, data = service.handle('GET','/api/hub/notifications',1,{})
        self.assertEqual(code,200)
        self.assertEqual(data['items'][0]['body'],r['body'])
        self.assertEqual(service.handle('GET','/api/hub/notifications',2,{})[0],403)
        service.handle('POST','/api/hub/notifications/settings',1,{'daily':False})
        self.assertEqual(publish(r,self.path,self.now)['status'],'disabled')
        self.assertFalse(enabled('daily_digest',{'daily':False,'quota':True}))

    def test_quota_mirror_stale_and_explicit_remaining(self):
        ts = self.now.isoformat()
        cache = {'accounts':{'codex':{'weekly':{'percent':99}}},'collected_at':ts,
                 'push':{'codex':{'accounts':[{'n':'测试账号','ts':ts,'fh':{'u':25}}]}}}
        body = build(cache,{'status':'unavailable'},self.now)['body']
        self.assertIn('75%',body)
        self.assertNotIn('1%',body)
        cache['push']['codex']['accounts'][0]['ts']='2026-11-08T09:30:00+08:00'
        self.assertIn('缓存过期',build(cache,{},self.now)['body'])

    def test_beijing_payment_boundary_currency_and_unknown_creation(self):
        with sqlite3.connect(self.path) as c:
            c.executescript('CREATE TABLE orders(owner TEXT,payload TEXT); CREATE TABLE accounts(owner TEXT,platform TEXT,state TEXT,last_sync TEXT,coverage TEXT);')
            def put(owner, oid, paid, amount=125, parent=None):
                r={'account_id':'a','source_order_id':oid,'source_parent_order_id':parent,'paid_at':paid,'paid_amount_minor':amount,'currency':'CNY','created_at':'2026-11-08T00:00:00Z'}
                c.execute('INSERT INTO orders VALUES(?,?)',(owner,json.dumps(r)))
            put('1','start','2026-11-07T16:00:00Z')
            put('1','end','2026-11-08T16:00:00Z')
            put('1','unknown',None)
            put('1','parent','2026-11-08T01:00:00Z')
            put('1','child','2026-11-08T01:00:00Z',parent='parent')
            put('2','other','2026-11-08T00:00:00Z',99999)
        data=source_export(self.path,self.now)
        self.assertEqual(data['paid_by_currency'],{'CNY':125})
        self.assertEqual(data['unknown_paid_at'],1)
        self.assertEqual(data['ambiguous_parent_rows'],2)

    def test_stale_report_rejected(self):
        r=build({}, {}, self.now)
        r['generated_at']-=301
        with self.assertRaises(ValueError):publish(r,self.path,self.now)

    def test_long_history_stays_within_android_response_limit(self):
        service=NotificationService(self.path)
        with service.db() as c:
            for i in range(100):
                event={'id':str(i),'type':'daily_digest','source_time':i,'body':'早报正文'*1000}
                c.execute('INSERT INTO alert_events VALUES(?,?,?,?)',(str(i),'1',i,json.dumps(event)))
        code,data=service.handle('GET','/api/hub/notifications',1,{})
        self.assertEqual(code,200)
        self.assertLess(len(json.dumps(data).encode()),256*1024)
        self.assertEqual(data['unread'],100)
        self.assertEqual(data['items'][0]['id'],'99')

    def test_codex_window_comes_from_source_duration(self):
        cache={'push':{'codex':{'accounts':[{'n':'合成账号','ts':self.now.timestamp(),'fh':{'u':15,'window_seconds':604800}}]}}}
        body=build(cache,{},self.now)['body']
        self.assertIn('每周窗口：套餐剩余 85%',body)
        self.assertNotIn('5小时窗口',body)

    def test_only_complete_official_daily_bill_is_actual_cost(self):
        bill={'server_id':'106','day':'2026-11-08','basis':'official_daily_bill','coverage_complete':True,'amount_minor':125,'currency':'CNY','evidence_ref':'synthetic-invoice','observed_at':self.now.isoformat()}
        body=build({}, {}, self.now,{'entries':[bill]})['body']
        self.assertIn('106：官方日账单 1.25 CNY',body)
        for change in ({'basis':'estimate'},{'day':'2026-11-07'},{'coverage_complete':False},{'amount_minor':None}):
            body=build({}, {}, self.now,{'entries':[dict(bill,**change)]})['body']
            self.assertNotIn('1.25',body)
        body=build({}, {}, self.now,{'entries':[bill,bill]})['body']
        self.assertNotIn('1.25',body)

if __name__=='__main__':unittest.main()
