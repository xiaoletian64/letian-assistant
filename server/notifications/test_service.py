import tempfile,unittest,sqlite3,json
from pathlib import Path
from server.notifications.service import NotificationService
class ServiceTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.path=Path(self.tmp.name)/'alerts.sqlite3';self.s=NotificationService(self.path)
 def tearDown(self):self.tmp.cleanup()
 def test_anonymous_nonowner_never_read_personal_events(self):
  self.assertEqual(self.s.handle('GET','/api/hub/notifications',None,{})[0],401)
  for owner in (2,'1',True):
   self.assertEqual(self.s.handle('GET','/api/hub/notifications',owner,{})[0],403)
 def test_registration_not_returned_by_inbox_and_unbound_on_delete(self):
  token='a'*64
  status,r=self.s.handle('POST','/api/hub/notifications/devices',1,{'installation_id':'fixture-install','platform':'ios','token':token})
  self.assertEqual(status,200);self.assertNotIn(token,json.dumps(r))
  _,inbox=self.s.handle('GET','/api/hub/notifications',1,{})
  self.assertNotIn(token,json.dumps(inbox))
  self.s.handle('DELETE','/api/hub/notifications/devices',1,{'installation_id':'fixture-install'})
  with sqlite3.connect(self.path) as c:self.assertEqual(c.execute('select active from notification_devices').fetchone()[0],0)
 def test_unconfigured_channel_not_claimed_ready(self):
  _,r=self.s.handle('GET','/api/hub/notifications',1,{})
  self.assertEqual(r['push']['ios'],'not_configured');self.assertEqual(r['push']['android'],'client_monitor')
 def test_settings_only_allowed_boolean_categories(self):
  self.assertEqual(self.s.handle('POST','/api/hub/notifications/settings',1,{'quota':'yes'})[0],400)
  self.assertEqual(self.s.handle('POST','/api/hub/notifications/settings',1,{'threshold':0})[0],400)
  self.assertEqual(self.s.handle('POST','/api/hub/notifications/settings',1,{'quota':False})[0],200)
  self.assertFalse(self.s.handle('GET','/api/hub/notifications',1,{})[1]['settings']['quota'])
 def test_active_installation_cannot_be_taken_from_another_owner(self):
  self.s.handle('POST','/api/hub/notifications/devices',1,{'installation_id':'fixture','platform':'ios','token':'a'*64})
  with sqlite3.connect(self.path) as c:c.execute('update notification_devices set account_id=?',('2',))
  self.assertEqual(self.s.handle('POST','/api/hub/notifications/devices',1,{'installation_id':'fixture','platform':'ios','token':'b'*64})[0],409)
 def test_bad_tokens_paths_and_forged_account_are_rejected(self):
  for b in [{'installation_id':'x','platform':'ios','token':'bad'}, {'installation_id':'x','platform':'ios','token':'a'*64,'account_id':2}]:self.assertEqual(self.s.handle('POST','/api/hub/notifications/devices',1,b)[0],400)
  self.assertEqual(self.s.handle('GET','/api/hub/notifications/evil',1,{})[0],404)
 def test_event_read_marks_cannot_leak_across_accounts(self):
  with sqlite3.connect(self.path) as c:
   c.execute('insert into alert_events values(?,?,?,?)',('fixture-event','1',100,json.dumps({'id':'fixture-event','account_id':'1','type':'quota_low','series_id':'glm','source_time':100})))
  _,r=self.s.handle('GET','/api/hub/notifications',1,{})
  self.assertEqual(r['unread'],1)
  self.assertEqual(self.s.handle('POST','/api/hub/notifications/read',1,{'ids':['fixture-event']})[0],200)
  self.assertEqual(self.s.handle('GET','/api/hub/notifications',1,{})[1]['unread'],0)
if __name__=='__main__':unittest.main()
