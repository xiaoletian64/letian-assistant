import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:vault/main.dart' as app;

void main() {
  testWidgets('unconfigured public build makes no deployment requests', (
    t,
  ) async {
    var calls = 0;
    app.apiClient = MockClient((_) async {
      calls++;
      throw StateError('network forbidden');
    });
    app.otaClient = MockClient((_) async {
      calls++;
      throw StateError('network forbidden');
    });
    await app.main();
    await t.pumpAndSettle();
    expect(find.text('尚未配置服务'), findsOneWidget);
    expect(calls, 0);
    await t.pumpWidget(const SizedBox());
  });
}
