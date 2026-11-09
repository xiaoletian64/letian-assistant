import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  final now = DateTime.now().toUtc().toIso8601String();
  test('summary keeps platform, account, period and value without summing', () {
    final rows = [
      QuotaAccount('Codex', '主账号', [
        const QuotaWindow('7天窗口', '剩余 12%', remaining: 12),
      ], sourceTime: now),
      QuotaAccount('Codex', '备用账号', [
        const QuotaWindow('5小时窗口', '剩余 80%', remaining: 80),
      ], sourceTime: now),
    ];
    final summary = quotaOverview(rows).join('\n');
    expect(summary, contains('Codex · 主账号 · 7天窗口 · 剩余 12%'));
    expect(summary, contains('Codex · 备用账号 · 5小时窗口 · 剩余 80%'));
    expect(summary, isNot(contains('92%')));
  });
  test('unavailable values never leak into current summary', () {
    final a = QuotaAccount(
      'GLM',
      '账户',
      [const QuotaWindow('5小时', '剩余 99%', remaining: 99)],
      sourceTime: now,
      error: '认证失败',
    );
    expect(quotaOverview([a]).join(), contains('查询失败，当前数值未知'));
    expect(quotaOverview([a]).join(), isNot(contains('99%')));
    expect(purchaseOverview({}, 'expense').single, contains('金额未知'));
  });
  testWidgets(
    'all business details start hidden, values stay visible and refresh preserves expansion',
    (t) async {
      for (final scale in [1.0, 2.0]) {
        await t.pumpWidget(const SizedBox());
        t.view.physicalSize = const Size(320, 1800);
        t.view.devicePixelRatio = 1;
        Widget page(String value) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    BusinessSummaryCard(
                      title: 'AI额度',
                      lines: [value, '查询失败：1个来源'],
                      children: const [Text('账号周期明细')],
                    ),
                    const BusinessSummaryCard(
                      title: '消费',
                      lines: ['昨日净消费 CNY 128.60', '近30天净消费 USD 23.50'],
                      children: [Text('退款口径详情')],
                    ),
                    const BusinessSummaryCard(
                      title: '快递',
                      lines: ['待发货 1 单 · 运输中 6 单', '近3天签收：未知'],
                      children: [Text('物流订单详情')],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await t.pumpWidget(page('GLM · 5小时剩余12%'));
        await t.pumpAndSettle();
        expect(find.text('账号周期明细'), findsNothing);
        expect(find.text('退款口径详情'), findsNothing);
        expect(find.text('物流订单详情'), findsNothing);
        expect(find.text('GLM · 5小时剩余12%'), findsOneWidget);
        expect(find.text('昨日净消费 CNY 128.60'), findsOneWidget);
        await t.tap(find.text('AI额度'));
        await t.pumpAndSettle();
        expect(find.text('账号周期明细'), findsOneWidget);
        await t.pumpWidget(page('GLM · 5小时剩余11%'));
        await t.pumpAndSettle();
        expect(find.text('账号周期明细'), findsOneWidget);
        await t.tap(find.text('AI额度'));
        await t.pumpAndSettle();
        expect(find.text('账号周期明细'), findsNothing);
        expect(t.takeException(), isNull);
      }
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
  testWidgets('render business overview with synthetic values', (t) async {
    final font = File('/System/Library/Fonts/STHeiti Light.ttc');
    if (font.existsSync()) {
      await (FontLoader('OverviewCJK')..addFont(
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
    final boundary = GlobalKey();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'OverviewCJK',
          scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        ),
        home: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            appBar: AppBar(title: const Text('首页卡片 · 合成数据预览')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                BusinessSummaryCard(
                  title: 'AI额度',
                  lines: [
                    'GLM · 5小时窗口 · 剩余12%',
                    'Codex · 周窗口 · 剩余38%',
                    '6个平台 · 1个来源需关注',
                    '最早来源更新 11-09 09:20 · 北京时间',
                  ],
                  children: [Text('账号与周期明细')],
                ),
                BusinessSummaryCard(
                  title: '消费',
                  lines: [
                    '昨日净消费 CNY 128.60',
                    '近30天净消费 CNY 2,360.00',
                    '仅已导入记录 · 退款按支付订单归属',
                  ],
                  children: [Text('各平台消费明细')],
                ),
                BusinessSummaryCard(
                  title: '快递',
                  lines: [
                    '待发货 1 单 · 运输中 6 单（缓存状态）',
                    '近3天签收：未知',
                    '未来3天预计到货：未知',
                    '签收和预计到货时间尚未接入',
                  ],
                  children: [Text('物流订单明细')],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    if (const bool.fromEnvironment('CARD_PREVIEW')) {
      await expectLater(
        find.byKey(boundary),
        matchesGoldenFile(
          '../../private-diagnostics/card-overview-20261109/overview.png',
        ),
      );
    }
    expect(t.takeException(), isNull);
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
