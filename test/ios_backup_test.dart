import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

void main() {
  const channel = MethodChannel('site.zhangyue.vault/sync');
  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'synthetic-owner'});
    runtimeConfig = RuntimeConfig.fromJson({
      'schema_version': 1,
      'api_base_url': 'https://api.example.org',
      'update_manifest_url': 'https://updates.example.org/latest.json',
    });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  testWidgets('cancelled directory selection never uploads', (t) async {
    var uploads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'syncBackup') uploads++;
          return null;
        });
    await t.pumpWidget(const MaterialApp(home: IosBackupPage()));
    await t.tap(find.text('选择备份目录'));
    await t.pumpAndSettle();
    expect(find.text('已取消选择'), findsOneWidget);
    expect(uploads, 0);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
  testWidgets('backup uses current account and ignores stale account result', (
    t,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    Map? args;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pickTree') return {'name': '示例备份目录'};
          if (call.method == 'syncBackup') {
            args = call.arguments as Map;
            return pending.future;
          }
          return null;
        });
    await t.pumpWidget(const MaterialApp(home: IosBackupPage()));
    await t.tap(find.text('选择备份目录'));
    await t.pumpAndSettle();
    await t.tap(find.text('上传所选目录的备份'));
    await t.pump();
    await t.pump();
    expect(args?['server'], 'https://api.example.org');
    expect(args?['token'], 'synthetic-owner');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', 'synthetic-other');
    pending.complete({'uploaded': 1, 'failed': 0});
    await t.pumpAndSettle();
    expect(find.textContaining('上传 1 份'), findsNothing);
  });
}
