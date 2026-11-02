# Owner-only history proxy

The host routes only exact GET `/api/hub/quota/history` to `quota_history_proxy.handle(self, connection)` after its existing account authorization. The module independently authenticates and requires numeric user_id 1; it never trusts an ID supplied in the request.

Allowed query keys: provider, window, from, to, cursor, limit. Duplicate/unknown keys, empty filters, controls, non-finite/negative timestamps, reversed intervals and invalid limits return 400 before SSH. Limit defaults to 100 and cannot exceed 200. Provider/window are bounded text, cursor is positive integer, from/to are observation epoch seconds.

The fixed private SSH alias selects the collector; the fixed read-only module command receives only JSON on stdin, never shell-interpolated client input. One SSH per request, 12-second timeout, at most 4096 request bytes and 2 MiB accepted response; safe error 503 on RPC/output failure. The collector has its own whitelist and read-only database connection. Returned items and cursor must match bounded response shape. Production host/configuration/database files are not included here. Host JSON responses must retain existing no-store headers.

Run:

```
python3 -m unittest server.quota_history.test_proxy -v
python3 -m unittest discover -s server/quota_history -v
```

Tests use controlled synthetic identities, check 401/403/200 and reject duplicate/unknown/invalid parameters before RPC. Invalid backend details are never returned to the client.

Production verification used a controlled identity handler around the installed proxy: anonymous 401, another identity 403, owner 200 with five real RPC rows, complete expected fields and valid cursor. A separate real anonymous HTTP request returned 401. Duplicate parameters and out-of-range limits returned 400 before RPC. No real user tokens were accessed. The installed host route remains after the existing account authorization gate.
