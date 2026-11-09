import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';
import 'package:vault/notifications.dart';

void main() {
  testWidgets('integrated cards start collapsed and reports remain readable', (
    t,
  ) async {
    final font = File('/System/Library/Fonts/STHeiti Light.ttc');
    if (font.existsSync()) {
      await (FontLoader('PreviewCJK')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
    }
    final icons = File(
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'PreviewCJK',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
          scaffoldBackgroundColor: const Color(0xFFF0F6FF),
        ),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            appBar: AppBar(title: const Text('乐天助手 · 综合卡片')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '交互预览 · 合成数据',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                ...quotaPlatformCards(
                  quotaAccounts({
                    'collected_at': DateTime.now().toUtc().toIso8601String(),
                    'accounts': {
                      'zhipu': {
                        'five_hour': {'percent': 30},
                        'weekly': {'percent': 50},
                      },
                    },
                  }),
                ),
                const CollapsibleContentCard(
                  item: {
                    'title': '昨日消费',
                    'subtitle': '支付时间不完整 · 总额未知',
                    'body': '只统计来源明确的支付时间和实付。缺失金额不会填零；退款未核验时不计算净支出。',
                  },
                ),
                const CollapsibleContentCard(
                  item: {
                    'type': 'order',
                    'title': '最近订单 · 示例商品',
                    'subtitle': '待发货 · 物流及到货时间未获取',
                    'body': '来源尚未返回物流详情和预计到货时间，请以平台最新状态为准。',
                    'products': [
                      {'title': '示例商品', 'image_url': null},
                    ],
                  },
                ),
                NotificationDigestCard(
                  item: const {
                    'title': '乐天早报 · 11-09',
                    'read': false,
                    'source_time': 1794187800,
                    'body':
                        'AI 剩余额度\n各账号独立显示，过期数据明确提示。\n订阅额度与账户余额不等于实际费用。\n\n昨日购物消费\n缺少支付时间，昨日总额未知。\n\n昨日服务器费用\n106：官方账单未获取\n124：官方账单未获取\n114：官方账单未获取\n\n每天北京时间09:30生成，缺失不填零。',
                  },
                  onRead: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('暂无商品图'), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    if (const bool.fromEnvironment('CLIENT_PREVIEW')) {
      await expectLater(
        find.byKey(key),
        matchesGoldenFile(
          '../../private-diagnostics/letian-morning-20261109/client-collapsed.png',
        ),
      );
    }
    await t.tap(find.text('乐天早报 · 11-09'));
    await t.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(t.takeException(), isNull);
    if (const bool.fromEnvironment('CLIENT_PREVIEW')) {
      await expectLater(
        find.byKey(key),
        matchesGoldenFile(
          '../../private-diagnostics/letian-morning-20261109/client-morning.png',
        ),
      );
    }
  });
}
