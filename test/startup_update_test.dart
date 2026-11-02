import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vault/main.dart';

void main() {
  setUp(
    () => runtimeConfig = RuntimeConfig.fromJson({
      'schema_version': 1,
      'api_base_url': 'https://api.example.org',
      'update_manifest_url': 'https://updates.example.org/latest.json',
    }),
  );
  Widget app() {
    final key = GlobalKey<NavigatorState>();
    return MaterialApp(
      navigatorKey: key,
      builder: (c, child) =>
          StartupUpdateObserver(navigatorKey: key, child: child!),
      home: const Scaffold(body: Text('应用内容')),
    );
  }

  setUp(
    () => otaClient = MockClient(
      (r) async => http.Response(
        jsonEncode({
          'versionCode': currentVersionCode + 1,
          'versionName': '测试新版',
          'notes': '更新说明',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );
  testWidgets('opening app automatically prompts for newer release', (t) async {
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(find.text('发现新版本 测试新版'), findsOneWidget);
    await t.tap(find.text('以后'));
    await t.pumpAndSettle();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('发现新版本 测试新版'), findsNothing);
  });
  testWidgets('late response after disposal does not open a dialog', (t) async {
    final response = Completer<http.Response>();
    otaClient = MockClient((r) => response.future);
    await t.pumpWidget(app());
    await t.pump();
    await t.pumpWidget(const SizedBox());
    response.complete(
      http.Response(
        jsonEncode({
          'versionCode': currentVersionCode + 1,
          'versionName': '新版',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('automatic and manual requests do not stack update dialogs', (
    t,
  ) async {
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    final c = t.element(find.text('应用内容'));
    showUpdateDialog(c, {'versionName': '另一提示'});
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.text('以后'));
    await t.pumpAndSettle();
  });
  testWidgets(
    'login navigation during check still prompts once on destination',
    (t) async {
      final response = Completer<http.Response>();
      otaClient = MockClient((r) => response.future);
      await t.pumpWidget(app());
      await t.pump();
      Navigator.of(t.element(find.text('应用内容'))).pushReplacement(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('登录后首页'))),
      );
      await t.pumpAndSettle();
      response.complete(
        http.Response(
          jsonEncode({
            'versionCode': currentVersionCode + 1,
            'versionName': '登录后新版',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('发现新版本 登录后新版'), findsOneWidget);
      await t.tap(find.text('以后'));
      await t.pumpAndSettle();
    },
  );
  testWidgets('real app prompts on startup before login', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(const VaultApp());
    await t.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('发现新版本 测试新版'), findsOneWidget);
    await t.tap(find.text('以后'));
    await t.pumpAndSettle();
  });
  testWidgets('current release stays silent', (t) async {
    otaClient = MockClient(
      (r) async => http.Response(
        jsonEncode({'versionCode': currentVersionCode}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });
  testWidgets('network failure stays silent', (t) async {
    otaClient = MockClient((r) async => throw Exception('offline'));
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('应用内容'), findsOneWidget);
  });
}
