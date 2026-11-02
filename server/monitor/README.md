# Read-only server status integration

`GET /api/hub/servers/status` must be routed **after the host application's existing Bearer authentication and authorization**. `handle_status(handler, connection)` additionally requires authenticated user_id == 1; other accounts receive 403, anonymous requests 401. The module does not create an unauthenticated HTTP server. Never accept host, URL, SSH alias, service name, or configuration path from an HTTP request.

At process startup construct `monitor = CachedMonitor(load_private(os.environ['MONITOR_PRIVATE_CONFIG']), ttl=5)` (import both from aggregator); call `monitor.snapshot()` from the existing authenticated API worker. The lock provides single-flight sampling and 5-second cache reuse within one process. Never construct it per request. Multiple workers require a shared cache or a single monitor worker to avoid multiplying SSH traffic. Each remote target uses one SSH session running this fixed Python collector over stdin; no source is interpolated into shell arguments. Remote chart and service reads run with bounded concurrency and timeouts. The SSH subprocess has a 12-second hard deadline; at most four targets are configured. A timeout is unknown, not zero. Keep configuration outside the repository and web root, permissions 0600. Do not log configuration or raw sampling exceptions. A private configuration contains `servers`, each with stable public-safe `id`, generic `display_name`, optional private `ssh_alias`, and an allowlist `services`. Missing `ssh_alias` selects local loopback Netdata. Remote aliases must be defined in the service account's private SSH config with an already verified host key, restricted read-only credentials, and no user-controlled ProxyCommand. Do not disable host key checking.

Public example (no actual hostnames):

```json
{"servers":[{"id":"server-a","display_name":"服务器 A","services":["example.service"]},{"id":"server-b","display_name":"服务器 B","ssh_alias":"monitor-secondary","services":[]}]}
```

Output contract: `{sampled_at, stale_after_seconds:15, servers:[{id, display_name, sampled_at, online, metrics, services, error?}]}`. All timestamps UTC ISO-8601. Individual server `sampled_at` is the oldest returned metric sample, never the HTTP fetch time. Missing metrics are null. `online:true` means Netdata sampling reachable; a sampling failure is `online:null` (unknown), not proof the server is powered off. Failure exposes only `sample_failed`. CPU/memory/root-disk are percent; network is bytes/second, converted from standard Netdata system.net kilobits/second; load is the one-minute load average. Services expose only explicitly configured safe unit names and active/inactive/failed/activating/deactivating/unknown. Display names and unit names must be reviewed for privacy before serving them.

The UI uses a standalone read-only page and persistent inline failure/status text; navigation back discards no edits. It polls every 5 seconds while visible/resumed, never overlaps requests, pauses on covered route/background/disposal, clears data on identity changes, and retains but marks failed previous samples as stale. Server timestamps older than the threshold are marked stale even when transport succeeds. User refresh uses the same request guard. Add `part 'server_monitor.dart';` in main.dart and open `const ServerMonitorPage()`.

Verification:

```
python3 -m unittest discover -s server/monitor -v
flutter test test/server_monitor_test.dart
```

No production service was modified by this module. Before rollout, privately confirm Netdata chart dimensions/units on each host, root disk chart ID, configured service names, API authorization, endpoint request duration, real foreground/background behavior, and physical device UI. A missing chart remains unknown; no fabricated fallback. Configure the existing API with bounded workers/rate limits and consider a short shared cache to avoid multiple clients multiplying SSH load. Source authentication must never be derived from the public display identity.

## Source freshness and authorization regression

Netdata reads use `after=-30&points=30&options=unaligned`, retain the newest row by source timestamp per chart, and expose the oldest of those chart timestamps as the server timestamp. This avoids a single wide aggregated point lagging behind wall-clock time. The 15-second stale threshold remains unchanged. No metric timestamp is replaced with HTTP receipt time. UI explains the 5-second pull interval separately from source sampling time. Live verification on both configured servers returned all six metrics, source ages 2.6 seconds, and all selected services active.

`test_http_authorization.py` starts an ephemeral loopback server with controlled synthetic credentials and invokes the real `handle_status`: anonymous 401, non-owner 403, owner 200, nonmatching route 404, no-store headers, and sampling invoked only for the owner request. `test_aggregator.py` covers latest source-row selection, original timestamps, units, missing values, unsafe configuration, sanitised failures and cache reuse. Run the unittest discovery command above. Tests contain no production host or credentials.

Catalog integration requires explicit per-user filtering: the existing catalog serialiser does not support per-entry user permissions; adding owner metadata alone has no enforcement effect. Do not add a monitor entry unless listing is restricted to user_id == 1 and the renderer is explicitly accepted. The status endpoint itself independently enforces user_id == 1.

## Catalog owner isolation

`catalog_access.filter_owner_entries(rows, user_id)` receives the server-authenticated numeric ID and removes only `server-monitor` for every identity except integer 1. The host applies it before its existing catalog serializer. Other entries and account owner configuration remain unchanged. `server-monitor` must also be in the renderer allowlist. The bundled catalog carries `owner_only:true`; the client must hide this entry until a trusted server-authenticated identity confirms owner 1, including offline/fallback paths. Backend authorization remains independently enforced.

Catalog regression: `test_catalog_access.py` verifies owner 1 visibility, other/unknown identities hidden, string identity rejected and other row objects unchanged. Production staging additionally executes the extracted real listing branch against synthetic identities and compares every other serialized entry to the baseline. Real anonymous catalog requests remain 401.

## Planned quota history proxy boundary

The future exact GET `/api/hub/quota/history` must execute after the existing account gate and independently require authenticated user_id 1, matching monitor isolation. A fixed read-only RPC on the collector host will return bounded history data. Do not accept SQL, filesystem paths, remote command names, hosts or URLs from clients. Validate all supported query parameters against the history library contract before invoking the fixed RPC; unknown/invalid parameters return 400. Bound result sizes and remote duration, use at most one SSH session per request, and expose safe availability errors only. SQLite, backups and raw private snapshots stay in the private service environment. Credentials/account secrets must not appear in the history response. Exact RPC operation and field schema are pending the history library contract; no speculative production route has been installed.
