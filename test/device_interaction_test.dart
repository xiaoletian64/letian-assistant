import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));
  const device = {
    'did': 'test-only',
    'name': '客厅空气净化器',
    'model': 'internal.airpurifier.opaque',
    'online': true,
    'category': 'airpurifier',
    'category_label': '空气净化器',
    'room': '客厅',
    'art': <String, dynamic>{},
  };
  testWidgets('device card identifies appliance without engineering model', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 180,
          height: 220,
          child: HomeDeviceCard(
            device: device,
            onOpen: () => opened = true,
            onSettings: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.air_rounded), findsOneWidget);
    expect(find.text('internal.airpurifier.opaque'), findsNothing);
    await tester.tap(find.text('客厅空气净化器'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'brightness drag previews without sending commands until release',
    (tester) async {
      final writes = <dynamic>[];
      await tester.pumpWidget(
        wrap(
          DeviceControlPanel(
            property: const {
              'prop': 'brightness',
              'value': 49,
              'rw': 'rw',
              'type': 'uint',
              'range': [1, 100, 1],
            },
            busy: false,
            onWrite: (v) async {
              writes.add(v);
              return true;
            },
          ),
        ),
      );
      var slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 1);
      expect(slider.max, 100);
      slider.onChanged!(72);
      await tester.pump();
      expect(writes, isEmpty);
      slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeEnd!(72);
      await tester.pumpAndSettle();
      expect(writes, [72]);
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets('color temperature follows device range and step', (
    tester,
  ) async {
    final writes = <dynamic>[];
    await tester.pumpWidget(
      wrap(
        DeviceControlPanel(
          property: const {
            'prop': 'color-temperature',
            'value': 4000,
            'rw': 'rw',
            'type': 'uint',
            'range': [2700, 5000, 100],
          },
          busy: false,
          onWrite: (v) async {
            writes.add(v);
            return true;
          },
        ),
      ),
    );
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.max, 5000);
    slider.onChangeEnd!(4562);
    await tester.pumpAndSettle();
    expect(writes, [4600]);
  });
  testWidgets('mode names select actual values without freeform numbers', (
    tester,
  ) async {
    dynamic written;
    await tester.pumpWidget(
      wrap(
        DeviceControlPanel(
          property: const {
            'prop': 'mode',
            'value': 1,
            'type': 'uint',
            'rw': 'rw',
            'choices': [
              {'value': 1, 'description': 'Auto'},
              {'value': 6, 'description': 'Sleep'},
            ],
          },
          busy: false,
          onWrite: (v) async {
            written = v;
            return true;
          },
        ),
      ),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '睡眠'));
    await tester.pumpAndSettle();
    expect(written, 6);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets(
    'one power gesture sends one typed bool without engineering dialog',
    (tester) async {
      final writes = <dynamic>[];
      await tester.pumpWidget(
        wrap(
          DeviceControlPanel(
            property: const {
              'prop': 'on',
              'value': false,
              'type': 'bool',
              'rw': 'rw',
            },
            busy: false,
            onWrite: (v) async {
              writes.add(v);
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(writes, [true]);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets('pending operation disables power input', (tester) async {
    await tester.pumpWidget(
      wrap(
        DeviceControlPanel(
          property: const {
            'prop': 'on',
            'value': true,
            'type': 'bool',
            'rw': 'rw',
          },
          busy: true,
          onWrite: (_) async => true,
        ),
      ),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });
  testWidgets(
    'offline device explains recovery instead of an unresponsive tile',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeDevicePage(
            device: (Map<String, dynamic>.from(device)..['online'] = false),
          ),
        ),
      );
      expect(find.text('设备暂时离线'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    },
  );
  testWidgets('large text device card stays within narrow bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: SizedBox(
              width: 160,
              height: 352,
              child: HomeDeviceCard(
                device: device,
                onOpen: () {},
                onSettings: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('completed art job refreshes an existing mutable device card', (
    tester,
  ) async {
    final item = <String, dynamic>{
      'category': 'airpurifier',
      'art': <String, dynamic>{'path': null},
    };
    await tester.pumpWidget(wrap(DeviceArtwork(device: item)));
    expect(find.byType(FutureBuilder<List<int>?>), findsNothing);
    item['art'] = {
      'path': '/api/hub/mihome/icons/000000000000000000000000.png',
    };
    await tester.pumpWidget(wrap(DeviceArtwork(device: item)));
    expect(find.byType(FutureBuilder<List<int>?>), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
