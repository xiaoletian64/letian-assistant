import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets(
    'one platform heading preserves direct and pushed Cursor accounts',
    (t) async {
      final accounts = quotaAccounts({
        'accounts': {
          'cursor': {
            'total_percent': 25,
            'auto_percent': 12,
            'api_percent': 80,
          },
        },
        'push': {
          'cursor': {
            'accounts': [
              {
                'n': 'Cursor(pro)',
                'rem':
                    'autoPercentUsed=1.75% used; totalPercentUsed=1.59% used',
              },
              {'n': '另一真实账号（保留独立来源和周期）', 'rem': '独立额度待来源确认'},
            ],
          },
        },
      });
      for (final spec in [(390.0, 1.0), (320.0, 1.5), (320.0, 2.0)]) {
        await t.pumpWidget(const SizedBox());
        t.view.physicalSize = Size(spec.$1, 1800);
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(spec.$2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Column(children: quotaPlatformCards(accounts)),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Cursor'), findsOneWidget);
        expect(find.text('Cursor(pro)'), findsNothing);
        await t.tap(find.text('推送来源详情（2 个账号）'));
        await t.pumpAndSettle();
        expect(find.text('Cursor(pro)'), findsOneWidget);
        expect(find.text('另一真实账号（保留独立来源和周期）'), findsOneWidget);
        for (final value in [
          '剩余 75%',
          '剩余 88%',
          '剩余 20%',
          '剩余 98.41%',
          '剩余 98.25%',
          '独立额度待来源确认',
        ]) {
          expect(find.text(value), findsOneWidget);
        }
      }
      await t.pumpWidget(const SizedBox());
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}
