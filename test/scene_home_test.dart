import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

http.Response response(Object x, [int status = 200]) => http.Response(
  jsonEncode(x),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
const catalog = {
  'schema_version': 2,
  'plugins': [
    {'id': 'quota', 'title': '模型额度', 'renderer': 'content'},
    {'id': 'vehicles', 'title': '我的车', 'renderer': 'content'},
    {'id': 'sessions', 'title': '会话镜像', 'renderer': 'sessions'},
    {'id': 'auth', 'title': '账号授权', 'renderer': 'authorization'},
    {'id': 'hospital', 'title': '医院报告', 'renderer': 'content'},
    {'id': 'purchases', 'title': '综合订单', 'renderer': 'content'},
  ],
};
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'alice'});
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
  testWidgets(
    'shell shows accounts and source state, hospital stays original',
    (t) async {
      apiClient = MockClient((r) async {
        switch (r.url.path) {
          case '/api/me':
            return response({'username': 'alice'});
          case '/api/hub/plugins':
            return response(catalog);
          case '/api/quota/summary':
            return response({
              'collected_at': DateTime.now().toUtc().toIso8601String(),
              'accounts': {
                'opencode': {
                  'rolling': {'percent': 0},
                  'weekly': {'percent': 40},
                  'monthly': {'percent': 60},
                },
              },
              'push': {
                'codex': {
                  'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  'accounts': [
                    {
                      'n': '主账号',
                      'fh': {'u': 30},
                    },
                    {
                      'n': '备用账号',
                      'fh': {'u': 10},
                    },
                  ],
                },
              },
            });
          case '/api/hub/vehicles':
            return response({
              'vehicles': [
                {
                  'name': '通勤车',
                  'battery': 76,
                  'charging': 1,
                  'service_name': '联网服务',
                  'service_remaining_days': 3,
                },
              ],
            });
          case '/api/hub/sessions':
            return response({'sessions': [], 'generated_at': '2026-10-26'});
          case '/api/hub/plugins/open':
            return response({
              'items': [],
              'overview': {
                'expense': ['昨日净消费 CNY 12.50', '近30天净消费 USD 8.20'],
                'delivery': ['待发货 1 单 · 运输中 6 单（缓存状态）', '近3天签收：未知'],
              },
            });
          case '/api/qr/all':
            return response({
              'douyin': {'logged_in': true},
            });
          default:
            return response({'items': []});
        }
      });
      await t.pumpWidget(const MaterialApp(home: SceneShell()));
      await t.pumpAndSettle();
      expect(find.text('充电中'), findsWidgets);
      expect(find.textContaining('平台剩余 3 天'), findsWidgets);
      expect(find.text('昨日净消费 CNY 12.50'), findsOneWidget);
      expect(find.text('近3天签收：未知'), findsOneWidget);
      expect(find.text('主账号'), findsNothing);
      expect(find.text('备用账号'), findsNothing);
      final summary = find.byKey(const ValueKey('business-AI额度'));
      await t.ensureVisible(summary);
      await t.tap(find.text('AI额度'));
      await t.pumpAndSettle();
      expect(find.text('Codex · 主账号'), findsOneWidget);
      expect(find.text('Codex · 备用账号'), findsOneWidget);
      expect(find.textContaining('每月窗口'), findsWidgets);
      await t.ensureVisible(find.byKey(const ValueKey('hospital-entry')));
      await t.tap(find.byKey(const ValueKey('hospital-entry')));
      await t.pumpAndSettle();
      expect(find.byType(PluginPage), findsOneWidget);
    },
  );
  testWidgets('server monitor home entry follows authorized directory', (
    t,
  ) async {
    var authorized = true;
    apiClient = MockClient((r) async {
      if (r.url.path == '/api/me') return response({'username': 'alice'});
      if (r.url.path == '/api/hub/plugins') {
        return response({
          'schema_version': 2,
          'plugins': [
            if (authorized)
              {
                'id': 'server-monitor',
                'title': '服务器监控',
                'renderer': 'server-monitor',
                'owner_only': true,
              },
          ],
        });
      }
      return response({'servers': []});
    });
    await t.pumpWidget(const MaterialApp(home: SceneShell()));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-monitor-entry')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('server-monitor-entry')));
    await t.pumpAndSettle();
    expect(find.byType(ServerMonitorPage), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    authorized = false;
    await t.pumpWidget(const MaterialApp(home: SceneShell()));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-monitor-entry')), findsNothing);
  });
  testWidgets(
    'detail clears old-account data after token changes and refresh fails',
    (t) async {
      apiClient = MockClient(
        (r) async => r.headers['authorization'] == 'Bearer alice'
            ? response({
                'vehicles': [
                  {'name': 'Alice私有车辆', 'address': 'Alice私有位置'},
                ],
              })
            : response({}, 403),
      );
      await t.pumpWidget(
        const MaterialApp(home: SceneDataPage(kind: 'vehicles')),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Alice私有车辆'), findsOneWidget);
      await (await SharedPreferences.getInstance()).setString('token', 'bob');
      await t.tap(find.byTooltip('刷新'));
      await t.pumpAndSettle();
      expect(find.textContaining('Alice私有车辆'), findsNothing);
      expect(find.text('Alice私有位置'), findsNothing);
    },
  );
  testWidgets('permission revocation clears previously visible owner state', (
    t,
  ) async {
    var revoked = false;
    apiClient = MockClient((r) async {
      if (r.url.path == '/api/me') return response({'username': 'alice'});
      if (r.url.path == '/api/hub/plugins') {
        return revoked ? response({}, 403) : response(catalog);
      }
      if (r.url.path == '/api/hub/vehicles') {
        return response({
          'vehicles': [
            {'name': 'private-vehicle'},
          ],
        });
      }
      if (r.url.path == '/api/quota/summary') return response({'accounts': {}});
      if (r.url.path == '/api/hub/sessions') return response({'sessions': []});
      return response({});
    });
    await t.pumpWidget(const MaterialApp(home: SceneShell()));
    await t.pumpAndSettle();
    expect(find.textContaining('private-vehicle'), findsOneWidget);
    revoked = true;
    await t.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, 400),
    );
    await t.pump();
    await t.pumpAndSettle();
    expect(find.textContaining('private-vehicle'), findsNothing);
    expect(await token(), 'alice');
  });
  testWidgets('no permission means no protected business requests', (t) async {
    final paths = <String>[];
    apiClient = MockClient((r) async {
      paths.add(r.url.path);
      return response(
        r.url.path == '/api/me'
            ? {'username': 'bob'}
            : {'schema_version': 2, 'plugins': []},
      );
    });
    await t.pumpWidget(const MaterialApp(home: SceneShell()));
    await t.pumpAndSettle();
    expect(paths, isNot(contains('/api/quota/summary')));
    expect(paths, isNot(contains('/api/hub/sessions')));
    expect(find.text('76%'), findsNothing);
  });
  testWidgets('401 clears dashboard and returns to login', (t) async {
    apiClient = MockClient((r) async => response({}, 401));
    await t.pumpWidget(const MaterialApp(home: SceneShell()));
    await t.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(await token(), isNull);
  });
  testWidgets('late old-account response cannot overwrite new account', (
    t,
  ) async {
    final oldQuota = Completer<http.Response>();
    apiClient = MockClient((r) async {
      if (r.url.path == '/api/me') return response({'username': 'alice'});
      if (r.url.path == '/api/hub/plugins') return response(catalog);
      if (r.url.path == '/api/quota/summary') return oldQuota.future;
      if (r.url.path == '/api/hub/vehicles') return response({'vehicles': []});
      if (r.url.path == '/api/hub/sessions') return response({'sessions': []});
      return response({});
    });
    await t.pumpWidget(const MaterialApp(home: SceneShell()));
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await (await SharedPreferences.getInstance()).setString('token', 'bob');
    oldQuota.complete(
      response({
        'accounts': {
          'secret-alice-provider': {'amount': 10},
        },
      }),
    );
    await t.pumpAndSettle();
    expect(find.text('secret-alice-provider'), findsNothing);
  });
}
