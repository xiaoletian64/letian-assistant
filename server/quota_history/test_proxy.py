import unittest
from server.quota_history.proxy import parse_query, handle

class ProxyTests(unittest.TestCase):
 def test_valid_and_invalid_queries(self):
  self.assertEqual(parse_query('provider=example&limit=20&cursor=10'), {'provider':'example','limit':20,'cursor':10})
  for query in ['limit=1&limit=2','unknown=x','limit=201','limit=0','from=nan','from=20&to=10','cursor=-1','provider=','window=%00','from=inf']:
   with self.subTest(query=query):
    with self.assertRaises(ValueError):parse_query(query)
 def test_auth_and_validation_do_not_invoke_rpc(self):
  calls=[]
  def rpc(params):calls.append(params);return {'items':[],'next_cursor':None}
  class H:
   def __init__(self,user,path):self.user=user;self.path=path
   def _auth(self,c):return self.user,None
   def _json(self,status,body):return status,body
  for user,path,status in [(None,'/api/hub/quota/history',401),({'user_id':5},'/api/hub/quota/history',403),({'user_id':1},'/api/hub/quota/history?limit=1&limit=2',400),({'user_id':1},'/api/hub/quota/history?limit=1',200)]:
   self.assertEqual(handle(H(user,path),None,rpc)[0],status)
  self.assertEqual(calls,[{'limit':1}])
 def test_backend_details_are_not_exposed(self):
  class H:
   path='/api/hub/quota/history'
   def _auth(self,c):return {'user_id':1},None
   def _json(self,s,b):return s,b
  def fail(params):raise RuntimeError('private host credentials')
  self.assertEqual(handle(H(),None,fail),(503,{'error':'history_unavailable'}))
