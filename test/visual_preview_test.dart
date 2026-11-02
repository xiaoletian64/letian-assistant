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
  testWidgets('render phone and tablet dashboard previews', (tester) async {
    final font = File(
      '/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc',
    );
    if (!font.existsSync()) return;
    final loader = FontLoader('PreviewCJK')
      ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '/opt/flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
    await loadBundledPluginCatalog();
    SharedPreferences.setMockInitialValues({'token': 'preview'});
    final catalog = await loadBundledPluginCatalog();
    apiClient = MockClient(
      (r) async => http.Response(
        jsonEncode(r.url.path == '/api/me' ? {'username': 'preview'} : catalog),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    final boundary = GlobalKey();
    for (final wide in [false, true]) {
      tester.view.physicalSize = wide
          ? const Size(1200, 900)
          : const Size(390, 844);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'PreviewCJK',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2563EB),
            ),
            scaffoldBackgroundColor: const Color(0xFFF5F7FB),
            cardTheme: ThemeData().cardTheme.copyWith(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF5F7FB),
              scrolledUnderElevation: 0,
            ),
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
            ),
          ),
          home: RepaintBoundary(key: boundary, child: const HomePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(boundary),
        matchesGoldenFile(
          'previews/dashboard-${wide ? 'tablet' : 'phone'}.png',
        ),
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
}
