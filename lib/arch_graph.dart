part of 'main.dart';

/// 架构节点图：机器 → 服务 → 技能簇 三层交互图（106 gen_arch.py 每日产出 arch.json）。
/// 只读页面；节点坐标在服务端定好，本页只负责渲染与点击查看。
class ArchGraphPage extends StatefulWidget {
  const ArchGraphPage({super.key});
  @override
  State<ArchGraphPage> createState() => _ArchGraphPageState();
}

class _ArchGraphPageState extends State<ArchGraphPage> {
  Map<String, dynamic>? data;
  bool loading = false;
  bool failed = false;
  String? selectedId;
  final TransformationController _tc = TransformationController();
  bool _disposed = false;

  List nodes = const [];
  List edges = const [];
  Map<String, Map<String, dynamic>> nodeById = {};
  Map<String, List<String>> adj = {};

  Future<void> load() async {
    if (_disposed || loading) return;
    setState(() { loading = true; failed = false; });
    try {
      final r = await apiGet('/health/arch.json').timeout(const Duration(seconds: 15));
      if (!_disposed && r is Map) {
        data = Map<String, dynamic>.from(r);
        nodes = data?['nodes'] is List ? data!['nodes'] as List : const [];
        edges = data?['edges'] is List ? data!['edges'] as List : const [];
        nodeById = {
          for (final n in nodes)
            if (n is Map && n['id'] != null) '${n['id']}': Map<String, dynamic>.from(n)
        };
        adj = {};
        for (final e in edges) {
          if (e is! Map) continue;
          final a = '${e['from']}'; final b = '${e['to']}';
          adj.putIfAbsent(a, () => []).add(b);
          adj.putIfAbsent(b, () => []).add(a);
        }
        failed = false;
        _fit();
      }
    } catch (_) {
      if (!_disposed) failed = true;
    } finally {
      if (!_disposed) setState(() { loading = false; });
    }
  }

  void _fit() {
    final ch = (data?['canvas']?['h'] as num?)?.toDouble() ?? 1650;
    // 初始缩放：1000 宽 × 0.42 ≈ 贴合手机屏宽；可自由缩放拖动
    const s = 0.42;
    _tc.value = Matrix4.identity()
      ..translate(16.0, 16.0 - ch * 0.0)
      ..scale(s, s, 1.0);
  }

  @override
  void initState() { super.initState(); load(); }

  @override
  void dispose() { _disposed = true; _tc.dispose(); super.dispose(); }

  Color _colorOf(String type, Map n) {
    switch (type) {
      case 'machine': return const Color(0xFF4C8DFF);
      case 'service': return const Color(0xFF35C28F);
      case 'skills': return const Color(0xFFB07DE8);
      default: return const Color(0xFF8A93A6);
    }
  }

  Color _statusColor(Map n) {
    final st = '${n['status'] ?? ''}';
    if (st == 'ok') return const Color(0xFF35C28F);
    if (st == 'warn') return const Color(0xFFF2A93B);
    if (st == 'down') return const Color(0xFFE5484D);
    return const Color(0xFF5A6478);
  }

  void _onTap(Offset p) {
    // GestureDetector 是 InteractiveViewer 的 child，localPosition 已是画布坐标
    String? hit;
    for (final raw in nodes) {
      if (raw is! Map) continue;
      final x = (raw['x'] as num?)?.toDouble() ?? 0;
      final y = (raw['y'] as num?)?.toDouble() ?? 0;
      final w = (raw['w'] as num?)?.toDouble() ?? 80;
      final h = (raw['h'] as num?)?.toDouble() ?? 28;
      if (p.dx >= x - 4 && p.dx <= x + w + 4 && p.dy >= y - 4 && p.dy <= y + h + 4) {
        hit = '${raw['id']}'; break;
      }
    }
    setState(() { selectedId = (hit == selectedId) ? null : hit; });
  }

