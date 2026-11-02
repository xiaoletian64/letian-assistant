part of 'main.dart';

class TiboChallengeCard extends StatelessWidget {
  const TiboChallengeCard({super.key});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tibo · 28天挑战', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('产品更新与额度重置公告。公告不代表您的账户已经重置，实际变化以账户采样历史为准。'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('查看28天动态'),
                onPressed: () => openLink(context, 'https://tibo-28.hdj.me/'),
              ),
              TextButton.icon(
                icon: const Icon(Icons.history),
                label: const Text('额度与重置历史'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const QuotaHistoryPage(fetchPage: fetchQuotaHistory),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('动态来源：独立追踪看板，可查看其中的公告原帖。', style: TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}

Future<Map<String, dynamic>> fetchQuotaHistory(
  Map<String, String> query,
) async {
  final account = await token();
  if (account == null) throw SessionExpired();
  final suffix = Uri(queryParameters: query).query;
  final result = await apiGet(
    '/api/hub/quota/history${suffix.isEmpty ? '' : '?$suffix'}',
  );
  if (account != await token()) throw SessionExpired();
  if (result is! Map) throw const FormatException('额度历史格式异常');
  return Map<String, dynamic>.from(result);
}
