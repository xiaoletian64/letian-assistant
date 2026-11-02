import unittest
from aggregator import MonitorAggregator, normalize_charts, CachedMonitor

class MonitorTests(unittest.TestCase):
    def test_selects_latest_source_sample_not_http_time(self):
        data = normalize_charts({'system.cpu': {'labels':['time','user'], 'data':[[100,3],[105,8],[103,5]]}})
        self.assertEqual(data['sampled_at'],'1970-01-01T00:01:45Z')
        self.assertEqual(data['metrics']['cpu_percent'],8)

    def test_actual_root_disk_chart_id(self):
        data = normalize_charts({'disk_space./': {'labels':['time','used','avail','reserved for root'], 'data':[[100,75,25,0]]}})
        self.assertEqual(data['metrics']['disk_percent'],75)

    def test_netdata_units_missing_and_source_timestamp(self):
        data = normalize_charts({'system.cpu': {'labels':['time','user','system','idle'], 'data':[[100,12,3,85]]}, 'system.net': {'labels':['time','received','sent'], 'data':[[100,8,-16]]}})
        self.assertEqual(data['metrics']['cpu_percent'], 15)
        self.assertEqual(data['metrics']['network_rx_bytes_per_second'], 1000)
        self.assertEqual(data['metrics']['network_tx_bytes_per_second'], 2000)
        self.assertIsNone(data['metrics']['memory_percent'])
        self.assertEqual(data['sampled_at'], '1970-01-01T00:01:40Z')

    def test_failures_preserve_safe_identity_without_details(self):
        def fail(_): raise RuntimeError('secret-host secret-token')
        result = MonitorAggregator([{'id':'server-a','display_name':'服务器 A'}], fail).snapshot()
        self.assertEqual(result['servers'][0]['error'], 'sample_failed')
        self.assertNotIn('secret', str(result))
        self.assertIsNone(result['servers'][0]['online'])

    def test_shared_cache_samples_once_per_window(self):
        calls = []
        class Source:
            def snapshot(self):
                calls.append(1)
                return {'servers': []}
        clock = [0]
        cache = CachedMonitor(Source(), ttl=5, clock=lambda: clock[0])
        cache.snapshot()
        cache.snapshot()
        self.assertEqual(len(calls), 1)
        clock[0] = 6
        cache.snapshot()
        self.assertEqual(len(calls), 2)

    def test_rejects_duplicate_or_unsafe_configuration(self):
        with self.assertRaises(ValueError):
            MonitorAggregator([{'id':'a','display_name':'A'}, {'id':'a','display_name':'B'}])
        with self.assertRaises(ValueError):
            MonitorAggregator([{'id':'a','display_name':'A','ssh_alias':'-oProxyCommand=bad'}])

if __name__ == '__main__': unittest.main()

class AuthorizationTests(unittest.TestCase):
    def test_route_requires_owner_and_does_not_sample_forbidden(self):
        from aggregator import handle_status
        class Handler:
            def __init__(self, user): self.user = user
            def _auth(self, connection): return self.user, None
            def _json(self, code, body): return code, body
        class Monitor:
            def snapshot(self): return {'servers': []}
        for user, code in ((None,401), ({'user_id':5},403), ({'user_id':1},200)):
            self.assertEqual(handle_status(Handler(user), None, Monitor())[0],code)
