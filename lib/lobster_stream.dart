part of 'main.dart';

/// SSE transport framing, independent of model generation and widget timing.
class LobsterSseEvent {
  const LobsterSseEvent(this.seq, this.event, this.data);
  final int seq;
  final String event;
  final Map<String, dynamic> data;
}

Stream<LobsterSseEvent> lobsterSseEvents(Stream<List<int>> bytes) {
  String? id;
  var type = 'message';
  final data = <String>[];
  return bytes
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .transform(
        StreamTransformer<String, LobsterSseEvent>.fromHandlers(
          handleData: (line, sink) {
            if (line.isEmpty) {
              try {
                if (data.isNotEmpty && ['delta', 'state'].contains(type)) {
                  final body = sceneMap(jsonDecode(data.join('\n')));
                  final seq = int.tryParse(id ?? '');
                  if (seq == null || seq < 1 || body['seq'] != seq) {
                    throw const FormatException('流式事件编号不一致');
                  }
                  sink.add(LobsterSseEvent(seq, type, body));
                }
              } catch (e, stack) {
                sink.addError(e, stack);
              }
              id = null;
              type = 'message';
              data.clear();
              return;
            }
            if (line.startsWith(':')) return;
            final colon = line.indexOf(':');
            final field = colon < 0 ? line : line.substring(0, colon);
            var value = colon < 0 ? '' : line.substring(colon + 1);
            if (value.startsWith(' ')) value = value.substring(1);
            switch (field) {
              case 'id':
                id = value;
              case 'event':
                type = value;
              case 'data':
                data.add(value);
            }
          },
        ),
      );
  // A disconnected partial frame is never committed. The standard synchronous
  // transforms also propagate cancellation directly to the HTTP subscription.
}

class LobsterStreamSnapshot {
  LobsterStreamSnapshot(
    this.jobId, {
    this.seq = 0,
    this.content = '',
    this.status = 'queued',
  });
  final String jobId;
  int seq;
  String content, status;
  bool get terminal => const [
    'completed',
    'failed',
    'interrupted',
    'cancelled',
  ].contains(status);
  bool apply(LobsterSseEvent event) {
    if (event.data['job_id'] != jobId) throw const FormatException('流式任务不匹配');
    if (event.seq <= seq) return false;
    if (event.event == 'delta') {
      final next = event.data['content'], delta = event.data['text'];
      if (next is! String ||
          delta is! String ||
          (event.data['replace'] != true && !next.startsWith(content))) {
        throw const FormatException('流式内容不连续，正在校对');
      }
      content = next;
      status = 'running';
    } else if (event.event == 'state') {
      final next = event.data['status'];
      if (!const [
        'queued',
        'running',
        'completed',
        'failed',
        'interrupted',
        'cancelled',
      ].contains(next)) {
        throw const FormatException('流式任务状态异常');
      }
      status = '$next';
    }
    seq = event.seq;
    return true;
  }
}
