import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  test('preserves account dates without treating reset as recharge', () {
    final rows = quotaAccounts({
      'collected_at': DateTime.now().toUtc().toIso8601String(),
      'accounts': {
        'cursor': {
          'total_percent': 20,
          'plan_expires_at': '2027-01-01T00:00:00Z',
          'last_recharge_at': '2026-11-01T00:00:00Z',
        },
      },
      'push': {
        'mimo': {
          'periodEndUTC': '2027-02-01T00:00:00Z',
          'accounts': [
            {
              'n': 'test',
              'rem': '剩余 30%',
              'ts': DateTime.now().toIso8601String(),
            },
          ],
        },
      },
    });
    expect(rows.first.expiresAt, '2027-01-01T00:00:00Z');
    expect(rows.first.rechargedAt, '2026-11-01T00:00:00Z');
    expect(
      rows.firstWhere((a) => a.platform == 'MiMo').periodEnd,
      '2027-02-01T00:00:00Z',
    );
    expect(rows.firstWhere((a) => a.platform == 'MiMo').rechargedAt, isNull);
  });
  testWidgets(
    'overview has images and readable dates on narrow large-text screen',
    (t) async {
      t.view.physicalSize = const Size(320, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final account = QuotaAccount(
        'MiMo',
        '套餐账号',
        const [QuotaWindow('每月额度', '剩余 12%', remaining: 12)],
        sourceTime: DateTime.now().toIso8601String(),
        expiresAt: '2027-01-01T00:00:00Z',
      );
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: QuotaOverviewCard(accounts: [account]),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(Image), findsWidgets);
      expect(find.text('套餐到期：2027-01-01 08:00（北京时间）'), findsOneWidget);
      expect(find.text('最近充值：未提供'), findsOneWidget);
      await t.tap(find.text('AI额度'));
      await t.pumpAndSettle();
      expect(find.text('MiMo'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );
}
