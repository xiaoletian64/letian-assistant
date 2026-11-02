import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

http.Response json(Object x, [int status = 200]) => http.Response(
  jsonEncode(x),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('site.zhangyue.vault/notifications'),
          (call) async => call.method == 'status'
              ? {'authorization': 'unsupported', 'background_available': false}
              : call.method == 'clearBindings'
              ? true
              : null,
        );
  });
  testWidgets('password login opens shell and binds server canonical identity', (
    t,
  ) async {
    apiClient = MockClient((r) async {
      if (r.url.path == '/api/login') {
        expect(r.method, 'POST');
        return json({'token': 'alice-token'});
      }
      if (r.url.path == '/api/me') return json({'username': 'Alice'});
      return json({'schema_version': 2, 'plugins': []});
    });
    await t.pumpWidget(const MaterialApp(home: LoginPage()));
    await t.enterText(find.byType(TextField).at(0), 'alice');
    await t.enterText(find.byType(TextField).at(1), 'fixture-password');
    await t.tap(find.widgetWithText(FilledButton, '登录'));
    await t.pumpAndSettle();
    expect(find.byType(SceneShell), findsOneWidget);
    expect(await token(), 'alice-token');
    final p = await SharedPreferences.getInstance();
    final binding =
        'dashboard.account.${cryptoSha256(utf8.encode('$baseUrl|alice-token'))}';
    expect(p.getString(binding), cryptoSha256(utf8.encode('$baseUrl|Alice')));
  });
  testWidgets('wrong password stays on login and never saves a token', (
    t,
  ) async {
    apiClient = MockClient(
      (r) async => json({'error': 'bad_credentials'}, 401),
    );
    await t.pumpWidget(const MaterialApp(home: LoginPage()));
    await t.enterText(find.byType(TextField).at(0), 'alice');
    await t.enterText(find.byType(TextField).at(1), 'wrong');
    await t.tap(find.widgetWithText(FilledButton, '登录'));
    await t.pumpAndSettle();
    expect(find.text('用户名或密码错误'), findsOneWidget);
    expect(await token(), isNull);
  });
  testWidgets('network failure does not remove token or claim verified login', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({'token': 'saved'});
    apiClient = MockClient((r) async => json({}, 503));
    await t.pumpWidget(const MaterialApp(home: SceneShell()));
    await t.pumpAndSettle();
    expect(await token(), 'saved');
    expect(find.byType(LoginPage), findsNothing);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    expect(find.text('身份暂未确认'), findsOneWidget);
  });
  testWidgets(
    'identity refresh failure is shown as unverified even after prior success',
    (t) async {
      SharedPreferences.setMockInitialValues({'token': 'saved'});
      var fail = false;
      apiClient = MockClient(
        (r) async => r.url.path == '/api/me'
            ? fail
                  ? json({}, 503)
                  : json({'username': 'alice'})
            : json({'schema_version': 2, 'plugins': []}),
      );
      await t.pumpWidget(const MaterialApp(home: SceneShell()));
      await t.pumpAndSettle();
      fail = true;
      await t.fling(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 350),
        1000,
      );
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      expect(find.text('身份暂未确认'), findsOneWidget);
      expect(await token(), 'saved');
    },
  );
  testWidgets(
    'logout cancellation retains session, confirmed logout clears stack',
    (t) async {
      SharedPreferences.setMockInitialValues({'token': 'saved'});
      apiClient = MockClient(
        (r) async => json(
          r.url.path == '/api/me'
              ? {'username': 'alice'}
              : {'schema_version': 2, 'plugins': []},
        ),
      );
      await t.pumpWidget(const MaterialApp(home: SceneShell()));
      await t.pumpAndSettle();
      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      await t.tap(find.text('退出登录'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(await token(), 'saved');
      await t.tap(find.text('退出登录'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '退出登录'));
      await t.pumpAndSettle();
      expect(await token(), isNull);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(SceneShell), findsNothing);
    },
  );
}
