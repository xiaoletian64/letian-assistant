part of 'main.dart';

/// 服务体检：展示每日自动接口健康检查结果（106 定时生成 health.json）。
/// 只读页面，无写操作；数据源为静态 JSON，任何登录态均可查看。
class SkillHealthPage extends StatefulWidget {
  const SkillHealthPage({super.key});
  @override
  State<SkillHealthPage> createState() => _SkillHealthPageState();
}

class _SkillHealthPageState extends State<SkillHealthPage> {
  Map<String, dynamic>? data;
  bool loading = false;
  bool failed = false;
  int _epoch = 0;
  bool _disposed = false;

  Future<Map<String, dynamic>> _parse(Map<String, dynamic> raw) async {
    final items = raw['items'];
    if (items is! List || items.isEmpty) {
      throw const FormatException('体检报告为空');
    }
    return raw;
  }

  Future<void> load() async {
    if (_disposed || loading) return;
    final epoch = _epoch;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final result =
          await apiGet('/health/skills.json').timeout(const Duration(seconds: 12));
      if (!_disposed && epoch == _epoch) {
        data = await _parse(Map<String, dynamic>.from(result as Map));
        failed = false;
      }
    } catch (_) {
      if (!_disposed && epoch == _epoch) failed = true;
    } finally {
      if (!_disposed) {
        loading = false;
        setState(() {});
      }
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }

  bool get _stale {
    final checked = DateTime.tryParse('${data?['checked_at'] ?? ''}');
    if (checked == null) return true;
    return DateTime.now().difference(checked) > const Duration(hours: 26);
  }

  @override
  Widget build(BuildContext context) {
    final items = data?['items'] is List
        ? data!['items'] as List
        : const [];
    final summary = data?['summary'] is Map
        ? data!['summary'] as Map
        : const {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务体检'),
        actions: [
          IconButton(
            onPressed: loading ? null : load,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _header(summary),
            if (loading) const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
            if (failed)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('拉取失败，显示的是上次成功的结果；下拉可重试。'),
              ),
            if (_stale && data != null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('今日检查尚未生成，以下为最近一次结果。'),
              ),
            if (data == null && !loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('暂无体检报告，稍后下拉重试。'),
              ),
            ..._grouped(items),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                '每天 08:10 自动检查一次；本页展示最近一轮结果。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(Map summary) {
    final checked = DateTime.tryParse('${data?['checked_at'] ?? ''}');
    final local = checked == null
        ? '时间未知'
        : '检查于 ${checked.add(Duration(hours: 8)).toString().substring(0, 16)}（北京）';
    final ok = summary['ok'] is int ? summary['ok'] as int : 0;
    final warn = summary['warn'] is int ? summary['warn'] as int : 0;
    final down = summary['down'] is int ? summary['down'] as int : 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _badge('$ok 正常', Colors.green),
                const SizedBox(width: 8),
                _badge('$warn 降级', Colors.orange),
                const SizedBox(width: 8),
                _badge('$down 不可用', Colors.red),
              ],
            ),
            const SizedBox(height: 10),
            Text(local, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withAlpha(30),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600)),
  );

  List<Widget> _grouped(List items) {
    final order = <String>[];
    final byGroup = <String, List>{};
    for (final raw in items) {
      if (raw is! Map) continue;
      final g = '${raw['group'] ?? '其他'}';
      if (!byGroup.containsKey(g)) {
        byGroup[g] = [];
        order.add(g);
      }
      byGroup[g]!.add(raw);
    }
    return [
      for (final g in order) ...[
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(g,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        Card(
          child: Column(
            children: [
              for (final raw in byGroup[g]!) _tile(raw as Map),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _tile(Map item) {
    final status = '${item['status'] ?? 'warn'}';
    final icon = status == 'ok'
        ? (Icon(Icons.check_circle, color: Colors.green))
        : status == 'down'
            ? (Icon(Icons.error, color: Colors.red))
            : (Icon(Icons.warning, color: Colors.orange));
    final ms = item['ms'] is int ? item['ms'] as int : null;
    final trailing = ms == null
        ? null
        : Text('${ms}ms', style: Theme.of(context).textTheme.bodySmall);
    return ListTile(
      leading: icon,
      title: Text('${item['name'] ?? item['id'] ?? ''}'),
      subtitle: '${item['detail'] ?? ''}'.isEmpty
          ? null
          : Text('${item['detail']}'),
      trailing: trailing,
      dense: true,
    );
  }
}
