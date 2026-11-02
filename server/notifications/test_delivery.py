import tempfile,sqlite3,json,unittest
from pathlib import Path
from server.notifications.service import NotificationService
from server.notifications.delivery import deliver
class DeliveryTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.path=Path(self.tmp.name)/'n.sqlite3';s=NotificationService(self.path);s.handle('POST','/api/hub/notifications/devices',1,{'installation_id':'fixture','platform':'ios','token':'a'*64})
 def tearDown(self):self.tmp.cleanup()
 def event(self,eid='event',ts=100,kind='quota_low'):
  e={'id':eid,'account_id':'1','source_time':ts,'series_id':'glm','type':kind}
  with sqlite3.connect(self.path) as c:c.execute('insert into alert_events values(?,?,?,?)',(eid,'1',ts,json.dumps(e)))
 def test_acceptance_is_not_device_receipt_and_no_replay(self):
  self.event();calls=[]
  def send(d,p):calls.append(p);return {'status':'accepted'}
  deliver(self.path,send,now=101);deliver(self.path,send,now=102)
  self.assertEqual(len(calls),1);self.assertNotIn('glm',json.dumps(calls));self.assertEqual(calls[0]['aps']['alert']['body'],'请打开乐天助手查看最新状态')
  with sqlite3.connect(self.path) as c:self.assertEqual(c.execute('select status from notification_delivery').fetchone()[0],'accepted')
 def test_expired_and_superseded_events_not_sent(self):
  self.event('old',100);self.event('new',200,'quota_recovered');calls=[]
  deliver(self.path,lambda d,p:calls.append(p) or {'status':'accepted'},now=201)
  self.assertEqual(len(calls),1);self.assertEqual(calls[0]['event_id'],'new')
  self.event('expired',201);deliver(self.path,lambda d,p:calls.append(p),now=999);self.assertEqual(len(calls),1)
 def test_disabled_categories_never_send(self):
  NotificationService(self.path).handle('POST','/api/hub/notifications/settings',1,{'quota':False});self.event();calls=[]
  deliver(self.path,lambda d,p:calls.append(p),now=101);self.assertFalse(calls)
 def test_missing_provider_does_not_claim_delivery_or_retry_unknown(self):
  self.event();deliver(self.path,lambda d,p:{'status':'not_configured'},now=101)
  with sqlite3.connect(self.path) as c:self.assertEqual(c.execute('select status from notification_delivery').fetchone()[0],'not_configured')
 def test_old_invalid_token_does_not_revoke_rotated_token(self):
  self.event()
  def sender(device,payload):
   NotificationService(self.path).handle('POST','/api/hub/notifications/devices',1,{'installation_id':'fixture','platform':'ios','token':'b'*64})
   return {'status':'invalid_token'}
  deliver(self.path,sender,now=101)
  with sqlite3.connect(self.path) as c:self.assertEqual(c.execute('select active,token from notification_devices').fetchone(),(1,'b'*64))
 def test_unbind_during_batch_prevents_later_send(self):
  service=NotificationService(self.path)
  service.handle('POST','/api/hub/notifications/devices',1,{'installation_id':'second','platform':'ios','token':'b'*64})
  self.event();calls=[]
  def sender(device,payload):
   calls.append(device['installation_id'])
   other='second' if device['installation_id']=='fixture' else 'fixture'
   service.handle('DELETE','/api/hub/notifications/devices',1,{'installation_id':other})
   return {'status':'accepted'}
  deliver(self.path,sender,now=101)
  self.assertEqual(len(calls),1)
 def test_unconfigured_owner_events_are_not_delivered(self):
  self.event()
  with sqlite3.connect(self.path) as c:
   c.execute('update alert_events set account_id=?',('2',))
   c.execute('update notification_devices set account_id=?',('2',))
  calls=[];deliver(self.path,lambda d,p:calls.append(p) or {'status':'accepted'},now=101)
  self.assertEqual(calls,[])
 def test_invalid_device_deactivated_without_returning_token(self):
  self.event();result=deliver(self.path,lambda d,p:{'status':'invalid_token'},now=101)
  self.assertNotIn('a'*64,json.dumps(result))
  with sqlite3.connect(self.path) as c:self.assertEqual(c.execute('select active from notification_devices').fetchone()[0],0)
if __name__=='__main__':unittest.main()
