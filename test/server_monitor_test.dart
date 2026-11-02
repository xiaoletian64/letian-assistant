import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  test('non-overlap and account switch discard old response', () async {
    final pending = Completer<Map<String, dynamic>>();
    var count = 0;
    final controller = ServerMonitorController(
      fetch: () {
        count++;
        return pending.future;
      },
    );
    controller.setAccount('one');
    final first = controller.refresh();
    await controller.refresh();
    expect(count, 1);
    controller.setAccount('two');
    pending.complete({
      'servers': [
        {'id': 'old'},
      ],
    });
    await first;
    expect(controller.data, isNull);
    controller.dispose();
  });
  test('failed refresh retains data and stale status', () async {
    final next = ServerMonitorController(fetch: () async => {'servers': []});
    next.setAccount('one');
    await next.refresh();
    expect(next.data, isNotNull);
    next.fetch = () async => throw Exception('private details');
    await next.refresh();
    expect(next.data, isNotNull);
    expect(next.failed, isTrue);
    next.dispose();
  });
}
