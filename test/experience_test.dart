import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'token': 'test'}));
  testWidgets(
    'authorization failure has a retry instead of disconnected accounts',
    (tester) async {
      apiClient = MockClient((r) async => jsonResponse({}, 503));
      await tester.pumpWidget(const MaterialApp(home: QrPage()));
      await tester.pumpAndSettle();
      expect(find.text('重新加载'), findsOneWidget);
      expect(find.text('抖音'), findsNothing);
    },
  );
  testWidgets('plugin refresh retains readable previous data when it fails', (
    tester,
  ) async {
    var count = 0;
    apiClient = MockClient(
      (r) async => ++count == 1
          ? jsonResponse({
              'title': '测试',
              'items': [
                {'title': '保留内容'},
              ],
            })
          : jsonResponse({}, 503),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: PluginPage(id: 'test', title: '测试'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('保留内容'), findsOneWidget);
    expect(find.textContaining('更新未完成'), findsOneWidget);
  });
  testWidgets(
    'plugin confirmed action cannot be submitted twice and recovers after failure',
    (tester) async {
      final pending = Completer<http.Response>();
      var writes = 0;
      apiClient = MockClient((r) async {
        if (r.method == 'POST') {
          writes++;
          return pending.future;
        }
        return jsonResponse({
          'title': '测试',
          'items': [],
          'actions': [
            {
              'type': 'confirm_post',
              'label': '执行操作',
              'path': '/api/hub/test',
              'confirm': '确认测试',
            },
          ],
        });
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: PluginPage(id: 'test', title: '测试'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('执行操作'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.tap(find.text('执行操作'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('确认'));
      await tester.pump();
      await tester.pump();
      expect(writes, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton).first,
            )
            .onPressed,
        isNull,
      );
      pending.complete(jsonResponse({}, 503));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton).first,
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('short session dates and empty search have safe feedback', (
    tester,
  ) async {
    apiClient = MockClient(
      (r) async => jsonResponse({
        'count': 1,
        'sessions': [
          {
            'id': 'one',
            'title': '对话',
            'last_active': '',
            'preview': '内容',
            'count': 1,
          },
        ],
      }),
    );
    await tester.pumpWidget(const MaterialApp(home: SessionsPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'nomatch');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的会话'), findsOneWidget);
  });
  testWidgets('camera failed task fetch never claims there are no tasks', (
    tester,
  ) async {
    apiClient = MockClient((r) async => jsonResponse({}, 503));
    await tester.pumpWidget(const MaterialApp(home: CameraPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前没有待处理任务'), findsNothing);
    expect(find.text('重新加载'), findsOneWidget);
  });
  testWidgets('console safely finishes a read after leaving the page', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    apiClient = MockClient((r) async => pending.future);
    await tester.pumpWidget(const MaterialApp(home: ConsoleStatusPage()));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('已离开')));
    pending.complete(jsonResponse({}));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('deals empty list has a readable explanation', (tester) async {
    apiClient = MockClient(
      (r) async => r.url.path.endsWith('/status')
          ? jsonResponse({'login': true})
          : jsonResponse({'items': []}),
    );
    await tester.pumpWidget(const MaterialApp(home: DealsPage()));
    await tester.pumpAndSettle();
    expect(find.text('暂时没有免费试活动'), findsOneWidget);
  });
  testWidgets('home device scene and device list support large text on 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    apiClient = MockClient(
      (r) async => jsonResponse(
        r.url.path.endsWith('/scenes')
            ? {
                'scenes': [
                  {'id': 'scene', 'name': '晚间阅读和休息场景', 'home_id': 'house'},
                ],
              }
            : {
                'homes': [
                  {'id': 'house', 'name': '我的家庭'},
                ],
                'devices': [
                  {
                    'did': 'test',
                    'home_id': 'house',
                    'name': '客厅空气净化器',
                    'online': false,
                    'category': 'airpurifier',
                    'category_label': '空气净化器',
                    'room': '客厅',
                    'model': 'test',
                    'art': {'status': 'ready'},
                  },
                ],
              },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: const MihomePage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
