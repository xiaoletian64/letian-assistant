import unittest
from server.notifications.send_rpc import respond
class RPCTests(unittest.TestCase):
 def test_default_not_configured_and_no_secrets_in_status(self):
  self.assertEqual(respond({'op':'status'},sender=None),{'ios':'not_configured'})
 def test_host_urls_and_arbitrary_messages_rejected(self):
  for request in [{'op':'send','host':'evil.test'},{'op':'send','token':'a'*64,'event_id':'../private'},{'op':'send','token':'a'*64,'event_id':'e','message':'private text'}]:
   with self.subTest(request=request):self.assertEqual(respond(request,lambda d,p:{'status':'accepted'})['status'],'rejected')
 def test_safe_sender_receives_fixed_payload(self):
  calls=[]
  def sender(d,p):calls.append((d,p));return {'status':'accepted'}
  self.assertEqual(respond({'op':'send','token':'a'*64,'event_id':'fixture-event'},sender)['status'],'accepted')
  self.assertEqual(calls[0][0]['platform'],'ios');self.assertEqual(calls[0][1]['aps']['alert']['title'],'乐天助手状态提醒')
if __name__=='__main__':unittest.main()
