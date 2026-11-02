import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets('login starts empty and registration is explicit', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    expect(find.text('激活密钥'), findsNothing);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.controller!.text, isEmpty);
    }
    await tester.tap(find.text('没有账号？使用激活密钥注册'));
    await tester.pumpAndSettle();
    expect(find.text('激活密钥'), findsOneWidget);
    expect(find.text('注册并登录'), findsOneWidget);
  });
  testWidgets('zero activity and eight records keep seven finite chart bars', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => const HealthPage().buildBody(c, {
              'data': List.generate(
                8,
                (i) => {'date': '2026-10-${10 + i}', 'steps': 0},
              ),
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('近 7 天步数'), findsOneWidget);
    expect(find.text('10-10'), findsNothing);
  });
  testWidgets('quota clamps unusual percentages', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => const QuotaPage().buildBody(c, {
              'accounts': {
                'test': {
                  'window': {'percent': 150},
                },
              },
            }),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('hospital reports have working file action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => const HdreportPage().buildBody(c, {
              'pdfs': [
                {'name': 'report.pdf', 'mtime': 0, 'size': 1024},
              ],
              'session_age_hours': 25,
            }),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<ListTile>(
            find.ancestor(
              of: find.text('report.pdf'),
              matching: find.byType(ListTile),
            ),
          )
          .onTap,
      isNotNull,
    );
    expect(find.textContaining('已过期'), findsNothing);
  });
  testWidgets('articles are visible and tappable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => const WerssPage().buildBody(c, {
              'feeds': [],
              'articles': [
                {'title': '测试文章', 'url': 'https://mp.weixin.qq.com/s/test'},
              ],
            }),
          ),
        ),
      ),
    );
    expect(find.text('测试文章'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(
            find.ancestor(
              of: find.text('测试文章'),
              matching: find.byType(ListTile),
            ),
          )
          .onTap,
      isNotNull,
    );
  });
  testWidgets('project status is readable and null report accepted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => const DreamPage().buildBody(c, {
              'projects': [
                {'name': '测试项目', 'progress': '等待', 'status': 'blocked'},
              ],
              'report_md': null,
            }),
          ),
        ),
      ),
    );
    expect(find.text('需要处理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
