import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart' as flyer;
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'token': 'framework-test'}),
  );
  testWidgets(
    'real Flyer Chat renders markdown and copies original AI message',
    (t) async {
      const content = '## 状态\n\n**任务已完成**\n\n```dart\nprint("hello");\n```';
      apiClient = MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.path.endsWith('/status')
                ? {'connected': true}
                : r.url.path.endsWith('/sessions')
                ? {
                    'sessions': [
                      {'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'},
                    ],
                  }
                : {
                    'messages': [
                      {
                        'id': 'reply-1',
                        'role': 'assistant',
                        'content': content,
                      },
                    ],
                  },
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      String? clipboard;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = call.arguments['text'];
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await t.pumpWidget(const MaterialApp(home: LobsterChatPage()));
      await t.pumpAndSettle();
      expect(find.byType(flyer.Chat), findsOneWidget);
      expect(find.byType(FlyerChatTextMessage), findsOneWidget);
      expect(find.text('## 状态'), findsNothing);
      expect(find.text('状态', findRichText: true), findsOneWidget);
      await t.tap(find.byTooltip('复制消息'));
      await t.pumpAndSettle();
      expect(clipboard, content);
      await t.tap(find.byTooltip('复制代码'));
      await t.pumpAndSettle();
      expect(clipboard!.trim(), 'print("hello");');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'framework keeps code blocks usable on narrow large text with keyboard',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 900);
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      const content =
          '## 示例标题\n\n- 第一项\n- 第二项\n\n```python\nprint("very-long-code-line-with-a-lot-of-characters-012345678901234567890")\n```';
      apiClient = MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.path.endsWith('/status')
                ? {'connected': true}
                : r.url.path.endsWith('/sessions')
                ? {
                    'sessions': [
                      {'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'},
                    ],
                  }
                : {
                    'messages': [
                      {
                        'id': 'reply-1',
                        'role': 'assistant',
                        'content': content,
                      },
                    ],
                  },
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
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
      expect(find.byType(flyer.Chat), findsOneWidget);
      expect(find.byType(FlyerChatTextMessage), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.enterText(find.byType(TextField), '准备下一条草稿');
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  for (final action in ['new', 'history']) {
    testWidgets('typed-ahead draft is protected while waiting before $action', (
      t,
    ) async {
      var sent = false;
      apiClient = MockClient((r) async {
        Object data = {};
        if (r.url.path.endsWith('/status')) {
          data = {'connected': true};
        } else if (r.url.path.endsWith('/sessions')) {
          data = {
            'sessions': [
              {'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', 'title': '当前会话'},
              {'id': 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff', 'title': '另一个会话'},
            ],
          };
        } else if (r.method == 'POST') {
          sent = true;
          data = {
            'job': {'id': 'job-1', 'status': 'running'},
          };
        } else if (r.url.path.contains('/jobs/')) {
          data = {
            'job': {'id': 'job-1', 'status': 'running'},
          };
        } else {
          data = {
            'messages': [
              if (sent) {'id': 'm-1', 'role': 'user', 'content': '第一条消息'},
            ],
            'active_job': sent ? {'id': 'job-1', 'status': 'running'} : null,
          };
        }
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      await t.pumpWidget(const MaterialApp(home: LobsterChatPage()));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '第一条消息');
      await t.pump();
      await t.tap(find.text('发送'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.byType(TextField), '等待中写的下一条草稿');
      await t.pump();
      if (action == 'new') {
        await t.tap(find.byTooltip('新对话'));
      } else {
        await t.tap(find.byTooltip('对话历史'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.text('另一个会话'));
      }
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('继续编辑'), findsOneWidget);
      await t.tap(find.text('继续编辑'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        '等待中写的下一条草稿',
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
    });
  }
}
