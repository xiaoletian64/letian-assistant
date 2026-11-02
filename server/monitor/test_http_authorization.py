"""Wire-level auth regression using controlled credentials, no production tokens."""
import json
import threading
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from aggregator import handle_status

class MonitorHTTPTests(unittest.TestCase):
    def test_anonymous_nonowner_owner_and_fixed_route(self):
        calls = []
        class Monitor:
            def snapshot(self):
                calls.append(True)
                return {'servers': []}
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def _auth(self, connection):
                fixture = {'Bearer fixture-owner': {'user_id': 1}, 'Bearer fixture-other': {'user_id': 5}}
                return fixture.get(self.headers.get('Authorization')), None
            def _json(self, status, body):
                self.send_response(status)
                self.send_header('Content-Type','application/json')
                self.send_header('Cache-Control','no-store')
                self.end_headers()
                self.wfile.write(json.dumps(body).encode())
            def do_GET(self):
                if self.path.split('?')[0] != '/api/hub/servers/status':
                    return self._json(404, {'error':'not_found'})
                return handle_status(self, None, Monitor())
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            for credential, path, expected in [(None,'/api/hub/servers/status',401), ('fixture-other','/api/hub/servers/status',403), ('fixture-owner','/api/hub/servers/status',200), ('fixture-owner','/api/hub/servers/status/else',404)]:
                request = urllib.request.Request('http://127.0.0.1:'+str(server.server_port)+path)
                if credential: request.add_header('Authorization','Bearer '+credential)
                try: response = urllib.request.urlopen(request, timeout=2)
                except urllib.error.HTTPError as exc: response = exc
                with response:
                    self.assertEqual(response.status, expected)
                    self.assertEqual(response.headers['Cache-Control'],'no-store')
            self.assertEqual(len(calls),1, 'unauthorized and invalid paths must never sample')
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=2)
