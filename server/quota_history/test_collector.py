import unittest
from server.quota_history.collector import normalize
class CollectorTests(unittest.TestCase):
 def test_aggregate_errors_and_unknown_reset(self):
  rows=list(normalize({'accounts':{'opencode':{'weekly':{'percent':40,'reset':'11-03 12:00'}},'deepseek':{'amount':'12.3','currency':'CNY'}},'errors':{'zhipu':'HTTPError'},'collected_at':'2026-11-02T12:00:00+08:00'},'124_cache',10))
  self.assertEqual(len(rows),3)
  self.assertIsNone(rows[0]['reset_at'])
  self.assertEqual(rows[0]['raw']['reset'],'11-03 12:00')
  self.assertEqual(rows[1]['remaining'],12.3)
  self.assertEqual(rows[2]['error'],'source_error')
 def test_push_all_providers_and_raw_text(self):
  rows=list(normalize({'codex':{'accounts':[{'n':'one','fh':{'u':20,'reset_at':100},'ts':10}]},'mimo':{'accounts':[{'n':'m','rem':'unknown credits','ts':10}]},'gha':{'personal':{'used':3,'included':100,'left':97},'updated':10}},'106_push',11))
  self.assertEqual({r['provider'] for r in rows},{'codex','mimo','gha'})
  self.assertEqual(rows[1]['raw']['rem'],'unknown credits')
  self.assertIsNone(rows[1]['used'])
 def test_mimo_direct_and_cursor_direct(self):
  rows=list(normalize({'observedAt':10,'accounts':[{'n':'m','quota':{'used':3,'remaining':7,'limit':10}}],'periodEndUTC':'2026-11-03T00:00:00Z'},'mimo_cache',11,provider='mimo'))
  self.assertEqual(rows[0]['units'],'credits')
  self.assertEqual(rows[0]['used'],3)
  rows=list(normalize({'observedAt':10,'percentages':{'totalPercentUsed':30}},'cursor_cache',11,provider='cursor'))
  self.assertEqual(rows[0]['used'],30)
 def test_failed_check_preserves_success_and_failure(self):
  rows=list(normalize({'observedAt':10,'lastCheckAt':20,'lastError':'sensitive body','accounts':[{'n':'m','quota':{'used':3}}]},'mimo_cache',21,provider='mimo'))
  self.assertEqual(len(rows),2)
  self.assertEqual(rows[0]['error'],'source_error')
  self.assertEqual(rows[0]['source_time'],20)
  self.assertEqual(rows[1]['used'],3)
 def test_mimo_plan_expiry_is_not_quota_reset(self):
  rows=list(normalize({'observedAt':10,'periodEndUTC':'2027-01-01T00:00:00Z','accounts':[{'n':'m','quota':{'used':3,'remaining':7,'limit':10}}]},'mimo_cache',11,provider='mimo'))
  self.assertIsNone(rows[0]['reset_at'])
  self.assertEqual(rows[0]['raw']['plan_expires_at'],'2027-01-01T00:00:00Z')
 def test_mimo_quota_explicit_reset_and_items_only(self):
  rows=list(normalize({'observedAt':10,'periodEndUTC':'2027-01-01T00:00:00Z','accounts':[{'n':'m','quota':{'used':3,'reset_at':100}}]},'mimo_cache',11,provider='mimo'))
  self.assertEqual(rows[0]['reset_at'],100)
  rows=list(normalize({'observedAt':10,'items':[{'name':'monthly','used':3,'limit':10,'remaining':7}]},'mimo_cache',11,provider='mimo'))
  self.assertEqual(rows[0]['units'],'credits')
  self.assertEqual(rows[0]['used'],3)
  self.assertIsNone(rows[0]['reset_at'])
 def test_codex_401_retains_failure_without_body(self):
  rows=list(normalize({'observedAt':10,'lastCheckAt':20,'lastError':'401 credential-sensitive body','accounts':[{'n':'c','fh':{'u':3}}]},'codex_cache',21,provider='codex'))
  self.assertEqual(rows[0]['error'],'source_error')
  self.assertNotIn('credential-sensitive',str(rows))
 def test_public_sources_contain_no_private_host_or_root_cache(self):
  from pathlib import Path
  source=Path('server/quota_history/collector.py').read_text()
  self.assertNotRegex(source,r'\b(?:\d{1,3}\.){3}\d{1,3}\b')
  self.assertNotIn('/root/',source)
 def test_integer_credits_above_javascript_precision_stay_exact(self):
  from server.quota_history.collector import number
  value=9007199254740993
  self.assertEqual(number(value),value)
  self.assertIsInstance(number(value),int)
  self.assertEqual(number(str(value)),value)
  rows=list(normalize({'observedAt':10,'items':[{'name':'month','used':value,'limit':value+10}]},'mimo_cache',11,provider='mimo'))
  self.assertEqual(rows[0]['used'],value)
