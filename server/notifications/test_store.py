import tempfile
import unittest
from dataclasses import replace
from server.notifications.rules import Observation
from server.notifications.store import Store

class StoreTests(unittest.TestCase):
    def test_persistence_duplicate_and_account_isolation(self):
        with tempfile.TemporaryDirectory() as d:
            path=d+'/test.sqlite'; o=Observation('a','canonical',100,'balance',4,'CNY')
            with Store(path) as s:
                self.assertEqual(len(s.process(o)),1)
            with Store(path) as s:
                self.assertEqual(s.process(o),[])
                self.assertEqual(len(s.process(replace(o,account_id='b'))),1)
                self.assertEqual(len(s.list_events('a')),1)
                self.assertEqual(len(s.list_events('b')),1)
                self.assertEqual(s.process(replace(o,source_time=101,value=5)),[])
                self.assertEqual(s.process(replace(o,source_time=102,value=6))[0]['type'],'balance_recovered')
    def test_windows_and_sources_independent_mirrors_share_identity(self):
        with Store(':memory:') as s:
            o=Observation('a','canonical',100,'subscription',.05,'ratio')
            self.assertEqual(len(s.process(o)),1)
            self.assertEqual(s.process(o),[])
            self.assertEqual(len(s.process(replace(o,window='weekly'))),1)
            self.assertEqual(len(s.process(replace(o,series_id='another-source'))),1)
            self.assertEqual(len(s.list_events('a')),3)
    def test_restart_preserves_server_duration(self):
        with tempfile.TemporaryDirectory() as d:
            p=d+'/test.sqlite'; o=Observation('a','host/cpu',100,'server',90,'percent')
            with Store(p) as s: self.assertEqual(s.process(o),[])
            with Store(p) as s: self.assertEqual(s.process(replace(o,source_time=400))[0]['type'],'server_anomaly')
