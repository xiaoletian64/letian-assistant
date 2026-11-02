import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

http.Response response(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'token': 'acceptance-fixture-only',
    }),
  );
  testWidgets(
    'key password challenge reveals only after nonce and can hide again',
    (t) async {
      final paths = <String>[];
      apiClient = MockClient((r) async {
        paths.add(r.url.path);
        if (r.url.path.endsWith('/challenge')) {
          expect(jsonDecode(r.body)['password'], 'fixture-password');
          return response({'nonce': 'fixture-once'});
        }
        expect(r.url.queryParameters['nonce'], 'fixture-once');
        return response({'appkey': 'fixture-key-not-real'});
      });
      await t.pumpWidget(const MaterialApp(home: AppkeyPage()));
      await t.tap(find.text('验证并查看'));
      await t.pumpAndSettle();
      expect(paths, isEmpty);
      await t.enterText(find.byType(TextField), 'fixture-password');
      await t.tap(find.text('验证并查看'));
      await t.pumpAndSettle();
      expect(find.text('fixture-key-not-real'), findsOneWidget);
      expect(paths.length, 2);
      await t.tap(find.text('隐藏密钥'));
      await t.pumpAndSettle();
      expect(find.text('fixture-key-not-real'), findsNothing);
    },
  );
  testWidgets(
    'deal cancel never applies and confirmed submission is single flight',
    (t) async {
      var posts = 0;
      final pending = Completer<http.Response>();
      apiClient = MockClient((r) async {
        if (r.method == 'POST') {
          posts++;
          expect(jsonDecode(r.body)['offer_id'], 'fixture');
          return pending.future;
        }
        return response(
          r.url.path.endsWith('/status')
              ? {'login': true}
              : {
                  'items': [
                    {
                      'id': 'fixture',
                      'title': '验收活动',
                      'pic': '',
                      'applied': false,
                      'vip': false,
                    },
                  ],
                },
        );
      });
      await t.pumpWidget(const MaterialApp(home: DealsPage()));
      await t.pumpAndSettle();
      await t.tap(find.text('报名免费试'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(posts, 0);
      await t.tap(find.text('报名免费试'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '报名'));
      await t.pump();
      await t.pump();
      expect(posts, 1);
      expect(find.text('正在提交报名，请稍候。结果返回前请勿重复报名。'), findsOneWidget);
      pending.complete(response({'ok': true}));
      await t.pumpAndSettle();
      expect(posts, 1);
    },
  );
  testWidgets(
    'gateway confirmation cancels and commits exactly one fixture request',
    (t) async {
      var posts = 0;
      final pending = Completer<http.Response>();
      apiClient = MockClient((r) async {
        if (r.method == 'POST') {
          posts++;
          return pending.future;
        }
        return response({
          'title': '网关状态',
          'items': [],
          'actions': [
            {
              'label': '重启网关',
              'type': 'confirm_post',
              'path': '/api/hub/lobster/restart',
              'confirm': '验收替身确认',
            },
          ],
        });
      });
      await t.pumpWidget(
        const MaterialApp(
          home: PluginPage(id: 'gateway', title: '网关状态'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('重启网关'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(posts, 0);
      await t.tap(find.text('重启网关'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      await t.tap(find.widgetWithText(FilledButton, '确认'));
      await t.pump();
      await t.pump();
      expect(posts, 1);
      expect(
        t
            .widget<FilledButton>(
              find
                  .ancestor(
                    of: find.text('处理中…'),
                    matching: find.byWidgetPredicate((w) => w is FilledButton),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      pending.complete(response({'ok': true}));
      await t.pumpAndSettle();
      expect(posts, 1);
    },
  );
  testWidgets(
    'low power cancel preserves mode and fixture success reloads state',
    (t) async {
      var posts = 0;
      var enabled = false;
      apiClient = MockClient((r) async {
        if (r.method == 'POST') {
          posts++;
          enabled = true;
          return response({'ok': true});
        }
        return response({
          'LOWPOWER': enabled ? 'active' : 'inactive',
          'services': {},
          'user_services': {},
          'containers': [],
        });
      });
      await t.pumpWidget(const MaterialApp(home: ConsoleStatusPage()));
      await t.pumpAndSettle();
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(posts, 0);
      expect(t.widget<Switch>(find.byType(Switch)).value, false);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '确认'));
      await t.pumpAndSettle();
      expect(posts, 1);
      expect(t.widget<Switch>(find.byType(Switch)).value, true);
    },
  );
  testWidgets(
    'scene executes confirmation token protocol using network fixture only',
    (t) async {
      final writes = <String>[];
      apiClient = MockClient((r) async {
        if (r.method == 'POST') {
          writes.add(r.url.path);
          if (r.url.path.endsWith('/confirm')) {
            expect(jsonDecode(r.body)['kind'], 'scene');
            expect(jsonDecode(r.body)['scene_id'], 'fixture-scene');
            return response({'token': 'fixture-command-token'});
          }
          expect(jsonDecode(r.body)['token'], 'fixture-command-token');
          return response({'ok': true});
        }
        return response(
          r.url.path.endsWith('/scenes')
              ? {
                  'scenes': [
                    {
                      'id': 'fixture-scene',
                      'name': '验收替身场景',
                      'home_id': 'fixture-home',
                    },
                  ],
                }
              : {
                  'homes': [
                    {'id': 'fixture-home', 'name': '验收家庭'},
                  ],
                  'devices': [],
                },
        );
      });
      await t.pumpWidget(const MaterialApp(home: MihomePage()));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('验收替身场景'));
      await t.tap(find.text('验收替身场景'));
      await t.pumpAndSettle();
      expect(writes, ['/api/hub/mihome/confirm', '/api/hub/mihome/cmd']);
    },
  );
}
