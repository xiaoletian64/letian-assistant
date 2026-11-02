part of 'main.dart';

/// Fetcher uses the owner's authenticated bridge; this page never calls providers.
class QuotaHistoryPage extends StatefulWidget {
  const QuotaHistoryPage({super.key, required this.fetchPage});
  final Future<Map<String, dynamic>> Function(Map<String, String>) fetchPage;
  @override
  State<QuotaHistoryPage> createState() => _QuotaHistoryPageState();
}

class _QuotaHistoryPageState extends State<QuotaHistoryPage> {
  final _items = <Map<String, dynamic>>[];
  final _provider = TextEditingController(), _window = TextEditingController();
  bool _loading = false, _failed = false, _retryReset = false;
  String? _cursor;
  String? _accessError;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _provider.dispose();
    _window.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
      _accessError = null;
      _retryReset = reset;
    });
    try {
      final result = await widget.fetchPage({
        'limit': '50',
        if (_provider.text.trim().isNotEmpty) 'provider': _provider.text.trim(),
        if (_window.text.trim().isNotEmpty) 'window': _window.text.trim(),
        if (!reset && _cursor != null) 'cursor': _cursor!,
      });
      final rows = (result['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(rows);
        _cursor = result['next_cursor']?.toString();
      });
    } on SessionExpired {
      if (mounted) {
        setState(() {
          _items.clear();
          _cursor = null;
          _accessError = '登录已过期，请重新登录';
        });
      }
    } on AccessDenied {
      if (mounted) {
        setState(() {
          _items.clear();
          _cursor = null;
          _accessError = '当前账号无权查看额度历史';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _number(dynamic value) => value == null ? '未知' : '$value';
  String _time(dynamic value) => value is num
      ? DateTime.fromMillisecondsSinceEpoch(
          (value * 1000).round(),
          isUtc: true,
        ).toLocal().toIso8601String()
      : '未知';
  String _event(dynamic value) => switch (value) {
    'confirmed' => '来源明确重置',
    'inferred' => '匹配已知边界的推断重置',
    'candidate' => '候选变化：可能重置、赠额、充值或修正',
    _ => '未推断重置',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('额度历史')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('按平台独立记录。额度变化不等于按请求 Token，也不代表官方按量账单。'),
        const SizedBox(height: 12),
        TextField(
          controller: _provider,
          enabled: !_loading,
          decoration: const InputDecoration(
            labelText: '平台筛选（留空为全部）',
            hintText: '如 codex',
          ),
        ),
        TextField(
          controller: _window,
          enabled: !_loading,
          decoration: const InputDecoration(
            labelText: '窗口筛选（留空为全部）',
            hintText: '如 weekly',
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _loading ? null : () => _load(reset: true),
            child: const Text('应用筛选'),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_accessError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_accessError!),
          ),
        if (_failed)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text('历史加载失败，已加载记录保留。'),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => _load(reset: _retryReset),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        if (!_loading && !_failed && _accessError == null && _items.isEmpty)
          const Text('暂无历史采样'),
        for (final item in _items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['provider']} · ${item['account']} · ${item['window']}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SelectableText(
                    '已用 ${_number(item['used'])} · 剩余 ${_number(item['remaining'])} · 上限 ${_number(item['limit'])} ${item['units'] ?? '单位未知'}',
                  ),
                  Text(
                    '采样时间 ${_time(item['observed_time'])}\n来源时间 ${_time(item['source_time'])}',
                  ),
                  Text(
                    '来源 ${item['source'] ?? '未知'} · 重置时间 ${_time(item['reset_at'])}',
                  ),
                  Text(_event(item['event'])),
                  Text(
                    item['delta'] == null
                        ? '区间消耗未知'
                        : '累计计数差值 ${item['delta']} ${item['units']}（估计，不是逐请求统计）',
                  ),
                  if (item['error'] != null) const Text('本次采集失败；未知计数未填零'),
                ],
              ),
            ),
          ),
        if (_cursor != null)
          TextButton(
            onPressed: _loading ? null : () => _load(),
            child: const Text('加载更多'),
          ),
      ],
    ),
  );
}
