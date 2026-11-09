import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets('missing and untrusted images keep placeholders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: orderProductImages([
            {'title': '咖啡', 'image_url': null},
            {
              'title': '茶',
              'image_url': 'https://alicdn.com.evil.example/a.jpg',
            },
          ]),
        ),
      ),
    );
    expect(find.text('暂无商品图'), findsNWidgets(2));
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
