import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets('challenge announcement is separate from actual account resets', (
    t,
  ) async {
    MethodCall? opened;
    const channel = MethodChannel('site.zhangyue.vault/sys');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          opened = call;
          return true;
        });
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: TiboChallengeCard())),
    );
    expect(find.textContaining('不代表您的账户已经重置'), findsOneWidget);
    await t.tap(find.text('查看28天动态'));
    await t.pump();
    expect(opened?.method, 'openUrl');
    expect((opened?.arguments as Map)['url'], 'https://tibo-28.hdj.me/');
    expect((opened?.arguments as Map).containsKey('token'), isFalse);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
