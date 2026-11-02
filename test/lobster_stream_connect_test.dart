import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';
import 'lobster_stream_widget_test.dart' show StreamingClient, flush;

/// Deliberately ignores cancellation and returns headers late. The adapter must
/// still release a late response even if a third-party Client ignores Abortable.
class DeferredHeadersClient extends StreamingClient {
  final headers = Completer<http.StreamedResponse>();
  bool bodyCancelled = false;
  late final body = StreamController<List<int>>(
    onCancel: () {
      bodyCancelled = true;
    },
  );
  bool aborted = false;
  http.BaseRequest? pendingRequest;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('/events')) return super.send(request);
    pendingRequest = request;
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) => aborted = true);
    }
    return headers.future;
  }

  void finishHeaders() => headers.complete(
    http.StreamedResponse(
      body.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    ),
  );
}

Future<DeferredHeadersClient> establish(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({'token': 'stream-owner'});
  final c = DeferredHeadersClient();
  apiClient = c;
  await t.pumpWidget(const MaterialApp(home: LobsterChatPage()));
  await flush(t);
  await t.enterText(find.byType(TextField), '开始');
  await flush(t);
  await t.tap(find.text('发送'));
  await flush(t);
  expect(c.pendingRequest, isNotNull);
  return c;
}

void main() {
  for (final action in ['dispose', 'account', 'timeout']) {
    testWidgets(
      'establishing SSE $action aborts request and cancels ignored late response',
      (t) async {
        final c = await establish(t);
        expect(c.pendingRequest, isA<http.AbortableRequest>());
        if (action == 'dispose') {
          await t.pumpWidget(const SizedBox());
        } else if (action == 'account') {
          await t.enterText(find.byType(TextField), '私有待发草稿');
          await (await SharedPreferences.getInstance()).setString(
            'token',
            'other-owner',
          );
          await t.pump(const Duration(seconds: 2));
        } else {
          await t.pump(const Duration(seconds: 31));
        }
        await flush(t);
        expect(c.aborted, isTrue);
        if (action == 'account') {
          expect(
            t.widget<TextField>(find.byType(TextField)).controller!.text,
            isEmpty,
          );
        }
        c.finishHeaders();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await flush(t);
        expect(c.body.hasListener, isFalse);
        expect(c.bodyCancelled, isTrue);
        expect(c.generations, 1);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.runAsync(
          () => c.body.close().timeout(const Duration(seconds: 1)),
        );
      },
    );
  }
}
