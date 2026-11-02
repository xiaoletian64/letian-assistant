import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets(
    'Cursor and personal organization GitHub rows keep full readings at phone and large text sizes',
    (t) async {
      final accounts = quotaAccounts({
        'collected_at': '2026-10-26T12:00:00+08:00',
        'accounts': {
          'cursor': {
            'total_percent': 26.5,
            'auto_percent': 0,
            'api_percent': 125,
            'cycle_end': '2026-11-25T12:00:00Z',
          },
        },
        'push': {
          'gha': {
            'personal': {'included': 2000, 'left': 32},
            'org': {'included': 50000, 'left': 49123.5},
            'note': '每月1日重置；以GitHub账单周期为准，组织与个人独立计量',
          },
        },
      });
      for (final spec in [
        (390.0, 1.0),
        (320.0, 1.8),
        (760.0, 1.0),
        (1000.0, 2.0),
      ]) {
        t.view.physicalSize = Size(spec.$1, 1800);
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(spec.$1, 1800),
                textScaler: TextScaler.linear(spec.$2),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final a in accounts) QuotaAccountCard(account: a),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '$spec must not overflow');
        for (final reading in [
          '剩余 73.5%',
          '剩余 100%',
          '剩余 32 分钟',
          '剩余 49123.5 分钟',
        ]) {
          expect(find.text(reading), findsOneWidget);
        }
        expect(find.text('个人账号'), findsOneWidget);
        expect(find.text('组织账号'), findsOneWidget);
        expect(find.textContaining('125%'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
      }
      await t.pumpWidget(const SizedBox());
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}
