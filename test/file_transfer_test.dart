import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets(
    'canceling system save shows explicit cancellation and permits retry',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      const channel = MethodChannel('site.zhangyue.vault/sys');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            return false;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => openPrivateFile(
                  c,
                  '/api/test',
                  'test.pdf',
                  'application/pdf',
                ),
                child: const Text('下载文件'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('下载文件'));
      await tester.pumpAndSettle();
      expect(find.text('已取消保存'), findsOneWidget);
      await tester.tap(find.text('下载文件'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );
}
