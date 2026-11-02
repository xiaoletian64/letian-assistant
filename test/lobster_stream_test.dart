import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  test(
    'real byte chunks preserve partial UTF8 Markdown and only complete SSE frames',
    () async {
      final source = StreamController<List<int>>();
      final received = <LobsterSseEvent>[];
      final done = lobsterSseEvents(
        source.stream,
      ).listen(received.add).asFuture<void>();
      final bytes = utf8.encode(
        'id: 1\nevent: delta\ndata: {"job_id":"j","seq":1,"text":"你```da","content":"你```da"}\n\n',
      );
      source.add(bytes.sublist(0, 62));
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      source.add(bytes.sublist(62));
      await source.close();
      await done;
      expect(received.single.data['content'], '你```da');
    },
  );
  test(
    'opaque monotonic cursor deduplicates replay and accepts authority projection',
    () {
      final state = LobsterStreamSnapshot('j');
      LobsterSseEvent event(int seq, String text, String content) =>
          LobsterSseEvent(seq, 'delta', {
            'job_id': 'j',
            'seq': seq,
            'text': text,
            'content': content,
          });
      expect(state.apply(event(1, '## ', '## ')), isTrue);
      expect(state.apply(event(1, '## ', '## ')), isFalse);
      expect(state.apply(event(3, 'x', '## x')), isTrue);
      expect(state.content, '## x');
      expect(state.apply(event(5, '标题', '## x 标题')), isTrue);
      expect(
        () => state.apply(event(6, 'x', 'changed')),
        throwsFormatException,
      );
      expect(state.seq, 5);
      expect(state.content, '## x 标题');
      state.apply(
        const LobsterSseEvent(7, 'delta', {
          'job_id': 'j',
          'seq': 7,
          'text': '官方',
          'content': '官方',
          'replace': true,
        }),
      );
      expect(state.content, '官方');
    },
  );
  test('cancel acknowledgement never discards partial output', () {
    final state = LobsterStreamSnapshot(
      'j',
      seq: 4,
      content: '```dart\nprint(',
    );
    state.apply(
      const LobsterSseEvent(5, 'state', {
        'job_id': 'j',
        'seq': 5,
        'status': 'cancelled',
      }),
    );
    expect(state.status, 'cancelled');
    expect(state.content, '```dart\nprint(');
    expect(state.terminal, isTrue);
  });
}
