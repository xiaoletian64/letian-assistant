import tempfile
import unittest
from pathlib import Path
from server.quota_history.history import Store

class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.tmp.name) / 'history.sqlite3')
    def tearDown(self):
        self.tmp.cleanup()
    def snap(self, t, **kw):
        return dict(provider='codex', account='a', source='cache', window='weekly', units='percent', source_time=t, observed_time=t, used=10, remaining=90, limit=100, **kw)
    def add(self, t, **kw):
        s=self.snap(t); s.update(kw); return self.store.append(s)
    def latest(self): return self.store.query()['items'][0]
    def test_cumulative(self):
        self.add(100, reset_at=200); self.add(110, used=15, remaining=85, reset_at=200)
        self.assertEqual(self.latest()['delta'], 5)
        self.assertEqual(self.latest()['delta_basis'], 'estimated')
    def test_unknown_period_never_estimates_consumption(self):
        self.add(100); self.add(110, used=15)
        self.assertIsNone(self.latest()['delta'])
    def test_duplicate(self):
        self.add(100); self.add(100, observed_time=120)
        self.assertEqual(len(self.store.query()['items']), 1)
    def test_unexpected_reset_and_grant_candidates(self):
        self.add(100); self.add(110, used=2, remaining=98)
        self.assertEqual(self.latest()['event'], 'candidate')
        self.assertIsNone(self.latest()['delta'])
        self.add(120, used=2, remaining=110, limit=120)
        self.assertEqual(self.latest()['event'], 'candidate')
        self.assertIsNone(self.latest()['delta'])
    def test_known_reset_boundary(self):
        self.add(100, reset_at=105); self.add(110, used=1)
        self.assertEqual(self.latest()['event'], 'inferred')
    def test_confirmed(self):
        self.add(100); self.add(110, reset_basis='source_explicit')
        self.assertEqual(self.latest()['event'], 'confirmed')
    def test_missing_failure_and_out_of_order(self):
        self.add(100); self.add(110, used=None, remaining=None, error='fetch_failed')
        self.assertIsNone(self.latest()['delta'])
        self.add(90, used=0, remaining=100)
        self.assertIsNone(self.latest()['event'])
        self.assertEqual(len(self.store.query()['items']), 3)
    def test_whitelist_and_filters(self):
        self.add(100, raw={'used': 10, 'token':'secret', 'nested':{'key':'secret'}})
        self.assertEqual(self.latest()['raw'], {'used':10})
        self.assertEqual(self.store.query(provider='other')['items'], [])
        with self.assertRaises(ValueError): self.store.query(sql='delete')
    def test_pagination(self):
        self.add(100); self.add(110)
        page=self.store.query(limit=1)
        self.assertEqual(len(self.store.query(cursor=page['next_cursor'])['items']),1)

if __name__ == '__main__': unittest.main()

class StorageSafetyTests(unittest.TestCase):
 def test_large_integer_and_delta_roundtrip_exactly(self):
  with tempfile.TemporaryDirectory() as d:
   store=Store(Path(d)/'db'); n=9007199254740993
   common=dict(provider='mimo',account='a',source='cache',window='month',units='credits',limit=n+100,reset_at=300)
   store.append(dict(common,source_time=100,observed_time=100,used=n))
   store.append(dict(common,source_time=110,observed_time=110,used=n+1))
   item=store.query()['items'][0]
   self.assertEqual(item['used'],n+1)
   self.assertEqual(item['delta'],1)
 def test_failures_without_source_time_preserve_each_attempt(self):
  with tempfile.TemporaryDirectory() as d:
   store=Store(Path(d)/'db'); common=dict(provider='codex',account='a',source='cache',window='collection',units='unknown',error='fetch_failed')
   store.append(dict(common,observed_time=100)); store.append(dict(common,observed_time=100)); store.append(dict(common,observed_time=160))
   self.assertEqual(len(store.query()['items']),2)
 def test_private_creation_and_indexed_series_lookup(self):
  import os,sqlite3
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'private'/'db'; Store(path)
   self.assertEqual(os.stat(path.parent).st_mode & 0o777,0o700)
   self.assertEqual(os.stat(path).st_mode & 0o777,0o600)
   with sqlite3.connect(path) as db:
    indexes={r[1] for r in db.execute('PRAGMA index_list(snapshots)')}
   self.assertIn('snapshots_series',indexes)
