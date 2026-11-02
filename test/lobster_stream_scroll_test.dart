import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets(
    'same-id streamed update does not pull reader to bottom and offers explicit return',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final input = TextEditingController();
      var rows = List<Map<String, dynamic>>.generate(
        24,
        (i) => {
          'id': 'msg-$i',
          'role': i.isEven ? 'user' : 'assistant',
          'content': '第$i条历史消息，包含需要阅读的真实文本。\n内容第二行。',
        },
      );
      late StateSetter update;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (c, set) {
                update = set;
                return LobsterFrameworkChat(
                  messages: rows,
                  input: input,
                  loading: false,
                  busy: false,
                  onSend: () {},
                  emptyBuilder: (_) => const SizedBox(),
                  status: const SizedBox(),
                );
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final list = find.byType(CustomScrollView);
      await t.drag(list, const Offset(0, 450));
      await t.pumpAndSettle();
      final controller = t.widget<CustomScrollView>(list).controller!;
      expect(controller.offset, greaterThan(60));
      final before = controller.offset;
      update(
        () => rows = [
          ...rows.take(23),
          {...rows.last, 'content': '刚收到的真实增量。\n含有半截```dart\nprint('},
        ],
      );
      await t.pumpAndSettle();
      expect(controller.offset, closeTo(before, 1));
      expect(find.text('有新内容 · 回到底部'), findsOneWidget);
      await t.tap(find.text('有新内容 · 回到底部'));
      await t.pumpAndSettle();
      expect(controller.offset, closeTo(0, 1));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      input.dispose();
    },
  );
}
