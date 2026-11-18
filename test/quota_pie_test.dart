import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  final now = DateTime.now().toUtc().toIso8601String();
  final future = DateTime.now()
      .toUtc()
      .add(const Duration(hours: 3))
      .toIso8601String();
  final later = DateTime.now()
      .toUtc()
      .add(const Duration(days: 2))
      .toIso8601String();
  final past = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 1))
      .toIso8601String();

  test('pie slices dedupe platforms and keep the most constrained window', () {
    final slices = quotaPieSlices([
      QuotaAccount('Codex', '主账号', [
        QuotaWindow(
          '5小时窗口',
          '剩余 80%',
          remaining: 80,
          resetAt: DateTime.parse(future).toUtc(),
        ),
        QuotaWindow('7天窗口', '剩余 12%', remaining: 12),
      ], sourceTime: now),
      QuotaAccount('Codex', '备用账号', [
        QuotaWindow('5小时窗口', '剩余 95%', remaining: 95),
      ], sourceTime: now),
      QuotaAccount('GLM', '主账号', [
        QuotaWindow('每周窗口', '剩余 45%', remaining: 45),
      ], sourceTime: now),
    ]);
    expect(slices.map((s) => s.label), ['Codex', 'GLM']);
    expect(slices.first.remaining, 12);
    expect(slices.last.remaining, 45);
  });

  test('failed sources and missing percentages never enter the pie', () {
    final slices = quotaPieSlices([
      QuotaAccount(
        'GLM',
        '坏源',
        [const QuotaWindow('5小时窗口', '剩余 99%', remaining: 99)],
        sourceTime: now,
        error: '查询失败',
      ),
      QuotaAccount('DeepSeek', '余额源', [
        const QuotaWindow('账户余额', '余额 ¥120'),
      ], sourceTime: now),
      QuotaAccount('Codex', '主账号', [
        QuotaWindow('5小时窗口', '剩余 30%', remaining: 30),
      ], sourceTime: now),
    ]);
    expect(slices.map((s) => s.label), ['Codex']);
  });

  test(
    'nextResetAt prefers the earliest future reset and falls back to latest past',
    () {
      final account = QuotaAccount('GLM', '主账号', [
        QuotaWindow(
          '5小时窗口',
          '剩余 40%',
          remaining: 40,
          resetAt: DateTime.parse(past).toUtc(),
        ),
        QuotaWindow(
          '每周窗口',
          '剩余 60%',
          remaining: 60,
          resetAt: DateTime.parse(later).toUtc(),
        ),
        QuotaWindow(
          '5小时窗口',
          '剩余 20%',
          remaining: 20,
          resetAt: DateTime.parse(future).toUtc(),
        ),
      ], sourceTime: now);
      expect(account.nextResetAt, DateTime.parse(future).toUtc());

      final pastOnly = QuotaAccount('GLM', '主账号', [
        QuotaWindow(
          '5小时窗口',
          '剩余 40%',
          remaining: 40,
          resetAt: DateTime.parse(
            past,
          ).toUtc().subtract(const Duration(hours: 2)),
        ),
        QuotaWindow(
          '每周窗口',
          '剩余 60%',
          remaining: 60,
          resetAt: DateTime.parse(past).toUtc(),
        ),
      ], sourceTime: now);
      expect(pastOnly.nextResetAt, DateTime.parse(past).toUtc());

      expect(
        QuotaAccount('GLM', '无时间', [
          const QuotaWindow('5小时窗口', '剩余 40%', remaining: 40),
        ], sourceTime: now).nextResetAt,
        isNull,
      );
    },
  );

  test('overview and collapsed extras surface the nearest period reset', () {
    final accounts = [
      QuotaAccount('GLM', '主账号', [
        QuotaWindow(
          '每周窗口',
          '剩余 45%',
          remaining: 45,
          resetAt: DateTime.parse(later).toUtc(),
        ),
      ], sourceTime: now),
      QuotaAccount('Codex', '主账号', [
        QuotaWindow(
          '5小时窗口',
          '剩余 12%',
          remaining: 12,
          resetAt: DateTime.parse(future).toUtc(),
        ),
      ], sourceTime: now),
    ];
    final line = quotaNextResetLine(accounts)!;
    expect(line, contains('最近周期到：'));
    expect(line, contains('Codex'));
    expect(quotaOverview(accounts).join('\n'), contains('最近周期到：'));
  });

  testWidgets('collapsed AI quota card shows donut, legend and reset line', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final accounts = [
      QuotaAccount('GLM', '主账号', [
        QuotaWindow(
          '每周窗口',
          '剩余 45%',
          remaining: 45,
          resetAt: DateTime.parse(later).toUtc(),
        ),
      ], sourceTime: now),
    ];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuotaOverviewCard(accounts: accounts),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('剩余额度分布'), findsOneWidget);
    expect(find.textContaining('GLM 剩余 45%'), findsOneWidget);
    expect(find.textContaining('最近周期到：'), findsOneWidget);
    expect(find.byType(QuotaDonutChart), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('no percentage sources keep an explicit unknown pie note', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuotaOverviewCard(
              accounts: [
                QuotaAccount('DeepSeek', '余额', [
                  const QuotaWindow('账户余额', '余额 ¥120'),
                ], sourceTime: now),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('暂无可对比的剩余百分比，饼图待来源提供数值'), findsOneWidget);
    expect(find.byType(QuotaDonutChart), findsNothing);
    expect(t.takeException(), isNull);
  });
}
