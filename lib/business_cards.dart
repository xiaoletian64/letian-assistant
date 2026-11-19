part of 'main.dart';

const quotaPieColors = [
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFFF59E0B),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFF06B6D4),
  Color(0xFF84CC16),
  Color(0xFFEF4444),
];

/// One donut slice per platform: its featured (most constrained) window's
/// remaining share. Percentages come from different quotas, so slices are
/// normalized for display only — values are never summed into a total quota.
class QuotaPieSlice {
  const QuotaPieSlice(this.label, this.remaining, this.color, this.resetAt);
  final String label;
  final double remaining;
  final Color color;
  final DateTime? resetAt;
}

List<QuotaAccount> _quotaPieSources(List<QuotaAccount> accounts) {
  final directCursor = accounts.any(
    (a) => a.platform == 'Cursor' && a.source == '直接采集',
  );
  return accounts
      .where(
        (a) =>
            !a.unavailable &&
            !(directCursor && a.platform == 'Cursor' && a.source == '推送采集'),
      )
      .toList();
}

QuotaWindow? _quotaFeaturedWindowOf(QuotaAccount account) {
  final windows = [...account.windows]
    ..sort((a, b) => (a.remaining ?? 101).compareTo(b.remaining ?? 101));
  return windows.isEmpty ? null : windows.first;
}

List<QuotaPieSlice> quotaPieSlices(List<QuotaAccount> accounts) {
  final slices = <QuotaPieSlice>[];
  final seen = <String>{};
  for (final account in _quotaPieSources(accounts)) {
    if (!seen.add(account.platform)) continue;
    final window = _quotaFeaturedWindowOf(account);
    final remaining = window?.remaining;
    if (remaining == null || remaining < 0 || remaining > 100) continue;
    slices.add(
      QuotaPieSlice(
        account.platform,
        remaining,
        quotaPieColors[slices.length % quotaPieColors.length],
        account.nextResetAt,
      ),
    );
  }
  slices.sort((a, b) => a.remaining.compareTo(b.remaining));
  return slices;
}

String? quotaNextResetLine(List<QuotaAccount> accounts) {
  final candidates = <(DateTime, String, String)>[];
  for (final account in _quotaPieSources(accounts)) {
    final reset = account.nextResetAt;
    if (reset == null) continue;
    final window = _quotaFeaturedWindowOf(account);
    candidates.add((reset, account.platform, window?.period ?? ''));
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  final (reset, platform, period) = candidates.first;
  final periodText = period.isEmpty ? '' : ' $period';
  return '最近周期到：${sceneTime(reset.toIso8601String())} · $platform$periodText（北京时间）';
}

/// Collapsed-area extras for the AI quota card: donut + legend, exclusion
/// note and the nearest upcoming period reset. Values stay per-source; the
/// donut normalizes only for visual comparison, never sums quotas.
List<Widget> quotaCollapsedExtras(List<QuotaAccount> accounts) {
  final slices = quotaPieSlices(accounts);
  final excluded = accounts
      .where(
        (a) => a.unavailable || a.windows.every((w) => w.remaining == null),
      )
      .length;
  return [
    const SizedBox(height: 10),
    if (slices.isNotEmpty)
      quotaPieSummaryRow(slices)
    else
      const Text(
        '暂无可对比的剩余百分比，饼图待来源提供数值',
        style: TextStyle(fontSize: 11, color: sceneMuted),
      ),
    if (excluded > 0)
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '$excluded 个来源无有效剩余百分比，未计入饼图',
          style: const TextStyle(fontSize: 11, color: sceneMuted),
        ),
      ),
    if (quotaNextResetLine(accounts) != null)
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: sceneInk.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 13, color: sceneMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                quotaNextResetLine(accounts)!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: sceneInk,
                ),
              ),
            ),
          ],
        ),
      ),
  ];
}

class QuotaDonutChart extends StatelessWidget {
  const QuotaDonutChart({super.key, required this.slices, this.size = 76});
  final List<QuotaPieSlice> slices;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _QuotaDonutPainter(slices)),
  );
}

class _QuotaDonutPainter extends CustomPainter {
  const _QuotaDonutPainter(this.slices);
  final List<QuotaPieSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (sum, s) => sum + s.remaining);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final stroke = radius * 0.42;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    if (total <= 0) {
      paint.color = const Color(0xFFDFEAFC);
      canvas.drawArc(rect, 0, dart_math.pi * 2, false, paint);
      return;
    }
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFFEDF3FC);
    canvas.drawArc(rect, 0, dart_math.pi * 2, false, track);
    const gap = 0.035; // radians of visual separation between slices.
    var start = -dart_math.pi / 2;
    for (final slice in slices) {
      final sweep = slice.remaining / total * dart_math.pi * 2;
      final drawn = (sweep - gap).clamp(0.0, dart_math.pi * 2);
      paint.color = slice.color;
      if (drawn > 0) canvas.drawArc(rect, start, drawn, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_QuotaDonutPainter oldDelegate) =>
      oldDelegate.slices.length != slices.length ||
      List.generate(
        slices.length,
        (i) =>
            oldDelegate.slices[i].remaining != slices[i].remaining ||
            oldDelegate.slices[i].color != slices[i].color ||
            oldDelegate.slices[i].label != slices[i].label,
      ).any((changed) => changed);
}

