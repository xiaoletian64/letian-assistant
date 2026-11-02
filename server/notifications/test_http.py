import unittest,tempfile
from pathlib import Path
from server.notifications.http import handle
from server.notifications.service import NotificationService
class HTTPTests(unittest.TestCase):
 def test_auth_method_body_boundaries(self):
  with tempfile.TemporaryDirectory() as d:
   service=NotificationService(Path(d)/'n.db')
   class Handler:
    command='GET';path='/api/hub/notifications';user=None
    def _auth(self,c):return self.user,None
    def _json(self,status,data):return status,data
    def _body(self,max_size):self.limit=max_size;return self.body
   h=Handler();self.assertEqual(handle(h,None,service)[0],401)
   h.user={'user_id':2};self.assertEqual(handle(h,None,service)[0],403)
   h.user={'user_id':1};self.assertEqual(handle(h,None,service)[0],200)
   h.command='POST';h.path='/api/hub/notifications/settings';h.body={'quota':False};self.assertEqual(handle(h,None,service)[0],200);self.assertEqual(h.limit,16384)
   from unittest.mock import Mock
   fake=Mock()
   h.path='/api/hub/notifications/../other';h.command='POST'
   self.assertEqual(handle(h,None,fake)[0],404);fake.handle.assert_not_called()
   h.path='/api/hub/notifications?account_id=2';h.command='GET';self.assertEqual(handle(h,None,service)[0],400)
if __name__=='__main__':unittest.main()
