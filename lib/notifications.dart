import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart' as app;

const _channel = MethodChannel('site.zhangyue.vault/notifications');
const _endpoint = '/api/hub/notifications';
String _origin() => Uri.parse(app.baseUrl).origin;
String _idKey(String origin) => 'notification_installation_$origin';
String _monitorKey(String origin) => 'notification_monitor_binding_$origin';
String _credentialHash(String credential) =>
    crypto.sha256.convert(utf8.encode(credential)).toString();
bool get _android => defaultTargetPlatform == TargetPlatform.android;
String _boundKey(String origin) => 'notification_bound_$origin';
int _bindingGeneration = 0;
Future<String> _installationId(String origin) async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString(_idKey(origin));
  if (id == null) {
    final random = Random.secure();
    id = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await prefs.setString(_idKey(origin), id);
  }
  return id;
}

/// Invoke before removing the old login credential. Native routing and token
/// state are always cleared, even if server unbinding fails.
Future<void> clearNotificationBinding({String? bearerToken}) async {
  _bindingGeneration++;
  final origin = _origin();
  final url = app.baseUrl;
  try {
    final credential = bearerToken ?? await app.token();
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_idKey(origin));
    if (credential == null ||
        credential.isEmpty ||
        id == null ||
        prefs.getBool(_boundKey(origin)) != true) {
      return;
    }
    await app.decodeResponse(
      await app.apiClient
          .delete(
            Uri.parse('$url$_endpoint/devices'),
            headers: {
              'Authorization': 'Bearer $credential',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'installation_id': id}),
          )
          .timeout(const Duration(seconds: 30)),
    );
    await prefs.remove(_boundKey(origin));
  } finally {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_monitorKey(origin));
    try {
      await _channel.invokeMethod('clearBindings');
    } on MissingPluginException {
      /* Older app builds have no native channel. */
    }
  }
}

Future<bool> _bindingCurrent(
  String? credential,
  String origin,
  int generation,
) async =>
    credential != null &&
    credential.isNotEmpty &&
    await app.token() == credential &&
    _origin() == origin &&
    generation == _bindingGeneration;

Future<void> _registerStatus(
  Map<String, dynamic> status,
  String? credential,
  String origin,
  int generation,
) async {
  if (_android) return;
  final pushToken = status['token'];
  if (status['authorization'] != 'authorized' ||
      pushToken is! String ||
      pushToken.isEmpty) {
    return;
  }
  if (!await _bindingCurrent(credential, origin, generation)) return;
  final id = await _installationId(origin);
  if (!await _bindingCurrent(credential, origin, generation)) return;
  final prefs = await SharedPreferences.getInstance();
  if (!await _bindingCurrent(credential, origin, generation)) return;
  await _post('$_endpoint/devices', {
    'installation_id': id,
    'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    'token': pushToken,
  }, credential);
  // Record only actual successful registrations, including one completed during
  // logout, so cleanup never silently overlooks that server binding.
  await prefs.setBool(_boundKey(origin), true);
  if (!await _bindingCurrent(credential, origin, generation)) {
    if (_origin() == origin) {
      await clearNotificationBinding(bearerToken: credential);
    }
  }
}

/// Refresh an existing native token after login/foreground refresh; no prompt,
/// timer, or permission request. Missing native support is a no-op.
Future<void> syncNotificationBinding() async {
  final generation = _bindingGeneration;
  final origin = _origin();
  final credential = await app.token();
  if (!await _bindingCurrent(credential, origin, generation)) return;
  try {
    final status =
        await _channel.invokeMapMethod<String, dynamic>('status') ?? {};
    if (!await _bindingCurrent(credential, origin, generation)) return;
    if (_android) {
      await _checkMonitorBinding(status, credential, origin, generation);
      return;
    }
    await _registerStatus(status, credential, origin, generation);
  } on MissingPluginException {
    return;
  }
}

Future<void> _checkMonitorBinding(
  Map<String, dynamic> status,
  String? credential,
  String origin,
  int generation,
) async {
  if (status['monitor_running'] != true) return;
  final prefs = await SharedPreferences.getInstance();
  if (!await _bindingCurrent(credential, origin, generation)) {
    await clearNotificationBinding(bearerToken: credential);
    return;
  }
  if (prefs.getString(_monitorKey(origin)) != _credentialHash(credential!)) {
    await clearNotificationBinding(bearerToken: credential);
  }
}

