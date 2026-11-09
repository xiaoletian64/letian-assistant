part of 'main.dart';

List<String> quotaOverview(List<QuotaAccount> accounts) {
  // Cursor's pushed mirror remains in details, never counted as a second balance.
  final directCursor = accounts.any(
    (a) => a.platform == 'Cursor' && a.source == '直接采集',
  );
  final sources = accounts
      .where(
        (a) => !(directCursor && a.platform == 'Cursor' && a.source == '推送采集'),
      )
      .toList();
  sources.sort((a, b) {
    int rank(QuotaAccount a) => a.unavailable
        ? 0
        : a.low
        ? 1
        : 2;
    return rank(a).compareTo(rank(b));
  });
  final lines = <String>[];
  for (final a in sources.take(2)) {
    final multi = sources.where((b) => b.platform == a.platform).length > 1;
    final name = '${a.platform}${multi ? ' · ${a.name}' : ''}';
    if (a.unavailable) {
      lines.add('$name · ${a.status}，当前数值未知');
    } else if (a.windows.isEmpty) {
      lines.add('$name · 额度未知');
    } else {
      final windows = [...a.windows];
      windows.sort(
        (a, b) => (a.remaining ?? 101).compareTo(b.remaining ?? 101),
      );
      final w = windows.first;
      final value = w.remaining == null
          ? (w.summary ?? w.value)
          : '剩余 ${sceneDecimal(w.remaining!)}%';
      lines.add('$name · ${w.period} · $value');
    }
  }
  if (lines.isEmpty) lines.add('暂未取得额度数据');
  final platforms = sources.map((a) => a.platform).toSet().length;
  final attention = sources.where((a) => a.unavailable || a.low).length;
  lines.add(
    '$platforms 个平台${attention > 0 ? ' · $attention 个来源需关注' : ' · 未发现额度告警'}',
  );
  final times = sources.map((a) => a.sourceDate).whereType<DateTime>().toList()
    ..sort();
  if (times.isNotEmpty) {
    lines.add('最早来源更新 ${sceneTime(times.first.toIso8601String())} · 北京时间');
  }
  return lines;
}

class BusinessSummaryCard extends StatelessWidget {
  const BusinessSummaryCard({
    super.key,
    required this.title,
    required this.lines,
    required this.children,
    this.onDetails,
    this.status,
  });
  final String title;
  final List<String> lines;
  final List<Widget> children;
  final VoidCallback? onDetails;
  final Widget? status;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 8),
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFDDE8F6)),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: ValueKey('business-$title'),
      initiallyExpanded: false,
      maintainState: false,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Text(line, style: const TextStyle(height: 1.5)),
            if (status != null) status!,
          ],
        ),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...children,
        if (onDetails != null)
          TextButton(onPressed: onDetails, child: const Text('查看完整详情')),
      ],
    ),
  );
}

List<Widget> quotaOverviewRows(List<QuotaAccount> accounts) => [
  for (final a in accounts)
    ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${a.platform} · ${a.name}'),
      subtitle: Text(
        [
          if (a.source.isNotEmpty) '来源：${a.source}',
          if (a.unavailable)
            '${a.status} · 当前数值未知'
          else
            for (final w in a.windows) '${w.period}：${w.summary ?? w.value}',
          '来源更新 ${a.observed} · 北京时间',
        ].join('\n'),
      ),
    ),
];

List<String> purchaseOverview(Map<String, dynamic> data, String group) {
  final overview = sceneMap(data['overview']);
  final raw = overview[group];
  return raw is List && raw.isNotEmpty
      ? raw.whereType<String>().toList()
      : [group == 'expense' ? '消费摘要暂未取得，金额未知' : '快递摘要暂未取得，状态未知'];
}
