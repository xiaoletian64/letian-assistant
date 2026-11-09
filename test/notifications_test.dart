import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart' as app;
import 'package:vault/notifications.dart';

void main() {
  void widgetTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  const channel = MethodChannel('site.zhangyue.vault/notifications');
  http.Response reply(Object value, [int code = 200]) => http.Response(
    jsonEncode(value),
    code,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  final snapshot = {
    'items': [
      {
        'id': 'one',
        'title': '余额提醒',
        'type': 'balance_low',
        'series_id': 'private',
        'source_time': 100,
        'read': false,
      },
    ],
    'unread': 1,
    'settings': {
      'quota': true,
      'balance': true,
      'server': true,
      'reset': true,
      'recovery': true,
    },
    'push': {'ios': 'not_configured', 'android': 'not_configured'},
  };
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'alice'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {
            'authorization': 'denied',
            'background_available': false,
          },
        );
    app.apiClient = MockClient((r) async => reply(snapshot));
  });
  widgetTest('permission and unconfigured channel remain explicit', (t) async {
    await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await t.pumpAndSettle();
    expect(find.textContaining('系统通知权限未开启'), findsOneWidget);
    expect(find.textContaining('推送通道尚未配置'), findsOneWidget);
    await t.scrollUntilVisible(find.text('余额提醒'), 300);
    expect(find.text('余额提醒'), findsOneWidget);
  });
  widgetTest('daily report body is readable at large text scale', (t) async {
    final report = Map<String, dynamic>.from(snapshot);
    report['items'] = [
      {
        'id': 'daily',
        'title': '乐天早报',
        'body': '昨日消费总额未知\n114：未获取官方昨日账单',
        'type': 'daily_digest',
        'read': false,
      },
    ];
    app.apiClient = MockClient((r) async => reply(report));
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const NotificationsPage(),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('乐天早报'), 300);
    expect(find.byType(SelectableText), findsNothing);
    await t.tap(find.text('乐天早报'));
    await t.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('114：未获取'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  widgetTest('read failure does not mark read', (t) async {
    app.apiClient = MockClient(
      (r) async => r.method == 'GET' ? reply(snapshot) : reply({}, 503),
    );
    await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('余额提醒'), 300);
    await t.tap(find.text('余额提醒'));
    await t.pumpAndSettle();
    expect(find.textContaining('服务暂时无法连接'), findsOneWidget);
    expect(find.text('标为已读'), findsOneWidget);
  });
  widgetTest('settings failure keeps old setting', (t) async {
    app.apiClient = MockClient(
      (r) async => r.method == 'GET' ? reply(snapshot) : reply({}, 503),
    );
    await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('低额度'), 300);
    await t.tap(find.text('低额度'));
    await t.pumpAndSettle();
    expect(find.textContaining('服务暂时无法连接'), findsOneWidget);
    expect(
      t
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '低额度'))
          .value,
      isTrue,
    );
  });
  widgetTest('account change discards completed response', (t) async {
    app.apiClient = MockClient((r) async {
      final p = await SharedPreferences.getInstance();
      await p.setString('token', 'bob');
      return reply(snapshot);
    });
    await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await t.pumpAndSettle();
    expect(find.text('余额提醒'), findsNothing);
    expect(find.textContaining('账号已变化'), findsOneWidget);
  });
  test('clear binding uses previous account credential', () async {
    String? auth;
    String? method;
    app.apiClient = MockClient((r) async {
      auth = r.headers['Authorization'];
      method = r.method;
      return reply({});
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'notification_installation_${Uri.parse(app.baseUrl).origin}',
      'existing',
    );
    await prefs.setBool(
      'notification_bound_${Uri.parse(app.baseUrl).origin}',
      true,
    );
    await clearNotificationBinding(bearerToken: 'previous');
    expect(auth, 'Bearer previous');
    expect(method, 'DELETE');
  });
  widgetTest('missing native plugin reports unsupported', (t) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw MissingPluginException(),
        );
    await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await t.pumpAndSettle();
    expect(find.textContaining('尚不支持系统通知权限通道'), findsOneWidget);
    expect(find.text('开启系统通知'), findsNothing);
  });
  widgetTest('permission is requested only after explicit button tap', (
    t,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return {
            'authorization': 'notDetermined',
            'background_available': false,
          };
        });
    await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await t.pumpAndSettle();
    expect(calls, ['status']);
    await t.tap(find.text('开启系统通知'));
    await t.pumpAndSettle();
    expect(calls, ['status', 'requestPermission']);
  });
  widgetTest('forbidden refresh clears old records', (t) async {
    var forbidden = false;
    app.apiClient = MockClient(
      (r) async => forbidden ? reply({}, 403) : reply(snapshot),
    );
    await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await t.pumpAndSettle();
    forbidden = true;
    await t.tap(find.byTooltip('刷新'));
    await t.pumpAndSettle();
    expect(find.textContaining('当前账号无权访问'), findsOneWidget);
    await t.scrollUntilVisible(find.textContaining('0条未读'), 200);
    expect(find.textContaining('0条未读'), findsOneWidget);
  });
  widgetTest('token rotation reuses random installation id', (t) async {
    var deviceToken = 'first';
    final registrations = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'authorization': 'authorized',
            'background_available': true,
            'token': deviceToken,
          },
        );
    app.apiClient = MockClient((r) async {
      if (r.method == 'POST') {
        registrations.add(jsonDecode(r.body) as Map<String, dynamic>);
        return reply({});
      }
      return reply(snapshot);
    });
    await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await t.pumpAndSettle();
    deviceToken = 'second';
    await t.tap(find.byTooltip('刷新'));
    await t.pumpAndSettle();
    expect(registrations.length, 2);
    expect(
      registrations[0]['installation_id'],
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );
    expect(
      registrations[1]['installation_id'],
      registrations[0]['installation_id'],
    );
    expect(registrations[1]['token'], 'second');
  });
  test('logout without binding only clears native state', () async {
    final calls = <String>[];
    var requests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c.method);
          return null;
        });
    app.apiClient = MockClient((_) async {
      requests++;
      return reply({});
    });
    await clearNotificationBinding();
    expect(requests, 0);
    expect(calls, ['clearBindings']);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(
        'notification_installation_${Uri.parse(app.baseUrl).origin}',
      ),
      isNull,
    );
  });
  test('server unbind failure still clears native state and throws', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'notification_installation_${Uri.parse(app.baseUrl).origin}',
      'existing',
    );
    await prefs.setBool(
      'notification_bound_${Uri.parse(app.baseUrl).origin}',
      true,
    );
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c.method);
          return null;
        });
    app.apiClient = MockClient((_) async => reply({}, 503));
    await expectLater(clearNotificationBinding(), throwsException);
    expect(calls, ['clearBindings']);
  });
  test('sync does not request permission or register without token', () async {
    final calls = <String>[];
    var requests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c.method);
          return {'authorization': 'authorized'};
        });
    app.apiClient = MockClient((_) async {
      requests++;
      return reply({});
    });
    await syncNotificationBinding();
    expect(calls, ['status']);
    expect(requests, 0);
  });
  test('pending notification only returns safe event id', () async {
    var value = 'safe-event_123';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => value);
    expect(await consumeNotificationOpenEvent(), 'safe-event_123');
    value = 'https://malicious.invalid';
    expect(await consumeNotificationOpenEvent(), isNull);
  });
  widgetTest('native tokenChanged registers newly available token', (t) async {
    String? nativeToken;
    final registered = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'authorization': 'authorized', 'token': nativeToken},
        );
    app.apiClient = MockClient((r) async {
      if (r.method == 'POST') {
        registered.add((jsonDecode(r.body) as Map)['token'] as String);
        return reply({});
      }
      return reply(snapshot);
    });
    await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await t.pumpAndSettle();
    expect(registered, isEmpty);
    nativeToken = 'late-apns-token';
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('tokenChanged'),
      ),
      (_) {},
    );
    await t.pumpAndSettle();
    expect(registered, ['late-apns-token']);
  });
  test(
    'account change during native status never registers old token',
    () async {
      var requests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('token', 'bob');
            return {
              'authorization': 'authorized',
              'token': 'old-account-device-token',
            };
          });
      app.apiClient = MockClient((_) async {
        requests++;
        return reply({});
      });
      await syncNotificationBinding();
      expect(requests, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('notification_bound_${Uri.parse(app.baseUrl).origin}'),
        isNull,
      );
    },
  );
  widgetTest('Android ordinary monitor starts and stops without vendor push', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    var running = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c.method);
          if (c.method == 'startMonitor') {
            expect((c.arguments as Map)['bearer'], 'alice');
            running = true;
          }
          if (c.method == 'stopMonitor') running = false;
          return {
            'authorization': 'authorized',
            'mode': 'foreground_monitor',
            'monitor_running': running,
            'background_available': running,
          };
        });
    await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await t.pumpAndSettle();
    expect(calls, ['status']);
    expect(find.textContaining('推送通道尚未配置'), findsNothing);
    await t.tap(find.text('开启监测'));
    await t.pumpAndSettle();
    expect(calls, contains('startMonitor'));
    expect(find.text('停止监测'), findsOneWidget);
    await t.tap(find.text('停止监测'));
    await t.pumpAndSettle();
    expect(calls, contains('stopMonitor'));
    expect(find.text('开启监测'), findsOneWidget);
  });
  widgetTest('Android denied permission never starts monitor', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c.method);
          return {
            'authorization': c.method == 'status' ? 'notDetermined' : 'denied',
            'mode': 'foreground_monitor',
            'monitor_running': false,
          };
        });
    await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await t.pumpAndSettle();
    await t.tap(find.text('开启监测'));
    await t.pumpAndSettle();
    expect(calls, ['status', 'requestPermission']);
    expect(find.text('打开系统设置'), findsOneWidget);
  });
  test(
    'Android sync never starts stopped service or registers device',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            calls.add(c.method);
            return {
              'authorization': 'authorized',
              'mode': 'foreground_monitor',
              'monitor_running': false,
              'token': 'unused',
            };
          });
      app.apiClient = MockClient(
        (_) async => throw StateError('Android must not register devices'),
      );
      await syncNotificationBinding();
      expect(calls, ['status']);
      await clearNotificationBinding();
      expect(calls.last, 'clearBindings');
    },
  );
  widgetTest(
    'Android first enable requests permission then starts and account switch clears service',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <String>[];
      var authorized = false;
      var running = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            calls.add(c.method);
            if (c.method == 'requestPermission') authorized = true;
            if (c.method == 'startMonitor') running = true;
            if (c.method == 'clearBindings') running = false;
            return {
              'authorization': authorized ? 'authorized' : 'notDetermined',
              'mode': 'foreground_monitor',
              'monitor_running': running,
              'background_available': running,
            };
          });
      await t.pumpWidget(const MaterialApp(home: NotificationsPage()));
      await t.pumpAndSettle();
      await t.tap(find.text('开启监测'));
      await t.pumpAndSettle();
      expect(calls, ['status', 'requestPermission', 'startMonitor', 'status']);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', 'bob');
      await syncNotificationBinding();
      expect(calls.last, 'clearBindings');
      expect(running, isFalse);
      expect(calls.where((c) => c == 'startMonitor').length, 1);
    },
  );
}
