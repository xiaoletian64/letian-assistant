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
