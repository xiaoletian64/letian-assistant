import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

const streamSession = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const streamJob = '11111111-2222-3333-4444-555555555555';

class StreamingClient extends http.BaseClient {
  final streams = <StreamController<List<int>>>[];
  final cursors = <String>[];
  final requests = <String>[];
  int generations = 0, cancels = 0, seq = 0, eventStatus = 200;
  String partial = '', state = 'running';
  bool requested = false, hasSessions = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    requests.add('${request.method} $path');
    if (path.endsWith('/events')) {
      cursors.add(request.url.queryParameters['after']!);
      if (eventStatus != 200) {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{}')),
          eventStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      final stream = StreamController<List<int>>();
      streams.add(stream);
      return http.StreamedResponse(
        stream.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    Object body = {};
    if (path.endsWith('/status')) {
      body = {'connected': true};
    } else if (path.endsWith('/sessions')) {
      if (request.method == 'POST') {
        hasSessions = true;
        body = {
          'session': {'id': streamSession},
        };
      } else {
        body = {
          'sessions': [
            if (hasSessions) {'id': streamSession, 'title': '真实上下文'},
          ],
        };
      }
    } else if (path.endsWith('/cancel')) {
      cancels++;
      requested = true;
      body = {
        'job': {
          'id': streamJob,
          'status': state,
          'cancel_requested': requested,
        },
      };
    } else if (path.contains('/jobs/')) {
      body = {
        'job': {
          'id': streamJob,
          'status': state,
          'partial_content': partial,
          'last_event_id': seq,
          'cancel_requested': requested,
          'assistant_message_id': 'job-$streamJob',
        },
      };
    } else if (path.endsWith('/messages')) {
      if (request.method == 'POST') {
        generations++;
        body = {
          'job': {'id': streamJob, 'status': 'queued'},
        };
      } else {
        body = {
          if (generations > 0 && ['queued', 'running'].contains(state))
            'active_job': {'id': streamJob, 'status': state},
          'messages': [
            if (generations > 0) {'id': 'u', 'role': 'user', 'content': '开始'},
            if (partial.isNotEmpty)
              {
                'id': 'job-$streamJob',
                'job_id': streamJob,
                'role': 'assistant',
                'content': partial,
                'status': state,
              },
          ],
        };
      }
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  void delta(int next, String text, String content) {
    seq = next;
    partial = content;
    streams.last.add(
      utf8.encode(
        'id: $next\nevent: delta\ndata: ${jsonEncode({'job_id': streamJob, 'seq': next, 'text': text, 'content': content})}\n\n',
      ),
    );
  }

  void terminal(int next, String status) {
    seq = next;
    state = status;
    streams.last.add(
      utf8.encode(
        'id: $next\nevent: state\ndata: ${jsonEncode({'job_id': streamJob, 'seq': next, 'status': status})}\n\n',
      ),
    );
  }
}

Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

Future<StreamingClient> begin(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({'token': 'stream-owner'});
  final client = StreamingClient();
  apiClient = client;
  await t.pumpWidget(const MaterialApp(home: LobsterChatPage()));
  await flush(t);
  await t.enterText(find.byType(TextField), '开始');
  await flush(t);
  await t.tap(find.text('发送'));
  await flush(t);
  expect(
    client.streams.length,
    1,
    reason:
        '${client.requests} ${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList()}',
  );
  return client;
}

List<String> assistantTexts(WidgetTester t) => t
    .widgetList<FlyerChatTextMessage>(find.byType(FlyerChatTextMessage))
    .where((w) => w.message.authorId == 'lobster')
    .map((w) => w.message.text)
    .toList();
void main() {
  for (final status in [401, 403]) {
    testWidgets(
      'events $status clears private partial and draft without retry or unhandled auth error',
      (t) async {
        final c = await begin(t);
        c.delta(4, '私有回复', '私有回复');
        await flush(t);
        await t.enterText(find.byType(TextField), '私有新草稿');
        c.eventStatus = status;
        await t.runAsync(() async {
          await c.streams.last.close();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await flush(t);
        await t.pump(const Duration(seconds: 3));
        await flush(t);
        expect(assistantTexts(t), isEmpty);
        expect(
          t.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        final attempts = c.cursors.length;
        await t.pump(const Duration(seconds: 10));
        await flush(t);
        expect(c.cursors.length, attempts);
        expect(c.generations, 1);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'reopening restores authoritative partial and cursor before subscribing',
    (t) async {
      final c = await begin(t);
      c.delta(7, '离页前片段', '离页前片段');
      await flush(t);
      await t.pumpWidget(const SizedBox());
      await flush(t);
      expect(c.streams.first.hasListener, isFalse);
      c.seq = 12;
      c.partial = '离页前片段＋离页后真实内容';
      await t.pumpWidget(const MaterialApp(home: LobsterChatPage()));
      await flush(t);
      expect(c.cursors, ['0', '12']);
      expect(assistantTexts(t), ['离页前片段＋离页后真实内容']);
      c.delta(16, '续接', '离页前片段＋离页后真实内容续接');
      await flush(t);
      expect(assistantTexts(t), ['离页前片段＋离页后真实内容续接']);
      expect(c.generations, 1);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'true stream updates same message through half Markdown, stop preserves partial and typed ahead',
    (t) async {
      final c = await begin(t);
      c.delta(3, '半截```dart\n', '半截```dart\n');
      await flush(t);
      expect(assistantTexts(t), ['半截```dart\n']);
      c.delta(6, 'print(', '半截```dart\nprint(');
      await flush(t);
      expect(assistantTexts(t), ['半截```dart\nprint(']);
      await t.enterText(find.byType(TextField), '下一条草稿');
      await t.tap(find.text('停止回复'));
      await flush(t);
      expect(c.cancels, 1);
      expect(find.text('停止请求中'), findsOneWidget);
      expect(assistantTexts(t), ['半截```dart\nprint(']);
      c.terminal(9, 'cancelled');
      await flush(t);
      expect(assistantTexts(t), ['半截```dart\nprint(']);
      expect(find.text('已停止'), findsWidgets);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        '下一条草稿',
      );
      expect(c.generations, 1);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'disconnect resumes opaque last sequence without another generation and completion reconciles',
    (t) async {
      final c = await begin(t);
      c.delta(3, '第一段', '第一段');
      await flush(t);
      await t.runAsync(() async {
        await c.streams.last.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await flush(t);
      await t.pump(const Duration(seconds: 3));
      await flush(t);
      expect(
        c.cursors,
        ['0', '3'],
        reason:
            '${c.requests} ${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList()}',
      );
      c.delta(3, '第一段', '第一段');
      await flush(t);
      c.delta(11, '尾段', '第一段补齐尾段');
      await flush(t);
      expect(assistantTexts(t), ['第一段补齐尾段']);
      c.terminal(15, 'completed');
      await flush(t);
      expect(assistantTexts(t), ['第一段补齐尾段']);
      expect(c.generations, 1);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account change closes old subscription and clears existing partial plus draft',
    (t) async {
      final c = await begin(t);
      c.delta(2, '私有片段', '私有片段');
      await flush(t);
      await t.enterText(find.byType(TextField), '私有草稿');
      await (await SharedPreferences.getInstance()).setString(
        'token',
        'other-owner',
      );
      c.delta(4, '迟到', '私有片段迟到');
      await flush(t);
      expect(assistantTexts(t), isEmpty);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(c.streams.last.hasListener, isFalse);
      expect(c.generations, 1);
      await t.pumpWidget(const SizedBox());
    },
  );
}
