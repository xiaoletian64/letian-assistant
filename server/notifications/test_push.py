import unittest
from server.notifications.push import APNsSender
class Response:
 def __init__(self,status,reason=''):self.status_code=status;self.reason=reason
 def json(self):return {'reason':self.reason}
class Client:
 def __init__(self,response):self.response=response;self.calls=[]
 def post(self,*a,**kw):self.calls.append((a,kw));return self.response
class PushTests(unittest.TestCase):
 def config(self):return {'enabled':True,'apns_authorized':True,'environment':'production','topic':'site.zhangyue.vault','team_id':'TESTTEAM','key_id':'TESTKEY','key_file':'/private/synthetic.p8'}
 def test_no_config_no_network(self):
  c=Client(Response(200));self.assertEqual(APNsSender({},client=c,jwt_factory=lambda:'fake')({'platform':'ios','token':'a'*64},{})['status'],'not_configured');self.assertFalse(c.calls)
 def test_acceptance_and_fixed_host_headers(self):
  c=Client(Response(200));s=APNsSender(self.config(),client=c,jwt_factory=lambda:'synthetic')
  self.assertEqual(s({'platform':'ios','token':'a'*64},{'event_id':'fixture','aps':{'alert':{'title':'状态提醒'}}})['status'],'accepted')
  a,kw=c.calls[0];self.assertTrue(a[0].startswith('https://api.push.apple.com/3/device/'));self.assertEqual(kw['headers']['apns-push-type'],'alert');self.assertNotIn('synthetic',str(s({'platform':'android','token':'b'*30},{})))
 def test_invalid_token_and_provider_errors_separate(self):
  for code,reason,status in [(400,'BadDeviceToken','invalid_token'),(410,'Unregistered','invalid_token'),(403,'InvalidProviderToken','rejected'),(429,'TooManyRequests','retry'),(500,'InternalServerError','retry')]:
   with self.subTest(code=code):self.assertEqual(APNsSender(self.config(),client=Client(Response(code,reason)),jwt_factory=lambda:'fake')({'platform':'ios','token':'a'*64},{'event_id':'e'})['status'],status)
if __name__=='__main__':unittest.main()
