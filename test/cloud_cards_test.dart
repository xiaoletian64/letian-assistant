import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets(
    'cloud cards control titles and unsupported platform has no fake connect action',
    (tester) async {
      SharedPreferences.setMockInitialValues({'token': 'test'});
      apiClient = MockClient(
        (r) async => http.Response(
          jsonEncode({
            'platforms': {
              'schema_version': 1,
              'cards': [
                {
                  'id': 'taobao',
                  'title': '淘宝云端名称',
                  'description': '云端说明',
                  'status': {
                    'state': 'not_implemented',
                    'logged_in': false,
                    'message': '尚未接通服务器登录',
                  },
                },
                {
                  'id': 'jd',
                  'title': '京东云端名称',
                  'refresh_action': 'refresh',
                  'status': {
                    'state': 'expired',
                    'logged_in': false,
                    'message': '已过期',
                  },
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: QrPage()));
      await tester.pumpAndSettle();
      expect(find.text('淘宝云端名称'), findsOneWidget);
      expect(find.text('京东云端名称'), findsOneWidget);
      expect(find.text('尚未接通服务器登录'), findsOneWidget);
      expect(find.text('刷新二维码'), findsOneWidget);
      expect(find.text('打开应用授权'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
