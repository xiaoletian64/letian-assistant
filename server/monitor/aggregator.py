"""Read-only fixed-target monitor. Authentication belongs to the host API."""
import concurrent.futures
import datetime as dt
import json
import math
import re
import subprocess
import urllib.request

CHARTS = ('system.cpu', 'system.ram', 'disk_space./', 'system.net', 'system.load')
METRICS = ('cpu_percent', 'memory_percent', 'disk_percent', 'network_rx_bytes_per_second', 'network_tx_bytes_per_second', 'load_1m')

def utc(timestamp=None):
    return dt.datetime.fromtimestamp(timestamp, dt.timezone.utc).isoformat().replace('+00:00', 'Z') if timestamp is not None else dt.datetime.now(dt.timezone.utc).isoformat().replace('+00:00', 'Z')

def normalize_charts(charts):
    rows, times = {}, []
    for name, chart in charts.items():
        data = chart.get('data') or []
        if not data: continue
        valid = [row for row in data if row and isinstance(row[0], (int,float)) and math.isfinite(row[0])]
        if not valid: continue
        row = dict(zip(chart.get('labels', []), max(valid, key=lambda row: row[0])))
        rows[name] = row
        if isinstance(row.get('time'), (int, float)): times.append(row['time'])
    def num(row, key):
        value = rows.get(row, {}).get(key)
        return float(value) if isinstance(value, (int,float)) and math.isfinite(value) else None
    def percent(chart, used, free):
        u, f = num(chart, used), num(chart, free)
        total = sum(v for k,v in rows.get(chart, {}).items() if k != 'time' and isinstance(v,(int,float)) and math.isfinite(v))
        return 100*u/total if u is not None and f is not None and total>0 else None
    idle = num('system.cpu','idle')
    cpu = 100-idle if idle is not None else None
    if cpu is None and 'system.cpu' in rows:
        values = [v for k,v in rows['system.cpu'].items() if k not in ('time','idle') and isinstance(v,(int,float)) and math.isfinite(v)]
        cpu = sum(values) if values else None
    rx, tx = num('system.net','received'), num('system.net','sent')
    return {'sampled_at': utc(min(times)) if times else None, 'online': True if times else None,
            'metrics': dict(zip(METRICS, (cpu, percent('system.ram','used','free'), percent('disk_space./','used','avail'), abs(rx)*125 if rx is not None else None, abs(tx)*125 if tx is not None else None, num('system.load','load1')))), 'services': []}

def read_target(config):
    # Hosts and key selection live only in a private SSH config. Never invoke a shell locally.
    alias = config.get('ssh_alias')
    if alias:
        # One SSH session per target. The remote reads its own loopback charts;
        # fixed module source goes over stdin, never into a shell argument.
        from pathlib import Path
        remote_config = {'services': config.get('services', [])}
        script = Path(__file__).read_text() + '\nprint(json.dumps(read_target(' + repr(remote_config) + ')))\n'
        proc = subprocess.run(['ssh', '-oBatchMode=yes', '-oConnectTimeout=3', alias, 'python3', '-'], input=script, text=True, capture_output=True, timeout=12, check=True)
        return json.loads(proc.stdout)
    charts = {}
    def read_chart(chart):
        url = 'http://127.0.0.1:19999/api/v1/data?chart=' + chart + '&after=-30&points=30&format=json&options=unaligned'
        try:
            with urllib.request.urlopen(url, timeout=3) as response: raw = response.read(1024*1024)
            return chart, json.loads(raw)
        except (OSError, ValueError, subprocess.SubprocessError):
            return chart, {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(CHARTS)) as pool:
        charts = dict(pool.map(read_chart, CHARTS))
    result = normalize_charts(charts)
    if not result['sampled_at']: raise RuntimeError('sample_failed')
    services = config.get('services', [])
    def read_service(service):
        args = ['systemctl', 'is-active', service]
        if alias: args = ['ssh','-oBatchMode=yes','-oConnectTimeout=3',alias] + args
        try:
            state = subprocess.run(args, capture_output=True, timeout=4).stdout.decode().strip()
            state = state if state in ('active','inactive','failed','activating','deactivating') else 'unknown'
        except (OSError, subprocess.SubprocessError): state = 'unknown'
        return {'name':service, 'state':state}
    if services:
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            result['services'] = list(pool.map(read_service, services))
    return result

class MonitorAggregator:
    def __init__(self, servers, reader=read_target):
        self.servers, self.reader = list(servers), reader
        if len(self.servers) > 4: raise ValueError('too many servers')
        ids = set()
        for server in self.servers:
            sid = server.get('id','')
            if not re.fullmatch(r'[a-zA-Z0-9_-]{1,40}',sid) or sid in ids: raise ValueError('invalid server id')
            ids.add(sid)
            if not isinstance(server.get('display_name'),str): raise ValueError('display_name required')
            if server.get('ssh_alias') and not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}',server['ssh_alias']): raise ValueError('invalid SSH alias')
            if len(server.get('services', [])) > 8: raise ValueError('too many services')
            if any(not re.fullmatch(r'[a-zA-Z0-9_.@-]{1,100}',s) or s.startswith('-') for s in server.get('services',[])): raise ValueError('invalid service')
    def _sample(self, server):
        identity = {'id':server['id'], 'display_name':server['display_name']}
        try: return dict(identity, **self.reader(server))
        except Exception: return dict(identity, sampled_at=None, online=None, metrics=dict.fromkeys(METRICS), services=[], error='sample_failed')
    def snapshot(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(4,len(self.servers)) or 1) as pool:
            servers = list(pool.map(self._sample,self.servers))
        return {'sampled_at':utc(), 'stale_after_seconds':15, 'servers':servers}

def load_private(path):
    with open(path, encoding='utf-8') as source: return MonitorAggregator(json.load(source)['servers'])

class CachedMonitor:
    """Process-wide single-flight cache; create once, never per request."""
    def __init__(self, source, ttl=5, clock=None):
        import threading
        import time
        self.source, self.ttl = source, max(1, ttl)
        self.clock = clock or time.monotonic
        self._lock = threading.Lock()
        self._value, self._expires = None, 0
    def snapshot(self):
        with self._lock:
            if self._value is None or self.clock() >= self._expires:
                self._value = self.source.snapshot()
                self._expires = self.clock() + self.ttl
            return self._value

_default_monitor = None
_default_lock = __import__('threading').Lock()

def handle_status(handler, connection, monitor=None):
    """Host routing calls only for the exact GET path after account_access."""
    user, _ = handler._auth(connection)
    if user is None:
        return handler._json(401, {'error':'authentication_required'})
    if user['user_id'] != 1:
        return handler._json(403, {'error':'forbidden'})
    try:
        if monitor is None:
            global _default_monitor
            with _default_lock:
                if _default_monitor is None:
                    import os
                    _default_monitor = CachedMonitor(load_private(os.environ.get('MONITOR_PRIVATE_CONFIG', '/opt/notes-site/private/server-monitor.json')))
                monitor = _default_monitor
        return handler._json(200, monitor.snapshot())
    except Exception:
        return handler._json(503, {'error':'monitor_unavailable'})
