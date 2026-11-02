import unittest
from dataclasses import replace
from server.notifications.rules import Observation, evaluate

class RulesTests(unittest.TestCase):
    def obs(self, **kw):
        return Observation(**dict(account_id='a', series_id='canonical/provider/account/balance', source_time=100, kind='balance', value=4, unit='CNY', **kw))
    def run_sequence(self, observations):
        state = {}; events = []
        for o in observations:
            state, new = evaluate(o, state); events.extend(new)
        return state, events
    def test_boundaries(self):
        for unit, value, low in [('CNY',5,False),('CNY',4.99,True),('USD',1,False),('USD',.99,True),('EUR',0,False)]:
            _, events=evaluate(replace(self.obs(),unit=unit,value=value),{})
            self.assertEqual(bool(events),low)
        self.assertEqual(evaluate(replace(self.obs(),kind='subscription',unit='ratio',value=.1),{})[1],[])
        self.assertEqual(evaluate(replace(self.obs(),kind='subscription',unit='ratio',value=.099),{})[1][0]['type'],'quota_low')
    def test_low_duplicate_recovery(self):
        o=self.obs()
        _,events=self.run_sequence([o,o,replace(o,source_time=101,value=5),replace(o,source_time=102,value=6)])
        self.assertEqual([e['type'] for e in events],['balance_low','balance_recovered'])
    def test_invalid_breaks_confirmation(self):
        o=self.obs()
        _,events=self.run_sequence([o,replace(o,source_time=101,value=6),replace(o,source_time=102,valid=False),replace(o,source_time=103,value=6)])
        self.assertEqual(len(events),1)
        for kwargs in [dict(value=None),dict(fresh=False),dict(valid=False),dict(value=float('nan')),dict(value=-1)]:
            self.assertEqual(evaluate(replace(o,**kwargs),{})[1],[])
    def test_reset_evidence(self):
        o=replace(self.obs(),kind='subscription',unit='ratio',value=.05)
        _,events=self.run_sequence([o,replace(o,source_time=101,cycle='next',value=1),replace(o,source_time=102,cycle='next',value=1)])
        self.assertNotIn('quota_reset',[e['type'] for e in events])
        _,events=self.run_sequence([o,replace(o,source_time=101,cycle='next',value=1,reset_evidence='source_explicit')])
        self.assertEqual(events[-1]['type'],'quota_reset')
    def test_server_unreachable_and_recovery(self):
        o=replace(self.obs(),kind='server',unit='percent',value=None,valid=False)
        _,events=self.run_sequence([o,replace(o,source_time=130),replace(o,source_time=160),replace(o,source_time=170,valid=True,value=20),replace(o,source_time=180,valid=True,value=20)])
        self.assertEqual([e['type'] for e in events],['monitor_unreachable','server_recovered'])
    def test_server_sustained(self):
        o=replace(self.obs(),kind='server',unit='percent',value=90)
        _,events=self.run_sequence([o,replace(o,source_time=399),replace(o,source_time=400)])
        self.assertEqual([e['type'] for e in events],['server_anomaly'])
    def test_older_and_stale_never_recover(self):
        o=self.obs()
        _,events=self.run_sequence([o,replace(o,source_time=99,value=6),replace(o,source_time=101,value=6,fresh=False),replace(o,source_time=102,value=6)])
        self.assertEqual([e['type'] for e in events],['balance_low'])
    def test_verified_reset_requires_boundary_and_counter(self):
        o=replace(self.obs(),kind='subscription',unit='ratio',value=.05)
        for changes,expected in [(dict(reset_boundary=101,previous_used=95,current_used=0),True),(dict(reset_boundary=99,previous_used=95,current_used=0),False),(dict(reset_boundary=101,previous_used=95,current_used=96),False)]:
            _,events=self.run_sequence([o,replace(o,source_time=102,cycle='next',value=1,reset_evidence='verified_cycle',**changes)])
            self.assertEqual('quota_reset' in [e['type'] for e in events],expected)
    def test_server_failures_must_be_consecutive(self):
        o=replace(self.obs(),kind='server',unit='percent',value=None,valid=False)
        _,events=self.run_sequence([o,replace(o,source_time=130),replace(o,source_time=140,valid=True,value=20),replace(o,source_time=160),replace(o,source_time=200)])
        self.assertEqual(events,[])
    def test_server_high_interruption(self):
        o=replace(self.obs(),kind='server',unit='percent',value=90)
        _,events=self.run_sequence([o,replace(o,source_time=200,value=89),replace(o,source_time=400)])
        self.assertEqual(events,[])
    def test_server_invalid_percentage_does_not_trigger_resource_anomaly(self):
        o=replace(self.obs(),kind='server',unit='percent',value=101)
        _,events=self.run_sequence([o,replace(o,source_time=400)])
        self.assertEqual(events,[])