Widget quotaPieSummaryRow(List<QuotaPieSlice> slices) {
  final tightest = slices.isEmpty ? null : slices.first;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Stack(
        alignment: Alignment.center,
        children: [
          QuotaDonutChart(slices: slices, size: 84),
          if (tightest != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${sceneDecimal(tightest.remaining)}%',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: sceneInk,
                  ),
                ),
                const Text(
                  '最紧',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: sceneMuted,
                  ),
                ),
              ],
            ),
        ],
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '剩余额度分布',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: sceneInk,
              ),
            ),
            const SizedBox(height: 6),
            for (final slice in slices)
              Container(
                margin: const EdgeInsets.only(top: 5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: slice.color.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: slice.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${slice.label} 剩余 ${sceneDecimal(slice.remaining)}%'
                        '${slice.resetAt == null ? '' : ' · ${sceneTime(slice.resetAt!.toIso8601String())} 到'}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: sceneInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

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
    // Keep confirmed values visible even when several other sources fail.
    int rank(QuotaAccount a) => a.unavailable
        ? 3
        : a.windows.isEmpty
        ? 2
        : a.low
        ? 0
        : 1;
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
  final unavailable = sources.where((a) => a.unavailable).length;
  lines.add(
    '$platforms 个平台${attention > 0 ? ' · $attention 个来源需关注' : ' · 未发现额度告警'}'
    '${unavailable > 0 ? ' · $unavailable 个来源当前数值未知' : ''}',
  );
  final times = sources.map((a) => a.sourceDate).whereType<DateTime>().toList()
    ..sort();
  if (times.isNotEmpty) {
    lines.add('最早来源更新 ${sceneTime(times.first.toIso8601String())} · 北京时间');
  }
  final nextReset = quotaNextResetLine(sources);
  if (nextReset != null) lines.add(nextReset);
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

List<Widget> quotaOverviewRows(List<QuotaAccount> accounts) =>
    quotaPlatformCards(accounts);

QuotaWindow _quotaFeaturedWindow(QuotaAccount account) {
  final windows = [...account.windows]
    ..sort((a, b) => (a.remaining ?? 101).compareTo(b.remaining ?? 101));
  return windows.first;
}

class QuotaOverviewCard extends StatelessWidget {
  const QuotaOverviewCard({
    super.key,
    required this.accounts,
    this.status,
    this.onDetails,
  });
  final List<QuotaAccount> accounts;
  final Widget? status;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final directCursor = accounts.any(
      (a) => a.platform == 'Cursor' && a.source == '直接采集',
    );
    final sorted =
        accounts
            .where(
              (a) =>
                  !(directCursor &&
                      a.platform == 'Cursor' &&
                      a.source == '推送采集'),
            )
            .toList()
          ..sort((a, b) {
            int rank(QuotaAccount a) => a.low
                ? 0
                : a.unavailable
                ? 3
                : a.windows.isEmpty
                ? 2
                : 1;
            return rank(a).compareTo(rank(b));
          });
    final featured = <QuotaAccount>[];
    for (final account in sorted) {
      if (featured.any((a) => a.platform == account.platform)) continue;
      featured.add(account);
      if (featured.length == 2) break;
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFDDE8F6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const ValueKey('business-AI额度'),
        title: const Text(
          'AI额度',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final account in featured)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      quotaBrandMark(account.platform),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${account.platform}${accounts.where((a) => a.platform == account.platform).length > 1 ? ' · ${account.name}' : ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: sceneMuted,
                              ),
                            ),
                            Text(
                              account.unavailable
                                  ? account.status
                                  : account.windows.isEmpty
                                  ? '额度未知'
                                  : _quotaFeaturedWindow(account).summary ??
                                        _quotaFeaturedWindow(account).value,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: account.unavailable || account.low
                                    ? sceneAmber
                                    : sceneInk,
                              ),
                            ),
                            if (!account.unavailable &&
                                account.windows.isNotEmpty)
                              Text(
                                _quotaFeaturedWindow(account).reset,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: sceneMuted,
                                ),
                              ),
                            Text(
                              '来源更新 ${account.observed} · 北京时间',
                              style: const TextStyle(
                                fontSize: 11,
                                color: sceneMuted,
                              ),
                            ),
                            Text(
                              '套餐到期：${quotaDateText(account.expiresAt)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: sceneMuted,
                              ),
                            ),
                            if (account.periodEnd != null)
                              Text(
                                '套餐周期结束：${quotaDateText(account.periodEnd)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: sceneMuted,
                                ),
                              ),
                            Text(
                              '最近充值：${quotaDateText(account.rechargedAt)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: sceneMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                '${accounts.map((a) => a.platform).toSet().length} 个平台 · ${accounts.where((a) => a.low || a.unavailable).length} 个来源需关注',
                style: const TextStyle(fontSize: 12, color: sceneMuted),
              ),
              if (accounts.isEmpty) const Text('暂未取得额度数据'),
              if (accounts.isNotEmpty) ...quotaCollapsedExtras(accounts),
              if (status != null) status!,
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          ...quotaPlatformCards(accounts),
          if (onDetails != null)
            TextButton(onPressed: onDetails, child: const Text('查看完整详情与历史')),
        ],
      ),
    );
  }
}

List<String> purchaseOverview(Map<String, dynamic> data, String group) {
  final overview = sceneMap(data['overview']);
  final raw = overview[group];
  return raw is List && raw.isNotEmpty
      ? raw.whereType<String>().toList()
      : [group == 'expense' ? '消费摘要暂未取得，金额未知' : '快递摘要暂未取得，状态未知'];
}
