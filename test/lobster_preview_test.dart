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
  testWidgets('preview chat and aligned GitHub Cursor using labeled sample data', (
    t,
  ) async {
    final font = File('/System/Library/Fonts/STHeiti Light.ttc');
    if (!font.existsSync()) return;
    await (FontLoader('PreviewCJK')
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync()))))
        .load();
    final icons = File(
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
    final mono = File('/System/Library/Fonts/Menlo.ttc');
    if (mono.existsSync()) {
      await (FontLoader('monospace')..addFont(
            Future.value(ByteData.sublistView(mono.readAsBytesSync())),
          ))
          .load();
    }
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'token': 'preview-only'});
    apiClient = MockClient(
      (r) async => http.Response(
        jsonEncode(
          r.url.path.endsWith('/status')
              ? {'connected': true}
              : r.url.path.endsWith('/sessions')
              ? {
                  'sessions': [
                    {
                      'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
                      'title': '界面示例',
                    },
                  ],
                }
              : {
                  'messages': [
                    {'role': 'user', 'content': '[界面示例] 你好，龙虾。'},
                    {
                      'role': 'assistant',
                      'content':
                          '## 框架界面示例\n\n**龙虾对话已接通。** 支持 Markdown、代码块与复制。\n\n```python\nprint("hello, lobster")\n```',
                    },
                  ],
                },
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'PreviewCJK',
          scaffoldBackgroundColor: const Color(0xFFF0F6FF),
          colorScheme: ColorScheme.fromSeed(seedColor: sceneBlue),
        ),
        home: RepaintBoundary(key: key, child: const LobsterChatPage()),
      ),
    );
    await t.pumpAndSettle();
    if (const bool.fromEnvironment('SCENE_PREVIEW')) {
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('previews/lobster-chat.png'),
      );
    }
    final accounts = quotaAccounts({
      'collected_at': '2026-10-26T16:00:00+08:00',
      'accounts': {
        'cursor': {
          'name': '个人账号（示例）',
          'total_percent': 25,
          'auto_percent': 12,
          'api_percent': 80,
          'cycle_end': '2026-11-01T00:00:00+08:00',
        },
      },
      'push': {
        'gha': {
          'updated': '2026-10-26T16:00:00+08:00',
          'personal': {'included': 2000, 'left': 1206},
          'org': {'included': 2000, 'left': 32},
          'note': '每月1日重置（示例）',
        },
      },
    });
    final quotaKey = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, fontFamily: 'PreviewCJK'),
        home: RepaintBoundary(
          key: quotaKey,
          child: Scaffold(
            backgroundColor: const Color(0xFFF0F6FF),
            appBar: AppBar(title: const Text('额度格式 · 示例数据')),
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final a in accounts) QuotaAccountCard(account: a),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.runAsync(() async {
      for (final f in ['cursor', 'github']) {
        await precacheImage(
          AssetImage('assets/images/$f.png'),
          t.element(find.byType(Scaffold)),
        );
      }
    });
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    if (const bool.fromEnvironment('SCENE_PREVIEW')) {
      await expectLater(
        find.byKey(quotaKey),
        matchesGoldenFile('previews/github-cursor.png'),
      );
    }
  });
}