  @override
  Widget build(BuildContext context) {
    final canvas = data?['canvas'] is Map ? data!['canvas'] as Map : const {};
    final cw = (canvas['w'] as num?)?.toDouble() ?? 1000;
    final ch = (canvas['h'] as num?)?.toDouble() ?? 1650;
    final summary = data?['summary'] is Map ? data!['summary'] as Map : const {};
    final genRaw = '${data?['generated_at'] ?? ''}';
    final gen = genRaw.length >= 16 ? genRaw.substring(0, 16) : (genRaw.isEmpty ? '从未生成' : genRaw);
    return Scaffold(
      appBar: AppBar(
        title: const Text('架构节点图'),
        actions: [
          IconButton(onPressed: loading ? null : load, tooltip: '刷新', icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        _legend(summary, gen),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (failed && data == null)
          const Padding(padding: EdgeInsets.all(24), child: Text('拉取失败，下拉或点刷新重试')),
        Expanded(
          flex: selectedId == null ? 5 : 3,
          child: Container(
            color: const Color(0xFF0E1622),
            child: InteractiveViewer(
              transformationController: _tc,
              boundaryMargin: const EdgeInsets.all(80),
              maxScale: 2.5, minScale: 0.2, constrained: false,
              child: GestureDetector(
                onTapUp: (d) => _onTap(d.localPosition),
                child: SizedBox(
                  width: cw, height: ch,
                  child: CustomPaint(painter: _GraphPainter(
                    nodes: nodes, edges: edges, selectedId: selectedId,
                    colorOf: _colorOf, statusColor: _statusColor,
                  )),
                ),
              ),
            ),
          ),
        ),
        Expanded(flex: selectedId == null ? 1 : 2, child: _detailPanel()),
      ]),
    );
  }

  Widget _legend(Map summary, String gen) {
    Widget chip(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 4), Text(t, style: const TextStyle(fontSize: 11)),
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        chip(const Color(0xFF4C8DFF), '机器 ${summary['machines'] ?? '-'}'),
        const SizedBox(width: 10),
        chip(const Color(0xFF35C28F), '服务 ${summary['services'] ?? '-'}'),
        const SizedBox(width: 10),
        chip(const Color(0xFFB07DE8), '技能 ${summary['skills'] ?? '-'}'),
        const Spacer(),
        Text(gen, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    );
  }

  Widget _detailPanel() {
    if (selectedId == null || !nodeById.containsKey(selectedId)) {
      return Container(
        alignment: Alignment.center,
        child: const Text('点击画布上的节点查看详情', style: TextStyle(color: Colors.grey)),
      );
    }
    final n = nodeById[selectedId]!;
    final type = '${n['type']}';
    final links = adj[selectedId] ?? const [];
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(
              color: _colorOf(type, n), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text('${n['label'] ?? selectedId}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            IconButton(icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() { selectedId = null; })),
          ]),
          ..._metaRows(n),
          if (links.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 8, bottom: 2),
              child: Text('连接', style: TextStyle(fontWeight: FontWeight.w600))),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final l in links)
                if (nodeById.containsKey(l))
                  ActionChip(
                    label: Text('${nodeById[l]!['label'] ?? l}', style: const TextStyle(fontSize: 11)),
                    onPressed: () => setState(() { selectedId = l; }),
                  ),
            ]),
          ],
          if (n['health'] is List && (n['health'] as List).isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 8, bottom: 2),
              child: Text('健康检查', style: TextStyle(fontWeight: FontWeight.w600))),
            for (final h in n['health'] as List)
              if (h is Map)
                ListTile(dense: true, contentPadding: EdgeInsets.zero,
                  leading: Icon(_statusColor(h) == const Color(0xFF35C28F)
                      ? Icons.check_circle : _statusColor(h) == const Color(0xFFE5484D)
                      ? Icons.error : Icons.warning,
                    color: _statusColor(h), size: 18),
                  title: Text('${h['name'] ?? ''}', style: const TextStyle(fontSize: 13)),
                  subtitle: '${h['detail'] ?? ''}'.isEmpty ? null : Text('${h['detail']}', style: const TextStyle(fontSize: 11)),
                ),
          ],
          if (n['members'] is List && (n['members'] as List).isNotEmpty) ...[
            Padding(padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text('技能（${(n['members'] as List).length}）',
                style: const TextStyle(fontWeight: FontWeight.w600))),
            for (final m in n['members'] as List)
              if (m is Map)
                Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${m['name'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    if ('${m['desc'] ?? ''}'.isNotEmpty)
                      Text('${m['desc']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ])),
          ],
        ],
      ),
    );
  }

  List<Widget> _metaRows(Map n) {
    final meta = n['meta'] is Map ? n['meta'] as Map : const {};
    final rows = <Widget>[];
    meta.forEach((k, v) {
      rows.add(Padding(padding: const EdgeInsets.only(top: 2),
        child: Text('$k：$v', style: const TextStyle(fontSize: 12))));
    });
    return rows;
  }
}

