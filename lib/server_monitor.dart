part of 'main.dart';

/// Read-only polling state. Account identity is private and never rendered.
class ServerMonitorController extends ChangeNotifier {
  ServerMonitorController({required this.fetch});
  Future<Map<String, dynamic>> Function() fetch;
  Map<String, dynamic>? data;
  bool loading = false;
  bool failed = false;
  bool _disposed = false;
  int _epoch = 0;
  String? _account;
  void setAccount(String? account) {
    if (_account == account) return;
    _account = account;
    _epoch++;
    data = null;
    failed = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed || loading || _account == null) return;
    final epoch = _epoch;
    loading = true;
    notifyListeners();
    try {
      final value = await fetch();
      if (!_disposed && epoch == _epoch) {
        data = value;
        failed = false;
      }
    } catch (_) {
      if (!_disposed && epoch == _epoch) failed = true;
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}

class ServerMonitorPage extends StatefulWidget {
  const ServerMonitorPage({super.key});
  @override
  State<ServerMonitorPage> createState() => _ServerMonitorPageState();
}

class _ServerMonitorPageState extends State<ServerMonitorPage>
    with WidgetsBindingObserver {
  late final ServerMonitorController monitor;
  Timer? timer;
  bool foreground = true;
  bool visible = true;
  bool ticking = false;
  int visibilityEpoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    monitor = ServerMonitorController(
      fetch: () async {
        final account = await token();
        final result = await apiGet(
          '/api/hub/servers/status',
        ).timeout(const Duration(seconds: 12));
        if (account != await token()) {
          monitor.setAccount(await token());
          throw StateError('account_changed');
        }
        if (result is! Map) {
          throw const FormatException('invalid monitor response');
        }
        return Map<String, dynamic>.from(result);
      },
    );
    monitor.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode becomes false when a route is covered, including kept-alive tabs.
    visible = TickerMode.valuesOf(context).enabled;
    schedule();
  }

  void schedule() {
    timer?.cancel();
    visibilityEpoch++;
    if (!foreground || !visible) {
      monitor.setAccount(null);
      return;
    }
    unawaited(tick());
    timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(tick()),
    );
  }

  Future<void> tick() async {
    if (ticking || !mounted || !foreground || !visible) return;
    ticking = true;
    final epoch = visibilityEpoch;
    try {
      final account = await token();
      if (!mounted || !foreground || !visible || epoch != visibilityEpoch) {
        return;
      }
      monitor.setAccount(account);
      await monitor.refresh();
    } finally {
      ticking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    schedule();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    monitor.removeListener(changed);
    monitor.dispose();
    super.dispose();
  }

  String number(dynamic value, String unit) => value is num && value.isFinite
      ? '${value.toStringAsFixed(1)}$unit'
      : '未知';
  @override
  Widget build(BuildContext context) {
    final data = monitor.data;
    final servers = data?['servers'] is List
        ? data!['servers'] as List
        : const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器监控'),
        actions: [
          IconButton(
            onPressed: monitor.loading ? null : tick,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: tick,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('前台每 5 秒拉取；下方时间为服务器实际源采样时间。'),
            ),
            if (monitor.loading) const LinearProgressIndicator(),
            if (monitor.failed)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '刷新失败，保留上次采样。数据已标记为过期，可重试。',
                  semanticsLabel: '刷新失败，当前为旧数据',
                ),
              ),
            if (data == null && !monitor.loading) const Text('暂无采样，请登录后重试。'),
            for (final raw in servers.whereType<Map>()) serverCard(raw, data),
          ],
        ),
      ),
    );
  }

  Widget serverCard(Map server, Map<String, dynamic>? data) {
    final metrics = server['metrics'] is Map
        ? server['metrics'] as Map
        : const {};
    final sampled = DateTime.tryParse('${server['sampled_at'] ?? ''}');
    final maxAge = data?['stale_after_seconds'] is num
        ? (data!['stale_after_seconds'] as num).toInt().clamp(5, 60)
        : 15;
    final stale =
        monitor.failed ||
        sampled == null ||
        DateTime.now().toUtc().difference(sampled).inSeconds > maxAge;
    final online = server['online'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${server['display_name'] ?? '服务器'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${stale ? '过期 · ' : ''}${online == true
                  ? '采样可达'
                  : online == false
                  ? '离线'
                  : '状态未知'}',
            ),
            Text(sampled == null ? '采样时间未知' : '采样：${sampled.toLocal()}'),
            const SizedBox(height: 12),
            for (final entry in <String, String>{
              'CPU': number(metrics['cpu_percent'], '%'),
              '内存': number(metrics['memory_percent'], '%'),
              '磁盘': number(metrics['disk_percent'], '%'),
              '接收': number(metrics['network_rx_bytes_per_second'], ' B/s'),
              '发送': number(metrics['network_tx_bytes_per_second'], ' B/s'),
              '1 分钟负载': number(metrics['load_1m'], ''),
            }.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(entry.key)),
                    Text(entry.value),
                  ],
                ),
              ),
            for (final service
                in (server['services'] is List
                        ? server['services'] as List
                        : const [])
                    .whereType<Map>())
              Text(
                '${service['name'] ?? '服务'}：${service['state'] ?? 'unknown'}',
              ),
          ],
        ),
      ),
    );
  }
}
