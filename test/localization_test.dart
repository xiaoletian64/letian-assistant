import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  test('device choices accept case and separators with Chinese fallback', () {
    expect(choiceName('AUTO'), '自动');
    expect(choiceName('energy_saving'), '节能');
    expect(choiceName('turbo'), '强劲');
    expect(choiceName('Brand Special'), '设备模式（Brand Special）');
    expect(choiceName('我的模式'), '我的模式');
  });
  test(
    'unknown property retains technical identifier in Chinese explanation',
    () {
      expect(devicePropertyName({'prop': 'mystery-2-1'}), '其他设置（mystery-2-1）');
      expect(devicePropertyName({'prop': 'child-lock-2-1'}), '童锁');
      expect(devicePropertyName({'prop': 'x', 'description': '我的属性'}), '我的属性');
    },
  );
  test('raw device enum is localized without changing numbers or errors', () {
    expect(deviceValue({'prop': 'mode', 'value': 'auto'}), '自动');
    expect(deviceValue({'prop': 'mode', 'value': 'mystery'}), '设备模式（mystery）');
    expect(deviceValue({'prop': 'temperature', 'value': 25}), '25 °C');
    expect(deviceValue({'prop': 'ssid', 'value': 'My WiFi'}), 'My WiFi');
    expect(deviceValue({'prop': 'status', 'error': 'raw'}), '暂时读不到');
  });
  test('service states never treat missing or new values as healthy', () {
    expect(serviceStatusLabel('active'), '运行中');
    expect(serviceStatusLabel('inactive'), '未运行');
    expect(serviceStatusLabel('failed'), '运行失败');
    expect(serviceStatusLabel('activating'), '启动中');
    expect(serviceStatusLabel('deactivating'), '停止中');
    expect(serviceStatusLabel('reloading'), '重新加载中');
    expect(serviceStatusLabel('unknown'), '状态未知');
    expect(serviceStatusLabel(null), '状态未知');
    expect(serviceStatusLabel('new-state'), '状态未知（new-state）');
  });
  test('common errors are Chinese and original Chinese is preserved', () {
    expect(friendlyError('ECONNREFUSED'), '服务暂时无法连接，请稍后重试');
    expect(friendlyError('unauthorized'), '登录已过期，请重新登录后继续');
    expect(friendlyError('service_unavailable'), '服务暂时无法连接，请稍后重试');
    expect(friendlyError(TimeoutException('raw')), '连接超时，请检查网络后重试');
    expect(friendlyError('第三方授权需要更新'), '第三方授权需要更新');
    expect(friendlyError('unfamiliar_code'), '操作未完成，请稍后重试（unfamiliar_code）');
  });
  testWidgets('standard Material controls also use Chinese', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const VaultApp());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(LoginPage));
    expect(MaterialLocalizations.of(context).pasteButtonLabel, '粘贴');
  });
}
