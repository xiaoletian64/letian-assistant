import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadBundledPluginCatalog();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'test-token'});
    apiClient = MockClient(
      (request) async => request.url.path == '/api/me'
          ? jsonResponse({'username': 'alice'}, 200)
          : http.Response('{}', 503),
    );
  });
  testWidgets('directory failure remains visible and retryable', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('工具目录暂时无法更新'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '重试'), findsOneWidget);
    expect(find.text('我的家'), findsOneWidget);
  });
  testWidgets('search gives explicit no-results recovery', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不存在的入口xyz');
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关工具'), findsOneWidget);
    await tester.ensureVisible(find.text('清除搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('我的家'), findsOneWidget);
  });
  testWidgets('favorites survive a dashboard remount', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('收藏我的家'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收藏我的家'));
    await tester.pumpAndSettle();
    expect(find.text('我的收藏'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.byTooltip('取消收藏我的家'), findsWidgets);
  });
  testWidgets('narrow screen with large text stays usable', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: const HomePage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('生活服务'), findsOneWidget);
  });
  testWidgets(
    'favorites and directory are isolated across A B A and token renewal',
    (tester) async {
      apiClient = MockClient((r) async {
        final alice =
            r.headers['authorization'] == 'Bearer test-token' ||
            r.headers['authorization'] == 'Bearer alice-renewed';
        return r.url.path == '/api/me'
            ? jsonResponse({'username': alice ? 'alice' : 'bob'}, 200)
            : jsonResponse({
                'schema_version': 2,
                'plugins': [
                  {'id': 'home', 'title': '我的家', 'renderer': 'devices'},
                  {
                    'id': 'private',
                    'title': alice ? 'Alice工具' : 'Bob工具',
                    'group': '日常使用',
                  },
                ],
              }, 200);
      });
      Future<void> mount() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();
      }

      await mount();
      await tester.ensureVisible(find.byTooltip('收藏我的家'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('收藏我的家'));
      await tester.pumpAndSettle();
      expect(find.text('Alice工具'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', 'bob-token');
      await mount();
      expect(find.text('我的收藏'), findsNothing);
      expect(find.text('Alice工具'), findsNothing);
      expect(find.text('Bob工具'), findsOneWidget);
      await prefs.setString('token', 'alice-renewed');
      await mount();
      expect(find.text('我的收藏'), findsOneWidget);
      expect(find.text('Bob工具'), findsNothing);
    },
  );
  testWidgets(
    'failed directory refresh uses cache and successful empty response removes it',
    (tester) async {
      var fail = false, empty = false;
      apiClient = MockClient(
        (r) async => r.url.path == '/api/me'
            ? jsonResponse({'username': 'alice'}, 200)
            : fail
            ? http.Response('{}', 503)
            : jsonResponse({
                'schema_version': 2,
                'plugins': empty
                    ? []
                    : [
                        {'id': 'saved', 'title': '缓存工具'},
                      ],
              }, 200),
      );
      Future<void> mount() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();
      }

      await mount();
      expect(find.text('缓存工具'), findsOneWidget);
      fail = true;
      await mount();
      expect(find.text('缓存工具'), findsOneWidget);
      expect(find.textContaining('正在显示上次保存的工具目录'), findsOneWidget);
      fail = false;
      empty = true;
      await tester.tap(find.byTooltip('刷新工具目录'));
      await tester.pumpAndSettle();
      expect(find.text('缓存工具'), findsNothing);
      fail = true;
      await mount();
      expect(find.text('缓存工具'), findsNothing);
    },
  );
  testWidgets(
    'identity failure never writes favorites to a temporary account',
    (tester) async {
      var failIdentity = true;
      apiClient = MockClient(
        (r) async => r.url.path == '/api/me'
            ? failIdentity
                  ? http.Response('{}', 503)
                  : jsonResponse({'username': 'alice'}, 200)
            : jsonResponse({
                'schema_version': 2,
                'plugins': [
                  {'id': 'home', 'title': '我的家', 'renderer': 'devices'},
                  {'id': 'auth', 'title': '账号授权', 'renderer': 'authorization'},
                ],
              }, 200),
      );
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      final star = find.byTooltip('收藏我的家');
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: star, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNull,
      );
      failIdentity = false;
      await tester.tap(find.byTooltip('刷新工具目录'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: star, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'recent history survives remount and a failed refresh keeps tools',
    (tester) async {
      apiClient = MockClient(
        (r) async => r.url.path == '/api/me'
            ? jsonResponse({'username': 'alice'}, 200)
            : jsonResponse({
                'schema_version': 2,
                'plugins': [
                  {'id': 'home', 'title': '我的家', 'renderer': 'devices'},
                  {'id': 'auth', 'title': '账号授权', 'renderer': 'authorization'},
                ],
              }, 200),
      );
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('账号授权'));
      await tester.tap(find.text('账号授权'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      expect(find.text('最近使用'), findsOneWidget);
    },
  );
}
