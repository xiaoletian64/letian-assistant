import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

http.Response ok(Object data, [int code = 200]) => http.Response(
  jsonEncode(data),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
const sid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'token': 'alice'}));
  testWidgets(
    'send persists user message, polls reply and prevents duplicate clicks',
    (t) async {
      var submitted = false, completed = false, sends = 0;
      apiClient = MockClient((r) async {
        if (r.url.path.endsWith('/status')) return ok({'connected': true});
        if (r.url.path.endsWith('/sessions')) {
          return r.method == 'POST'
              ? ok({
                  'session': {'id': sid},
                })
              : ok({'sessions': []});
        }
        if (r.url.path.endsWith('/messages')) {
          if (r.method == 'POST') {
            submitted = true;
            sends++;
            return ok({
              'job': {'id': 'job-one', 'status': 'queued'},
            }, 202);
          }
          return ok({
            'messages': [
              if (submitted) {'role': 'user', 'content': '你好龙虾'},
              if (completed) {'role': 'assistant', 'content': '你好，已收到'},
            ],
          });
        }
        if (r.url.path.contains('/jobs/')) {
          completed = true;
          return ok({
            'job': {'id': 'job-one', 'status': 'completed'},
          });
        }
        return ok({});
      });
      await t.pumpWidget(const MaterialApp(home: LobsterChatPage()));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '你好龙虾');
      await t.pump();
      await t.tap(find.text('发送'));
      await t.pump();
      await t.pump();
      expect(sends, 1);
      expect(find.text('你好龙虾'), findsWidgets);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(find.text('你好，已收到'), findsOneWidget);
      expect(sends, 1);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );
  testWidgets('uncertain network send keeps draft and reuses idempotency key', (
    t,
  ) async {
    final keys = <String>[];
    apiClient = MockClient((r) async {
      if (r.url.path.endsWith('/status')) return ok({'connected': true});
      if (r.url.path.endsWith('/sessions')) {
        return r.method == 'POST'
            ? ok({
                'session': {'id': sid},
              })
            : ok({
                'sessions': [
                  {'id': sid},
                ],
              });
      }
      if (r.method == 'POST' && r.url.path.endsWith('/messages')) {
        keys.add(jsonDecode(r.body)['idempotency_key']);
        throw http.ClientException('offline');
      }
      return ok({'messages': []});
    });
    await t.pumpWidget(const MaterialApp(home: LobsterChatPage()));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '保留草稿');
    await t.pump();
    await t.tap(find.text('发送'));
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      '保留草稿',
    );
    await t.tap(find.text('重试连接'));
    await t.pumpAndSettle();
    await t.tap(find.text('发送'));
    await t.pumpAndSettle();
    expect(keys.length, 2);
    expect(keys[0], keys[1]);
    expect(find.textContaining('草稿已保留'), findsOneWidget);
  });
  testWidgets('late history from previous account never appears', (t) async {
    final pending = Completer<http.Response>();
    apiClient = MockClient((r) async {
      if (r.url.path.endsWith('/status')) return ok({'connected': true});
      if (r.url.path.endsWith('/sessions')) {
        return ok({
          'sessions': [
            {'id': sid},
          ],
        });
      }
      return pending.future;
    });
    await t.pumpWidget(const MaterialApp(home: LobsterChatPage()));
    await t.pump();
    await t.pump();
    await (await SharedPreferences.getInstance()).setString('token', 'bob');
    pending.complete(
      ok({
        'messages': [
          {'role': 'assistant', 'content': 'alice-private'},
        ],
      }),
    );
    await t.pump();
    await t.pump();
    expect(find.text('alice-private'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('chat renders on narrow screen with large text', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(320, 900);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    apiClient = MockClient(
      (r) async => ok(
        r.url.path.endsWith('/status') ? {'connected': true} : {'sessions': []},
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: w!,
        ),
        home: const LobsterChatPage(),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('new conversation during loading stays usable', (t) async {
    final status = Completer<http.Response>();
    apiClient = MockClient(
      (r) async =>
          r.url.path.endsWith('/status') ? status.future : ok({'sessions': []}),
    );
    await t.pumpWidget(const MaterialApp(home: LobsterChatPage()));
    await t.pump();
    await t.tap(find.byTooltip('新对话'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    status.complete(ok({'connected': true}));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '加载后可以发送');
    await t.pump();
    final send = find
        .ancestor(of: find.text('发送'), matching: find.byType(IconButton))
        .first;
    expect(t.widget<IconButton>(send).onPressed, isNotNull);
  });
  testWidgets('account change clears existing message and draft', (t) async {
    apiClient = MockClient((r) async {
      if (r.url.path.endsWith('/status')) return ok({'connected': true});
      if (r.url.path.endsWith('/sessions')) {
        return ok({
          'sessions': [
            {'id': sid},
          ],
        });
      }
      return ok({
        'messages': [
          {'role': 'assistant', 'content': 'alice-private-message'},
        ],
      });
    });
    await t.pumpWidget(const MaterialApp(home: LobsterChatPage()));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'alice-private-draft');
    await t.pump();
    await (await SharedPreferences.getInstance()).setString('token', 'bob');
    await t.tap(find.text('发送'));
    await t.pumpAndSettle();
    expect(find.text('alice-private-message'), findsNothing);
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.textContaining('已清理原账号内容'), findsOneWidget);
  });
  testWidgets(
    'history switch asks before discarding another conversation draft',
    (t) async {
      const other = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff';
      var readOther = 0;
      apiClient = MockClient((r) async {
        if (r.url.path.endsWith('/status')) return ok({'connected': true});
        if (r.url.path.endsWith('/sessions')) {
          return ok({
            'sessions': [
              {'id': sid, 'title': '会话A'},
              {'id': other, 'title': '会话B'},
            ],
          });
        }
        if (r.url.path.contains(other)) readOther++;
        return ok({'messages': []});
      });
      await t.pumpWidget(const MaterialApp(home: LobsterChatPage()));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'A的草稿');
      await t.pump();
      await t.tap(find.byTooltip('对话历史'));
      await t.pumpAndSettle();
      await t.tap(find.text('会话B'));
      await t.pumpAndSettle();
      expect(find.text('切换对话？'), findsOneWidget);
      await t.tap(find.text('继续编辑'));
      await t.pumpAndSettle();
      expect(readOther, 0);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'A的草稿',
      );
      await t.tap(find.byTooltip('对话历史'));
      await t.pumpAndSettle();
      await t.tap(find.text('会话B'));
      await t.pumpAndSettle();
      await t.tap(find.text('清空并切换'));
      await t.pumpAndSettle();
      expect(readOther, 1);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );
}
