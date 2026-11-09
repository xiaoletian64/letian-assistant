import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  final now = DateTime.now().toUtc();
  Map<String, dynamic> codex(String name, {String? error}) => {
    'n': 'Codex-$name(prolite)',
    'ts': now.millisecondsSinceEpoch ~/ 1000,
    'fh': {'u': 99, 'window_seconds': 604800},
    if (error != null) 'error': error,
  };

  test('balances retain cents and Codex names are readable', () {
    final rows = quotaAccounts({
      'collected_at': now.toIso8601String(),
      'accounts': {
        'tencent': {'amount': 8.32, 'currency': 'CNY'},
      },
      'push': {
        'codex': {
          'accounts': [codex('CM')],
        },
      },
    });
    expect(rows.first.windows.single.value, '余额 ¥8.32');
    expect(rows.last.name, 'CM 账户');
    expect(rows.last.windows.single.period, '7天窗口');
  });

  test('a partial provider failure affects only its failed account', () {
    final rows = quotaAccounts({
      'push': {
        'codex': {
          'lastError': 'partial_collection_failed',
          'account_errors': {'Codex-CM(prolite)': 'http_401'},
          'accounts': [codex('CM'), codex('ZY')],
        },
      },
    });
    expect(rows[0].error, contains('认证'));
    expect(rows[1].error, isEmpty);
  });

  test('provider failure is not hidden by a recent observation', () {
    final rows = quotaAccounts({
      'push': {
        'jev': {
          'lastError': 'HTTPError',
          'updated_at': now.millisecondsSinceEpoch ~/ 1000,
          'accounts': [
            {
              'n': 'JEV',
              'bal': {'amt': 4.99, 'cur': 'USD'},
            },
          ],
        },
      },
    });
    expect(rows.first.error, isNotEmpty);
  });

  test('unrecognized error keys do not suppress provider failure', () {
    final rows = quotaAccounts({
      'push': {
        'codex': {
          'lastError': 'collection_failed',
          'account_errors': {'absent-account': 'http_401'},
          'accounts': [codex('CM')],
        },
      },
    });
    expect(rows.single.error, isNotEmpty);
  });

  test('GitHub personal failure preserves healthy organization scope', () {
    final rows = quotaAccounts({
      'push': {
        'gha': {
          'updated': now.millisecondsSinceEpoch ~/ 1000,
          'lastError': 'partial_collection_failed',
          'personal': {'left': 100, 'included': 2000, 'error': 'http_401'},
          'org': {'left': 200, 'included': 2000},
        },
      },
    }).where((a) => a.platform == 'GitHub Actions').toList();
    expect(rows[0].error, isNotEmpty);
    expect(rows[1].error, isEmpty);
  });

  test('future source time cannot masquerade as a fresh balance', () {
    final account = QuotaAccount(
      'JEV',
      '平台账号',
      const [],
      sourceTime: now.add(const Duration(days: 1)).toIso8601String(),
    );
    expect(account.unavailable, isTrue);
    expect(account.status, '来源时间异常');
  });

  testWidgets('failed current value is hidden until historical record opens', (
    t,
  ) async {
    final account = QuotaAccount(
      'JEV',
      '平台账号',
      const [QuotaWindow('账户余额', '余额 \$4.99')],
      sourceTime: now.toIso8601String(),
      error: '本次查询失败',
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: QuotaAccountCard(account: account)),
      ),
    );
    expect(find.text('当前余额未知'), findsOneWidget);
    expect(find.text('余额 \$4.99'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await t.tap(find.text('查看上次观测记录'));
    await t.pumpAndSettle();
    expect(find.text('余额 \$4.99'), findsOneWidget);
  });

  testWidgets(
    'expired percentage is historical and narrow large text stays readable',
    (t) async {
      t.view.physicalSize = const Size(320, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final account = QuotaAccount(
        'Codex',
        'CM 账户',
        const [QuotaWindow('7天窗口', '剩余 1%', remaining: 1)],
        sourceTime: now.subtract(const Duration(days: 2)).toIso8601String(),
      );
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: QuotaAccountCard(account: account),
              ),
            ),
          ),
        ),
      );
      expect(find.text('数据已过期'), findsOneWidget);
      expect(find.text('剩余 1%'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
