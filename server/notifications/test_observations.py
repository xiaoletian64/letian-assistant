import unittest
from server.notifications.observations import quota_observations,server_observations
class ObservationTests(unittest.TestCase):
 def test_percent_and_balance_unknown_do_not_become_zero(self):
  raw={'collected_at':100,'accounts':{'deepseek':{'amount':'4.99','currency':'CNY'},'zhipu':{'weekly':{'percent':95,'reset':'11-03 12:00'}}}}
  obs=list(quota_observations(raw,now=101));self.assertEqual([o.kind for o in obs],['balance','subscription']);self.assertAlmostEqual(obs[1].value,.05);self.assertIsNone(obs[1].reset_evidence)
 def test_cursor_push_mirror_not_counted_and_mimo_structured(self):
  raw={'collected_at':100,'accounts':{'cursor':{'account_id':'same','total_percent':99}},'push':{'cursor':{'accounts':[{'n':'mirror','account_id':'same','ts':100,'rem':'same'}]},'mimo':{'accounts':[{'n':'m','ts':100,'quota':{'remaining':5,'limit':100}}]}}}
  obs=list(quota_observations(raw,now=101));self.assertEqual(len(obs),2);self.assertEqual([o.value for o in obs],[.01,.05])
 def test_distinct_cursor_push_account_is_not_dropped(self):
  raw={'collected_at':100,'accounts':{'cursor':{'account_id':'first','total_percent':30}},'push':{'cursor':{'accounts':[{'account_id':'different','n':'other','ts':100,'rem':'totalPercentUsed=99% used'}]}}}
  obs=list(quota_observations(raw,now=101))
  self.assertEqual(len(obs),2)
  self.assertEqual(obs[-1].value,.01)
 def test_stale_balance_does_not_alert(self):
  raw={'push':{'jev':{'accounts':[{'n':'j','ts':1,'bal':{'amt':.5,'cur':'USD'}}]}}}
  self.assertFalse(list(quota_observations(raw,now=9999))[0].fresh)
 def test_invalid_server_uses_actual_attempt_time_and_one_availability_series(self):
  obs=list(server_observations({'servers':[{'id':'example','error':'sample_failed','sampled_at':None}]},now=100))
  self.assertEqual(len(obs),4);self.assertEqual(obs[0].source_time,100);self.assertFalse(obs[0].valid);self.assertTrue(all(not o.fresh for o in obs[1:]))
 def test_failed_sample_interrupts_metric_confirmation(self):
  from server.notifications.rules import evaluate
  state={}
  for t in (100,200):
   o=list(server_observations({'servers':[{'id':'a','sampled_at':t,'metrics':{'cpu_percent':95}}]},now=t))[1]
   state,_=evaluate(o,state)
  failure=list(server_observations({'servers':[{'id':'a','error':'sample_failed'}]},now=250))[1]
  state,_=evaluate(failure,state)
  o=list(server_observations({'servers':[{'id':'a','sampled_at':401,'metrics':{'cpu_percent':95}}]},now=401))[1]
  _,events=evaluate(o,state);self.assertEqual(events,[])
 def test_healthy_server_emits_metrics_and_heartbeat(self):
  o=list(server_observations({'servers':[{'id':'a','sampled_at':100,'metrics':{'cpu_percent':90,'memory_percent':40,'disk_percent':50}}]},now=101))
  self.assertEqual(len(o),4);self.assertEqual(o[0].value,0)
if __name__=='__main__':unittest.main()