/// Native payloads cannot choose a URL or arbitrary route.
Future<String?> consumeNotificationOpenEvent() async {
  final origin = _origin();
  final credential = await app.token();
  if (credential == null || credential.isEmpty) return null;
  try {
    final value = await _channel.invokeMethod<dynamic>('getPendingEvent');
    if (await app.token() != credential || _origin() != origin) return null;
    final id = value is String
        ? value
        : value is Map
        ? value['event_id']
        : null;
    return id is String && RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)
        ? id
        : null;
  } on MissingPluginException {
    return null;
  }
}

Future<dynamic> _post(
  String path,
  Map<String, dynamic> body,
  String? credential,
) async => app.decodeResponse(
  await app.apiClient
      .post(
        Uri.parse('${app.baseUrl}$path'),
        headers: {
          'Authorization': 'Bearer $credential',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 30)),
);

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _settings = {};
  String? _credential;
  String? _error;
  String _authorization = 'unsupported';
  bool _monitorRunning = false, _monitorSupported = false;
  bool _background = false, _configured = false, _loading = true, _busy = false;
  static const _labels = {
    'quota': '低额度',
    'balance': '低余额',
    'server': '服务器异常',
    'reset': '额度重置',
    'recovery': '恢复提醒',
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'tokenChanged' && mounted) {
        await _action((captured) => _permission('status', captured));
      }
    });
    _load();
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<bool> _sameAccount(String? captured) async {
    final current = await app.token();
    if (!mounted) return false;
    if (captured == null || current != captured) {
      String? cleanupError;
      if (captured != null) {
        try {
          await clearNotificationBinding(bearerToken: captured);
        } catch (_) {
          cleanupError = '；旧账号设备绑定解除失败，请重试退出';
        }
      }
      if (!mounted) return false;
      setState(() {
        _items = [];
        _settings = {};
        _configured = false;
        _error = '账号已变化，请返回后重新打开通知${cleanupError ?? ''}';
        _loading = false;
      });
      return false;
    }
    return true;
  }

  Future<void> _load() async {
    final captured = await app.token();
    _credential = captured;
    if (!await _sameAccount(captured)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await app.apiClient
          .get(
            Uri.parse('${app.baseUrl}$_endpoint'),
            headers: {'Authorization': 'Bearer $captured'},
          )
          .timeout(const Duration(seconds: 30));
      if (!await _sameAccount(captured)) return;
      final data = await app.decodeResponse(response) as Map<String, dynamic>;
      if (!await _sameAccount(captured)) return;
      setState(() {
        _items = (data['items'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _settings = Map<String, dynamic>.from(data['settings'] as Map? ?? {});
        final push = data['push'] as Map? ?? {};
        final platform = defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android';
        _configured =
            push[platform] == 'configured' ||
            (_android && push[platform] == 'client_monitor');
      });
      await _permission('status', captured);
    } catch (e) {
      if (!await _sameAccount(captured)) return;
      setState(() {
        if (e is app.SessionExpired || e is app.AccessDenied) {
          _items = [];
          _settings = {};
        }
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _permission(String method, String? captured) async {
    final origin = _origin();
    final generation = _bindingGeneration;
    try {
      final status =
          await _channel.invokeMapMethod<String, dynamic>(method) ?? {};
      if (!await _sameAccount(captured)) return;
      setState(() {
        _authorization = status['authorization']?.toString() ?? 'unsupported';
        _background = status['background_available'] == true;
        _monitorRunning = status['monitor_running'] == true;
        _monitorSupported = status['mode'] == 'foreground_monitor';
      });
      if (_android) {
        await _checkMonitorBinding(status, captured, origin, generation);
        final prefs = await SharedPreferences.getInstance();
        if (!await _sameAccount(captured)) return;
        if (prefs.getString(_monitorKey(origin)) == null && mounted) {
          setState(() => _monitorRunning = false);
        }
      } else {
        await _registerStatus(status, captured, origin, generation);
      }
      await _sameAccount(captured);
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _authorization = 'unsupported';
          _background = false;
          _monitorSupported = false;
          _monitorRunning = false;
        });
      }
    }
  }

  Future<void> _toggleMonitor() => _action((captured) async {
    if (_monitorRunning) {
      await _channel.invokeMethod('stopMonitor');
      if (!await _sameAccount(captured)) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_monitorKey(_origin()));
      if (!await _sameAccount(captured)) return;
      await _permission('status', captured);
      return;
    }
    if (_authorization == 'notDetermined') {
      await _permission('requestPermission', captured);
      if (!await _sameAccount(captured)) return;
    }
    if (_authorization != 'authorized') return;
    final origin = _origin();
    final generation = _bindingGeneration;
    if (!await _bindingCurrent(captured, origin, generation)) return;
    await _channel.invokeMethod('startMonitor', {
      'server': app.baseUrl,
      'bearer': captured,
    });
    if (!await _bindingCurrent(captured, origin, generation)) {
      await clearNotificationBinding(bearerToken: captured);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await _bindingCurrent(captured, origin, generation)) {
      await clearNotificationBinding(bearerToken: captured);
      return;
    }
    await prefs.setString(_monitorKey(origin), _credentialHash(captured!));
    if (!await _sameAccount(captured)) return;
    await _permission('status', captured);
  });

  Future<void> _action(Future<void> Function(String?) action) async {
    if (_busy) return;
    final captured = _credential;
    if (!await _sameAccount(captured)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(captured);
    } catch (e) {
      if (await _sameAccount(captured)) {
        setState(() {
          if (e is app.SessionExpired || e is app.AccessDenied) {
            _items = [];
            _settings = {};
          }
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _set(String key, bool value) => _action((captured) async {
    await _post('$_endpoint/settings', {key: value}, captured);
    if (await _sameAccount(captured)) setState(() => _settings[key] = value);
  });
  Future<void> _read(Map<String, dynamic> item) => _action((captured) async {
    await _post('$_endpoint/read', {
      'ids': [item['id']],
    }, captured);
    if (await _sameAccount(captured)) setState(() => item['read'] = true);
  });
  @override
  Widget build(BuildContext context) {
    final permission = switch (_authorization) {
      'authorized' => '系统通知权限已开启',
      'denied' => '系统通知权限未开启，请前往系统设置',
      'notDetermined' => '尚未请求系统通知权限',
      _ => '当前版本尚不支持系统通知权限通道',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(permission),
          if (_android) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('普通系统通知 · 常驻轻量监测\n会保留运行通知；省电策略可能影响及时性。'),
            ),
            Text(_monitorRunning ? '监测正在运行' : '监测未开启'),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed:
                    _busy ||
                        !_monitorSupported ||
                        (!_monitorRunning && _authorization == 'denied')
                    ? null
                    : _toggleMonitor,
                child: Text(_monitorRunning ? '停止监测' : '开启监测'),
              ),
            ),
          ],
          if (!_android && !_configured)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('推送通道尚未配置；当前不能保证后台送达。'),
            ),
          if (!_android && _authorization == 'authorized' && !_background)
            const Text('此版本尚未提供后台通知接收能力。'),
          if (!_android && _authorization == 'notDetermined')
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () => _action((c) => _permission('requestPermission', c)),
                child: const Text('开启系统通知'),
              ),
            ),
          if (_authorization == 'denied')
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _action((_) async {
                        await _channel.invokeMethod('openSettings');
                      }),
                child: const Text('打开系统设置'),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '提醒设置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const Text(
            '固定阈值：人民币低于5元、美元低于1美元；订阅窗口剩余低于10%。恢复需连续两次有效观测；重置以来源确认的周期证据为准。',
          ),
          for (final entry in _labels.entries)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value),
              value: _settings[entry.key] == true,
              onChanged: _busy || _loading || !_settings.containsKey(entry.key)
                  ? null
                  : (v) => _set(entry.key, v),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '通知记录 · ${_items.where((i) => i['read'] != true).length}条未读',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          if (!_loading && _items.isEmpty) const Text('暂无通知'),
          for (final item in _items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                item['read'] == true
                    ? Icons.notifications_none
                    : Icons.mark_email_unread_outlined,
              ),
              title: Text(item['title']?.toString() ?? '系统提醒'),
              subtitle: Text(item['read'] == true ? '已读' : '标为已读'),
              onTap: _busy || item['read'] == true ? null : () => _read(item),
            ),
        ],
      ),
    );
  }
}
