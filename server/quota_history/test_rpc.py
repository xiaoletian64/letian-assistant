import tempfile
import unittest
from pathlib import Path
from server.quota_history.history import Store
from server.quota_history.rpc import query
class RpcTests(unittest.TestCase):
 def test_readonly_query(self):
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'db'; Store(path)
   self.assertEqual(query(path,{'limit':'2'})['items'],[])
   with self.assertRaises(ValueError): query(path,{'delete':'all'})
 def test_absent_database_does_not_create(self):
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'missing'
   with self.assertRaises(Exception): query(path,{})
   self.assertFalse(path.exists())
