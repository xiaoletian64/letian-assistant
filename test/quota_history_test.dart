import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets('history keeps unknown values and source timestamps distinct', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuotaHistoryPage(
          fetchPage: (_) async => {
            'items': [
              {
                'provider': 'codex',
                'account': 'a',
                'window': 'weekly',
                'units': 'percent',
                'observed_time': 100,
                'source_time': 90,
                'used': null,
                'remaining': 90,
                'limit': 100,
                'event': 'candidate',
              },
            ],
            'next_cursor': null,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('已用 未知'), findsOneWidget);
    expect(find.textContaining('候选变化'), findsOneWidget);
    expect(find.textContaining('来源时间'), findsOneWidget);
  });
  testWidgets('failure supports retry without invented history', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: QuotaHistoryPage(
          fetchPage: (_) async {
            calls++;
            if (calls == 1) throw Exception('offline');
            return {'items': [], 'next_cursor': null};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无历史采样'), findsOneWidget);
    expect(calls, 2);
  });
  testWidgets('authorization loss clears previously loaded private history', (
    t,
  ) async {
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: QuotaHistoryPage(
          fetchPage: (_) async {
            if (++calls > 1) {
              throw AccessDenied();
            }
            return {
              'items': [
                {
                  'provider': 'private-provider',
                  'account': 'account-a',
                  'window': 'weekly',
                },
              ],
              'next_cursor': null,
            };
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('private-provider · account-a · weekly'), findsOneWidget);
    await t.tap(find.text('应用筛选'));
    await t.pumpAndSettle();
    expect(find.text('private-provider · account-a · weekly'), findsNothing);
    expect(find.text('当前账号无权查看额度历史'), findsOneWidget);
  });
}
