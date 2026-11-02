import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

http.Response jsonResponse(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadBundledPluginCatalog();
  });
  setUp(() => SharedPreferences.setMockInitialValues({'token': 'test'}));
  testWidgets(
    'server catalog controls every entry and resolves a native adapter',
    (tester) async {
      final paths = <String>[];
      apiClient = MockClient((r) async {
        paths.add(r.url.path);
        return r.url.path == '/api/me'
            ? jsonResponse({'username': 'test'})
            : r.url.path == '/api/hub/plugins'
            ? jsonResponse({
                'schema_version': 2,
                'plugins': [
                  {
                    'id': 'auth',
                    'title': '连接中心',
                    'renderer': 'authorization',
                    'category': '设备管理',
                  },
                ],
              })
            : jsonResponse({
                'douyin': {'logged_in': true},
                'dianping': {'logged_in': true},
              });
      });
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      expect(find.text('我的家'), findsNothing);
      expect(find.text('点评免费试'), findsNothing);
      await tester.ensureVisible(find.text('连接中心'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('连接中心'));
      await tester.pumpAndSettle();
      expect(find.text('账号授权'), findsOneWidget);
      expect(paths, contains('/api/qr/all'));
      expect(paths, isNot(contains('/api/hub/plugins/open')));
    },
  );
  testWidgets(
    'successful empty catalog never restores fixed or bundled entries',
    (tester) async {
      apiClient = MockClient(
        (r) async => jsonResponse(
          r.url.path == '/api/me'
              ? {'username': 'test'}
              : {'schema_version': 2, 'plugins': []},
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      expect(find.text('我的家'), findsNothing);
      expect(find.text('没有找到相关工具'), findsOneWidget);
    },
  );
  testWidgets('legacy favorites migrate to catalog IDs', (tester) async {
    final scope = cryptoSha256(utf8.encode('$baseUrl|test'));
    SharedPreferences.setMockInitialValues({
      'token': 'test',
      'dashboard.v1.$scope.favorites': ['auth'],
    });
    apiClient = MockClient(
      (r) async => jsonResponse(
        r.url.path == '/api/me'
            ? {'username': 'test'}
            : {
                'schema_version': 2,
                'plugins': [
                  {'id': 'auth', 'title': '连接中心', 'renderer': 'authorization'},
                ],
              },
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消收藏连接中心'), findsWidgets);
  });
  testWidgets(
    'unsupported adapter gives upgrade information rather than wrong page',
    (tester) async {
      apiClient = MockClient(
        (r) async => jsonResponse(
          r.url.path == '/api/me'
              ? {'username': 'test'}
              : {
                  'schema_version': 2,
                  'plugins': [
                    {
                      'id': 'future',
                      'title': '新能力',
                      'renderer': 'unknown',
                      'min_client_code': 999,
                    },
                  ],
                },
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('新能力'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新能力'));
      await tester.pumpAndSettle();
      expect(find.text('此插件需要更新客户端'), findsOneWidget);
    },
  );
  testWidgets(
    'old server response does not replace a compatible bootstrap catalog',
    (tester) async {
      apiClient = MockClient(
        (r) async => jsonResponse(
          r.url.path == '/api/me'
              ? {'username': 'test'}
              : {
                  'plugins': [
                    {'id': 'old', 'title': '旧目录'},
                  ],
                },
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      expect(find.text('我的家'), findsOneWidget);
      expect(find.text('旧目录'), findsNothing);
      expect(find.textContaining('目录版本不兼容'), findsOneWidget);
    },
  );
}