class _GraphPainter extends CustomPainter {
  final List nodes;
  final List edges;
  final String? selectedId;
  final Color Function(String, Map) colorOf;
  final Color Function(Map) statusColor;
  _GraphPainter({required this.nodes, required this.edges, required this.selectedId,
    required this.colorOf, required this.statusColor});

  @override
  void paint(Canvas canvas, Size size) {
    final sel = selectedId;
    final connected = <String>{};
    if (sel != null) {
      for (final e in edges) {
        if (e is! Map) continue;
        if ('${e['from']}' == sel) connected.add('${e['to']}');
        if ('${e['to']}' == sel) connected.add('${e['from']}');
      }
    }
    // 边
    for (final e in edges) {
      if (e is! Map) continue;
      final a = nodeOf('${e['from']}'); final b = nodeOf('${e['to']}');
      if (a == null || b == null) continue;
      final hot = sel != null && ('${e['from']}' == sel || '${e['to']}' == sel);
      final p1 = Offset(ax(a) + wOf(a) / 2, ay(a) + hOf(a) / 2);
      final p2 = Offset(ax(b) + wOf(b) / 2, ay(b) + hOf(b) / 2);
      canvas.drawLine(p1, p2, Paint()
        ..color = hot ? const Color(0xFF6AA5FF) : const Color(0xFF2A3A52)
        ..strokeWidth = hot ? 2 : 1);
    }
    // 节点
    for (final raw in nodes) {
      if (raw is! Map) continue;
      final id = '${raw['id']}';
      final type = '${raw['type'] ?? 'more'}';
      final c = colorOf(type, raw);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(ax(raw), ay(raw), wOf(raw), hOf(raw)), const Radius.circular(7));
      final isSel = sel == id;
      final isHot = sel != null && connected.contains(id);
      canvas.drawRRect(r, Paint()..color = c.withAlpha(isSel ? 70 : 34));
      canvas.drawRRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 2.2 : 1.1
        ..color = isSel ? Colors.white : (isHot ? const Color(0xFF6AA5FF) : c));
      // 状态点
      if (raw['status'] != null || type == 'machine' || type == 'service') {
        canvas.drawCircle(Offset(ax(raw) + wOf(raw) - 8, ay(raw) + 8), 3.2,
          Paint()..color = statusColor(raw));
      }
      // 文本
      final label = '${raw['label'] ?? id}';
      String text = label;
      if (type == 'skills' && raw['count'] != null) text = '$label · ${raw['count']}';
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(
          color: isSel ? Colors.white : const Color(0xFFD7DEEA), fontSize: 11)),
        maxLines: 2, ellipsis: '…', textDirection: TextDirection.ltr)
        ..layout(maxWidth: wOf(raw) - 12);
      tp.paint(canvas, Offset(ax(raw) + 6, ay(raw) + hOf(raw) / 2 - tp.height / 2));
    }
  }

  Map? nodeOf(String id) {
    for (final n in nodes) { if (n is Map && '${n['id']}' == id) return n; }
    return null;
  }
  double ax(Map n) => (n['x'] as num?)?.toDouble() ?? 0;
  double ay(Map n) => (n['y'] as num?)?.toDouble() ?? 0;
  double wOf(Map n) => (n['w'] as num?)?.toDouble() ?? 80;
  double hOf(Map n) => (n['h'] as num?)?.toDouble() ?? 28;

  @override
  bool shouldRepaint(_GraphPainter old) =>
    old.selectedId != selectedId || old.nodes.length != nodes.length;
}
