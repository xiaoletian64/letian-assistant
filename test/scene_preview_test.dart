import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets('render implemented scene home phone large text and tablet', (
    t,
  ) async {
    final fonts = [
      '/System/Library/Fonts/STHeiti Light.ttc',
      '/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc',
    ];
    final font = fonts.map(File.new).where((f) => f.existsSync()).firstOrNull;
    if (font == null) return;
    await (FontLoader('PreviewCJK')
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync()))))
        .load();
    final iconFiles = [
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      '/opt/flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ];
    final iconFile = iconFiles.map(File.new).where((f) => f.existsSync()).first;
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(ByteData.sublistView(iconFile.readAsBytesSync())),
        ))
        .load();
    SharedPreferences.setMockInitialValues({'token': 'preview-only'});
    final now = DateTime.utc(2026, 10, 26, 6, 35);
    final catalog = await loadBundledPluginCatalog();
    apiClient = MockClient((r) async {
      final result = switch (r.url.path) {
        '/api/me' => {'username': '乐天 · 预览示例'},
        '/api/hub/plugins' => catalog,
        '/api/hub/vehicles' => {
          'vehicles': [
            {
              'brand': '九号',
              'name': '通勤车',
              'battery': 76,
              'charging': 1,
              'state': '关机停着',
              'fresh': true,
              'report_ms': now.millisecondsSinceEpoch,
              'location_ms': now.millisecondsSinceEpoch,
              'address': '小区地下车库（示例）',
              'service_name': '智能服务',
              'service_remaining_days': 3,
            },
          ],
        },
        '/api/quota/summary' => {
          'collected_at': now.toUtc().toIso8601String(),
          'accounts': {
            'zhipu': {
              'five_hour': {'percent': 88},
              'weekly': {'percent': 26},
            },
            'opencode': {
              'rolling': {'percent': 40},
              'weekly': {'percent': 55},
              'monthly': {'percent': 28},
            },
            'deepseek': {'amount': 8.5, 'currency': 'CNY'},
          },
          'push': {
            'codex': {
              'accounts': [
                {
                  'n': '主账号（示例）',
                  'ts': now.millisecondsSinceEpoch / 1000,
                  'fh': {'u': 32, 'window_seconds': 604800},
                },
                {
                  'n': '备用账号（示例）',
                  'fh': {'u': 58, 'window_seconds': 604800},
                },
              ],
            },
            'mimo': {
              'accounts': [
                {'n': '个人账号（示例）', 'rem': '（82%）'},
              ],
            },
          },
        },
        '/api/hub/sessions' => {
          'sessions': [
            {
              'id': '00000000-0000-0000-0000-000000000000',
              'title': '手机控制方案（示例）',
              'last_active': '今天14:18',
            },
          ],
        },
        '/api/qr/all' => {
          'douyin': {'logged_in': true},
          'dianping': {'logged_in': false},
        },
        _ => <String, dynamic>{},
      };
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.view.devicePixelRatio = 1;
    for (final spec in [
      (390.0, 844.0, 1.0, 'phone'),
      (390.0, 2400.0, 1.0, 'full-page'),
      (320.0, 900.0, 1.8, 'large-text'),
      (1000.0, 900.0, 1.0, 'tablet'),
    ]) {
      t.view.physicalSize = Size(spec.$1, spec.$2);
      final boundary = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'PreviewCJK',
            colorScheme: ColorScheme.fromSeed(seedColor: sceneBlue),
            scaffoldBackgroundColor: const Color(0xFFF0F6FF),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF0F6FF),
              scrolledUnderElevation: 0,
            ),
            navigationBarTheme: const NavigationBarThemeData(
              backgroundColor: Colors.white,
              indicatorColor: Color(0xFFDCEBFF),
            ),
          ),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(spec.$3)),
            child: child!,
          ),
          home: RepaintBoundary(key: boundary, child: const SceneShell()),
        ),
      );
      await t.pumpAndSettle();
      await t.runAsync(() async {
        for (final name in [
          'avatar',
          'commuter-scooter',
          'openai',
          'glm',
          'opencode',
          'deepseek',
          'mimo',
        ]) {
          await precacheImage(
            AssetImage('assets/images/$name.png'),
            t.element(find.byType(SceneShell)),
          );
        }
      });
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (const bool.fromEnvironment('SCENE_PREVIEW')) {
        await expectLater(
          find.byKey(boundary),
          matchesGoldenFile('previews/scene-${spec.$4}.png'),
        );
      }
      if (spec.$4 == 'phone') {
        await t.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -650),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (const bool.fromEnvironment('SCENE_PREVIEW')) {
          await expectLater(
            find.byKey(boundary),
            matchesGoldenFile('previews/scene-quota.png'),
          );
        }
        await t.tap(find.text('我的').last);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (const bool.fromEnvironment('SCENE_PREVIEW')) {
          await expectLater(
            find.byKey(boundary),
            matchesGoldenFile('previews/scene-account.png'),
          );
        }
      }
      await t.pumpWidget(const SizedBox());
    }
  });
}
