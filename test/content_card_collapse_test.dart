import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets('details and open action are hidden until expanded', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollapsibleContentCard(
            item: const {
              'title': '昨日消费',
              'subtitle': '北京时间 · 数据不完整',
              'body': '退款到账金额未知',
            },
            onOpen: () => opened++,
          ),
        ),
      ),
    );
    expect(find.text('退款到账金额未知'), findsNothing);
    expect(find.text('打开原文'), findsNothing);
    await tester.tap(find.text('昨日消费'));
    await tester.pumpAndSettle();
    expect(find.text('退款到账金额未知'), findsOneWidget);
    await tester.tap(find.text('打开原文'));
    expect(opened, 1);
    await tester.tap(find.text('昨日消费'));
    await tester.pumpAndSettle();
    expect(find.text('退款到账金额未知'), findsNothing);
  });
  testWidgets('order images and full detail remain inside the collapsed card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CollapsibleContentCard(
              item: {
                'type': 'order',
                'title': '订单',
                'products': [
                  {'title': '合成商品', 'image_url': null},
                ],
                'body': '物流尚未获取',
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('暂无商品图'), findsNothing);
    await tester.tap(find.text('订单'));
    await tester.pumpAndSettle();
    expect(find.text('暂无商品图'), findsOneWidget);
    expect(find.text('物流尚未获取'), findsOneWidget);
    await tester.tap(find.text('订单'));
    await tester.pumpAndSettle();
    expect(find.text('暂无商品图'), findsNothing);
  });
}
