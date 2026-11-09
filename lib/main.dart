import 'dart:async';
import 'notifications.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart' as sha256_lib;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart' as flyer;
import 'package:flutter_chat_core/flutter_chat_core.dart' as chat_core;
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart'
    as flyer_text;

part 'home_devices.dart';
part 'runtime_config.dart';
part 'server_monitor.dart';
part 'quota_history.dart';
part 'tibo_card.dart';
part 'ios_sync.dart';
part 'localization.dart';
part 'dashboard.dart';
part 'plugin_catalog.dart';
part 'content_pages.dart';
part 'scene_models.dart';
part 'scene_home.dart';
part 'business_cards.dart';
part 'lobster_chat.dart';
part 'lobster_framework.dart';
part 'lobster_stream.dart';

http.Client apiClient = http.Client();
http.Client otaClient = http.Client();
final appNavigatorKey = GlobalKey<NavigatorState>();
bool _updateDialogVisible = false;

String get baseUrl => runtimeConfig.apiBaseUrl;
String get otaUrl => runtimeConfig.updateManifestUrl;
const currentVersion = '2.13.0';
const currentVersionCode = 47;

Future<Map<String, dynamic>?> checkOta() async {
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      !runtimeConfig.configured) {
    return null;
  }
  try {
    final r = await otaClient
        .get(Uri.parse(otaUrl))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode == 200) {
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    }
  } catch (_) {}
  return null;
}

void showUpdateDialog(BuildContext context, Map<String, dynamic> m) {
  if (_updateDialogVisible) return;
  _updateDialogVisible = true;
  final remote = m['versionName'] ?? '';
  final sha = (m['sha256'] ?? '').toString();
  final url = (m['url'] ?? '').toString();
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('发现新版本 $remote'),
      content: Text('${m['notes'] ?? ''}\n\n当前版本 $currentVersion'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('以后'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              const ch = MethodChannel('site.zhangyue.vault/install');
              await ch.invokeMethod('installFromUrl', {'url': url, 'sha': sha});
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('下载中…完成后自动提示安装')));
              }
            } catch (e) {
              final msg = e.toString();
              final needPerm = msg.contains('perm') || msg.contains('允许安装');
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('更新失败：$msg'),
                  backgroundColor: Colors.red.shade400,
                ),
              );
              if (needPerm) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('需要安装权限'),
                    content: const Text(
                      '系统还不允许乐天助手安装应用。\n点下面按钮到设置里打开「允许来自此来源的应用」，再回来点一次检查更新即可。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('知道了'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          const MethodChannel(
                            'site.zhangyue.vault/sys',
                          ).invokeMethod('openInstallSettings');
                        },
                        child: const Text('去设置开启'),
                      ),
                    ],
                  ),
                );
              }
            }
          },
          child: const Text('下载并安装'),
        ),
      ],
    ),
  ).whenComplete(() => _updateDialogVisible = false);
}

String cryptoSha256(List<int> b) {
  var h = sha256_lib.sha256.convert(b);
  return h.toString();
}

Future<void> installApkFromBytes(List<int> bytes) async {
  const ch = MethodChannel('site.zhangyue.vault/install');
  try {
    await ch.invokeMethod('installApk', {'bytes': bytes});
  } catch (e) {
    rethrow;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runtimeConfig = await RuntimeConfig.load();
  runApp(
    runtimeConfig.configured
        ? const VaultApp()
        : const ConfigurationRequiredApp(),
  );
}

class StartupUpdateObserver extends StatefulWidget {
  const StartupUpdateObserver({
    super.key,
    required this.navigatorKey,
    required this.child,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  @override
  State<StartupUpdateObserver> createState() => _StartupUpdateObserverState();
}

class _StartupUpdateObserverState extends State<StartupUpdateObserver>
    with WidgetsBindingObserver {
  bool _checking = false;
  DateTime? _lastCheck;
  int? _promptedVersion;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final now = DateTime.now();
    if (_checking ||
        (_lastCheck != null &&
            now.difference(_lastCheck!) < const Duration(minutes: 5))) {
      return;
    }
    _checking = true;
    _lastCheck = now;
    try {
      final release = await checkOta();
      if (!mounted || release == null) return;
      final version = int.tryParse('${release['versionCode']}') ?? 0;
      if (version <= currentVersionCode ||
          version == _promptedVersion ||
          _updateDialogVisible) {
        return;
      }
      final context = widget.navigatorKey.currentState?.overlay?.context;
      if (context == null || !context.mounted) return;
      _promptedVersion = version;
      showUpdateDialog(context, release);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class VaultApp extends StatelessWidget {
  const VaultApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: appNavigatorKey,
    builder: (c, child) =>
        StartupUpdateObserver(navigatorKey: appNavigatorKey, child: child!),
    title: '乐天助手',
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF5F7FB),
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardColor: Colors.white,
      cardTheme: ThemeData().cardTheme.copyWith(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      useMaterial3: true,
    ),
    home: const RootPage(),
  );
}

// ---------------- storage ----------------
Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();
Future<String?> token() async => (await _prefs()).getString('token');

class SessionExpired implements Exception {
  @override
  String toString() => '登录已过期，请重新登录后继续';
}

class AccessDenied implements Exception {
  @override
  String toString() => '当前账号无权访问此功能，请检查平台权限';
}

Future<dynamic> decodeResponse(http.Response r) async {
  if (r.statusCode == 401) throw SessionExpired();
  if (r.statusCode == 403) throw AccessDenied();
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception(
      r.statusCode == 502 || r.statusCode == 503
          ? '服务暂时无法连接，请稍后重试'
          : '操作未完成（${r.statusCode}），请重试',
    );
  }
  try {
    return jsonDecode(utf8.decode(r.bodyBytes));
  } catch (_) {
    throw Exception('服务返回异常，请稍后刷新');
  }
}

Future<dynamic> apiGet(String path) async => decodeResponse(
  await apiClient
      .get(
        Uri.parse(baseUrl + path),
        headers: {'Authorization': 'Bearer ${await token()}'},
      )
      .timeout(const Duration(seconds: 30)),
);
Future<dynamic> apiPost(String path, Map<String, dynamic> body) async =>
    decodeResponse(
      await apiClient
          .post(
            Uri.parse(baseUrl + path),
            headers: {
              'Authorization': 'Bearer ${await token()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30)),
    );

Future<void> clearAlertsBeforeLogout(
  BuildContext context,
  String? credential,
) async {
  try {
    await clearNotificationBinding(bearerToken: credential);
  } catch (_) {
    if (context.mounted) notice(context, '本机通知已关闭；服务器解绑暂未确认');
  }
}

void notice(BuildContext c, String message) {
  if (c.mounted) {
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<void> openLink(BuildContext c, String url) async {
  try {
    await const MethodChannel(
      'site.zhangyue.vault/sys',
    ).invokeMethod('openUrl', {'url': url});
  } catch (_) {
    if (c.mounted) notice(c, '无法打开链接，请确认已安装对应应用');
  }
}

Future<void> openPrivateFile(
  BuildContext c,
  String path,
  String name,
  String mime,
) async {
  notice(c, '正在下载，请稍候…');
  try {
    final completed = await const MethodChannel('site.zhangyue.vault/sys')
        .invokeMethod('openPrivateFile', {
          'url': baseUrl + path,
          'token': await token(),
          'name': name,
          'mime': mime,
        });
    if (c.mounted && completed == false) {
      ScaffoldMessenger.of(c).removeCurrentSnackBar();
      notice(c, '已取消保存');
    }
  } catch (_) {
    if (c.mounted) {
      ScaffoldMessenger.of(c).removeCurrentSnackBar();
      notice(c, '下载或打开失败，请检查网络与文件查看应用后重试');
    }
  }
}

Widget emptyState(String title, String description) => Padding(
  padding: const EdgeInsets.all(24),
  child: Column(
    children: [
      const Icon(Icons.inbox_outlined, size: 44, color: Color(0xFF94A3B8)),
      const SizedBox(height: 12),
      Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(
        description,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF64748B), height: 1.6),
      ),
    ],
  ),
);
Widget errorState(BuildContext c, String error, VoidCallback retry) => Center(
  child: SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.cloud_off_outlined,
          size: 44,
          color: Color(0xFF64748B),
        ),
        const SizedBox(height: 16),
        Text(friendlyError(error), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: retry, child: const Text('重新加载')),
        if (error.contains('登录已过期'))
          TextButton(
            onPressed: () async {
              final credential = await token();
              if (!c.mounted) return;
              await clearAlertsBeforeLogout(c, credential);
              await (await _prefs()).remove('token');
              if (c.mounted) {
                Navigator.of(c).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (_) => false,
                );
              }
            },
            child: const Text('重新登录'),
          ),
      ],
    ),
  ),
);

// ---------------- root: gate or home ----------------
class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  String? _token;
  bool _loading = true;
  bool _locked = false;

  static const _lockCh = MethodChannel('site.zhangyue.vault/install');

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    _token = await token();
    if (_token != null) {
      try {
        final enabled = await _lockCh.invokeMethod('lockEnabled');
        if (enabled == true) {
          setState(() {
            _locked = true;
            _loading = false;
          });
          return;
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_token == null) return const LoginPage();
    if (_locked) {
      return LockScreen(onUnlocked: () => setState(() => _locked = false));
    }
    return const SceneShell();
  }
}

/// 锁屏：指纹/人脸（自动弹出）+ 备用密码（notes 账号密码验证）。
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const _lockCh = MethodChannel('site.zhangyue.vault/install');
  final pw = TextEditingController();
  String msg = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
  }

  Future<void> _bio() async {
    try {
      final ok = await _lockCh.invokeMethod('bioAuth');
      if (ok == true && mounted) {
        widget.onUnlocked();
      } else if (mounted) {
        setState(() => msg = '未完成系统验证，也可输入账号密码解锁');
      }
    } catch (_) {}
  }

  Future<void> _pw() async {
    // 密码走服务端验证（appkey challenge 同款）
    setState(() => msg = '验证中…');
    try {
      final r = await apiPost('/api/hub/appkey/challenge', {
        'mode': 'password',
        'password': pw.text,
      });
      if (r['nonce'] != null) {
        widget.onUnlocked();
        return;
      }
      final err = (r['error'] ?? '').toString();
      setState(
        () => msg = err.isNotEmpty ? '验证失败（$err）· 登录态可能已过期，用下方「重新登录」' : '密码不对',
      );
    } catch (e) {
      setState(() => msg = '网络错误：$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('应用已锁定')),
    body: ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Icon(Icons.lock, size: 64, color: Colors.deepPurple),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _bio,
          icon: const Icon(Icons.fingerprint),
          label: const Text('使用手机锁屏验证'),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: pw,
          obscureText: true,
          decoration: const InputDecoration(labelText: '账号密码解锁'),
        ),
        const SizedBox(height: 10),
        FilledButton(onPressed: _pw, child: const Text('密码解锁')),
        TextButton(
          onPressed: () async {
            final credential = await token();
            if (!context.mounted) return;
            await clearAlertsBeforeLogout(context, credential);
            await (await _prefs()).remove('token');
            if (context.mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            }
          },
          child: const Text('登录态过期？重新登录', style: TextStyle(fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(msg, style: const TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

// ---------------- login ----------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final u = TextEditingController(),
      p = TextEditingController(),
      k = TextEditingController();
  bool registering = false, reveal = false;
  @override
  void dispose() {
    u.dispose();
    p.dispose();
    k.dispose();
    super.dispose();
  }

  String msg = '';
  bool busy = false;

  Future<void> _go(bool register) async {
    if (u.text.trim().isEmpty ||
        p.text.isEmpty ||
        (register && p.text.length < 6)) {
      set('用户名/密码太弱（密码≥6位）');
      return;
    }
    if (register && k.text.trim().isEmpty) {
      set('注册需要激活密钥');
      return;
    }
    set('连接中…');
    setState(() => busy = true);
    try {
      final body = {'username': u.text.trim(), 'password': p.text};
      if (register) body['appkey'] = k.text.trim();
      final r = await apiClient
          .post(
            Uri.parse(baseUrl + (register ? '/api/register' : '/api/login')),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (r.statusCode == 200 &&
          d['token'] is String &&
          (d['token'] as String).isNotEmpty) {
        final prefs = await _prefs();
        await prefs.setString('token', d['token']);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SceneShell()),
        );
      } else {
        set(
          {
                'invalid_appkey': '激活密钥不对',
                'username_taken': '用户名已存在',
                'bad_credentials': '用户名或密码错误',
              }[d['error']] ??
              (d['error'] ?? 'HTTP ${r.statusCode}'),
        );
      }
    } catch (e) {
      set('网络错误');
    }
    if (mounted) setState(() => busy = false);
  }

  void set(String s) {
    if (mounted) setState(() => msg = s);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('乐天助手')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Icon(
              Icons.dashboard_customize_outlined,
              size: 52,
              color: Color(0xFF2563EB),
            ),
            const SizedBox(height: 20),
            Text(
              registering ? '创建账号' : '欢迎回来',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text('登录后管理你的数据、设备与常用服务', textAlign: TextAlign.center),
            const SizedBox(height: 32),
            TextField(
              controller: u,
              enabled: !busy,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '用户名',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: p,
              enabled: !busy,
              obscureText: !reveal,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) {
                if (!busy) _go(registering);
              },
              decoration: InputDecoration(
                labelText: registering ? '密码（至少 6 位）' : '密码',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: reveal ? '隐藏密码' : '显示密码',
                  onPressed: () => setState(() => reveal = !reveal),
                  icon: Icon(reveal ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
            if (registering) ...[
              const SizedBox(height: 16),
              TextField(
                controller: k,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: '激活密钥',
                  helperText: '向管理员获取注册所需的激活密钥',
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : () => _go(registering),
              child: Text(
                busy
                    ? '正在连接…'
                    : registering
                    ? '注册并登录'
                    : '登录',
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      registering = !registering;
                      msg = '';
                    }),
              child: Text(registering ? '已有账号？返回登录' : '没有账号？使用激活密钥注册'),
            ),
            if (msg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// ---------------- home: 14 cards ----------------
class AsyncPage extends StatefulWidget {
  const AsyncPage({super.key, required this.title, this.apiPath = '/'});
  final String title;
  final String apiPath;
  Widget buildBody(BuildContext c, dynamic d) => const SizedBox();
  @override
  State<AsyncPage> createState() => _AsyncPageState();
}

class _AsyncPageState extends State<AsyncPage> {
  Object? data;
  String err = '';
  bool busy = true;

  Future<dynamic> fetch() => apiGet(widget.apiPath);
  String get apiPath => '/';
  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      busy = true;
      err = '';
    });
    try {
      data = await fetch();
    } catch (e) {
      err = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
          onPressed: busy ? null : load,
        ),
      ],
    ),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : err.isNotEmpty
        ? errorState(context, err, load)
        : RefreshIndicator(
            onRefresh: load,
            child: widget.buildBody(context, data),
          ),
  );
}

// ---------------- 笔记库 ----------------
class SimpleApiPage extends AsyncPage {
  const SimpleApiPage({
    super.key,
    required super.title,
    required this.infoPath,
    required this.sections,
  });
  final String infoPath;
  final List<String> sections;
  @override
  String get apiPath => infoPath;
  @override
  Widget buildBody(BuildContext c, dynamic d) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      for (final e in (d as Map).entries)
        ListTile(
          title: Text(
            e.key,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          subtitle: Text('${e.value}', style: const TextStyle(fontSize: 14)),
        ),
    ],
  );
}

// ---------------- 笔记库（保险库 + 登录流水）----------------
class VaultPage extends StatefulWidget {
  const VaultPage({super.key});
  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  dynamic d;
  String err = '';
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      busy = true;
      err = '';
    });
    try {
      d = await apiGet('/api/vault/info');
    } catch (e) {
      err = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  static String _size(num b) {
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(2)} GB';
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final logins = ((d?['logins'] ?? []) as List);
    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记备份'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: busy ? null : load,
          ),
        ],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : err.isNotEmpty
          ? errorState(context, err, load)
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF7C3AED,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.inventory_2,
                                  color: Color(0xFF7C3AED),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${d?['file'] ?? '-'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${_size((d?['bytes'] ?? 0) as num)} · 更新 ${d?['updated'] ?? '-'}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _stat('用户', '${d?['users'] ?? 0}'),
                              _stat('登录记录', '${logins.length}'),
                              _stat(
                                '完整性校验',
                                (d?['sha256'] == null) ? '未生成' : '已生成',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (d?['bytes'] ?? 0) > 0
                        ? () => openPrivateFile(
                            context,
                            '/api/vault/download',
                            'notes-backup.zip',
                            'application/zip',
                          )
                        : null,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('下载笔记备份'),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      '下载后可用系统文件管理器打开或保存备份。',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 14, 6, 6),
                    child: Text(
                      '最近登录记录',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (logins.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '暂无登录记录',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    for (final l in logins)
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            l['ok'] == 1 ? Icons.check_circle : Icons.error,
                            color: l['ok'] == 1 ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          title: Text(
                            '${l['ts']}'.replaceAll('T', ' '),
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '${l['ip'] ?? '-'} · ${l['reason'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _stat(String k, String v) => Expanded(
    child: Column(
      children: [
        Text(
          v,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text(k, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      ],
    ),
  );
}

// ---------------- Minis 同步（合并自 Minis Companion v0.6 的 SAF 扫描+上传）----------------
class SyncPage extends StatefulWidget {
  const SyncPage({super.key});
  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  static const channel = MethodChannel('site.zhangyue.vault/minis');
  bool? installed;
  String? error;
  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform != TargetPlatform.iOS) check();
  }

  Future<void> check() async {
    try {
      final v = await channel.invokeMethod<bool>('installed');
      if (mounted) setState(() => installed = v ?? false);
    } catch (_) {
      if (mounted) setState(() => error = '无法读取应用状态，请重试');
    }
  }

  Future<void> launch() async {
    try {
      final ok = await channel.invokeMethod<bool>('launch');
      if (ok != true) throw Exception('请先安装 Minis 同步版');
    } catch (_) {
      if (mounted) setState(() => error = '未能打开同步版，请先安装后重试');
    }
  }

  @override
  Widget build(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.iOS
      ? const IosBackupPage()
      : Scaffold(
          appBar: AppBar(title: const Text('Minis 同步')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(
                Icons.cloud_sync_outlined,
                size: 52,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(height: 18),
              const Text(
                '同步在 Minis 内完成',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                '无需 root。使用同步版 Minis，打开应用即可检查并同步。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF64748B), height: 1.6),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        installed == null
                            ? '正在检查安装状态'
                            : installed!
                            ? '同步版已安装'
                            : '首次使用',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '1. 保留官方 Minis，在原版中导出完整备份。\n2. 在同步版导入备份，核对聊天、附件、记忆和配置。\n3. 登录同一乐天账户并启用自动同步。',
                        style: TextStyle(height: 1.9, color: Color(0xFF475569)),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: installed == true
                              ? launch
                              : () async {
                                  try {
                                    await channel.invokeMethod('download');
                                  } catch (_) {
                                    if (mounted) {
                                      setState(() => error = '无法打开下载页，请稍后重试');
                                    }
                                  }
                                },
                          icon: Icon(
                            installed == true
                                ? Icons.open_in_new
                                : Icons.download_outlined,
                          ),
                          label: Text(
                            installed == true ? '打开同步设置' : '下载 Minis 同步版',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: check,
                        child: const Text('重新检查安装状态'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '数据与恢复',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                '同步状态、最近成功时间、冲突副本和恢复备份，请在同步版的「乐天同步」中查看。上传完成不代表另一台已经接收。原版应用和原始备份请保留到迁移验收完成。',
                style: TextStyle(height: 1.7, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              const Text(
                '更新保留数据',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                '同步版有独立更新通道。后续版本保持同一包名和签名，覆盖升级保留数据；不要用官方 APK 覆盖同步版。',
                style: TextStyle(height: 1.7, color: Color(0xFF64748B)),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        );
}

class QrPage extends StatefulWidget {
  const QrPage({super.key});
  @override
  State<QrPage> createState() => _QrPageState();
}

class _QrPageState extends State<QrPage> {
  static const _sys = MethodChannel('site.zhangyue.vault/sys');
  dynamic data;
  String? dataSession;
  bool busy = true;
  bool renewing = false;
  Timer? poll;
  String msg = '', error = '';
  @override
  void initState() {
    super.initState();
    load();
    poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!busy &&
          !renewing &&
          mounted &&
          data is Map &&
          ['jd', 'dianping'].any(
            (k) => [
              'awaiting_scan',
              'awaiting_confirmation',
              'loading',
              'starting',
            ].contains(data[k]?['state']),
          )) {
        load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  Future<void> refreshPlatform(String id) async {
    if (renewing) return;
    setState(() {
      renewing = true;
      msg = '';
    });
    try {
      await apiPost('/api/hub/connections/refresh', {'platform': id});
      await load(silent: true);
    } catch (e) {
      if (mounted) setState(() => msg = friendlyError(e));
    } finally {
      if (mounted) setState(() => renewing = false);
    }
  }

  Future<void> load({bool silent = false}) async {
    if (!mounted) return;
    final captured = await token();
    if (!mounted) return;
    setState(() {
      if (dataSession != captured) data = null;
      dataSession = captured;
      if (!silent) busy = true;
      msg = '';
      error = '';
    });
    try {
      final result = await apiGet('/api/qr/all');
      if (mounted && await token() == captured) data = result;
    } catch (e) {
      if (await token() == captured) {
        if (e is SessionExpired || e is AccessDenied) data = null;
        error = friendlyError(e);
      }
    }
    if (mounted) {
      final active = await token();
      if (mounted) {
        setState(() {
          if (active != captured) {
            data = null;
            error = '账号已变化，请刷新确认';
          }
          busy = false;
        });
      }
    }
  }

  /// 免扫码：把二维码内容文本直接丢给本机 App（抖音/点评/微信）完成授权。
  Future<void> _jump(String name, String? content) async {
    if (content == null || content.isEmpty) {
      setState(() => msg = '$name：暂无可跳转的授权链接（等码生成后再试）');
      return;
    }
    try {
      await _sys.invokeMethod('openUrl', {'url': content});
      if (!mounted) return;
      setState(() => msg = '已跳转 $name —— 在 App 里完成授权后回来点右上角刷新');
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      setState(() => msg = '本机没有能打开该链接的 App，内容已复制到剪贴板，可粘贴使用');
    }
  }

  Widget row(
    String name,
    dynamic d, {
    bool jd = false,
    String id = 'jd',
    String description = '',
  }) {
    final available = d is Map && d['error'] == null;
    final connected = available && d['logged_in'] == true;
    final content = available ? d['content']?.toString() : null;
    final image = available ? d['image_base64']?.toString() : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connected
                      ? Icons.check_circle_outline
                      : Icons.account_circle_outlined,
                  color: connected ? Colors.green : const Color(0xFF64748B),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  description,
                  style: const TextStyle(color: Color(0xFF64748B), height: 1.5),
                ),
              ),
            if (available && d['message'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${d['message']}',
                  style: const TextStyle(height: 1.5),
                ),
              ),
            Text(
              connected
                  ? '已连接'
                  : !available
                  ? '暂时无法读取状态，请刷新重试'
                  : content != null || image != null
                  ? '等待你完成授权'
                  : '暂无待授权连接，可打开授权管理获取',
            ),
            if (jd && !connected)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: renewing ? null : () => refreshPlatform(id),
                  icon: renewing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(renewing ? '正在生成二维码…' : '刷新二维码'),
                ),
              ),
            if (!jd &&
                !connected &&
                available &&
                d['state'] != 'not_implemented' &&
                d['state'] != 'not_configured')
              TextButton.icon(
                onPressed: busy ? null : load,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新授权状态与二维码'),
              ),
            if (!connected && content != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _jump(name, content),
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开应用授权'),
              ),
            ],
            if (!connected && image != null)
              ExpansionTile(
                initiallyExpanded: jd,
                title: const Text('显示二维码'),
                subtitle: const Text('可用另一台设备扫码'),
                children: [qrImage(image)],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wx = data?['wechat'];
    final wxItems =
        ((wx is Map ? (wx['items'] ?? []) : (wx is List ? wx : [])) as List);
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号授权'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: busy ? null : load,
          ),
        ],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
          ? errorState(context, error, load)
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '选择平台完成授权，返回这里刷新查看连接状态。',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
                  if (data?['platforms'] is Map &&
                      data?['platforms']['cards'] is List)
                    for (final card
                        in (data['platforms']['cards'] as List)
                            .whereType<Map>())
                      row(
                        '${card['title'] ?? card['id']}',
                        card['status'],
                        id: '${card['id']}',
                        description: '${card['description'] ?? ''}',
                        jd: card['refresh_action'] == 'refresh',
                      )
                  else ...[
                    row('京东 · 106服务器', data?['jd'], jd: true),
                    row('抖音', data?['douyin']),
                    row('大众点评', data?['dianping']),
                  ],
                  if (wxItems.isEmpty)
                    row(
                      '微信桌面',
                      wx is Map && wx['error'] != null
                          ? wx
                          : <String, dynamic>{},
                    ),
                  for (final item in wxItems)
                    row('微信 · ${item['title'] ?? '桌面授权'}', item),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        openLink(context, runtimeConfig.authorizationUrl),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('打开授权管理'),
                  ),
                  if (msg.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        msg,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  static const _cam = MethodChannel('site.zhangyue.vault/camera');
  dynamic task;
  String msg = '';
  bool busy = false, loading = true, fetching = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    poll();
  }

  Future<void> poll() async {
    if (!mounted || fetching) return;
    setState(() {
      fetching = true;
      error = '';
    });
    try {
      final d = await apiGet('/api/camera/next');
      if (mounted) setState(() => task = d['task']);
    } catch (_) {
      if (mounted) setState(() => error = '无法获取拍摄任务，请检查网络后重试');
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          fetching = false;
        });
      }
    }
  }

  Future<void> _shoot({required bool camera}) async {
    if (busy) return;
    setState(() => busy = true);
    final taskId = task?['id'];
    if (taskId == null) {
      if (mounted) setState(() => busy = false);
      return;
    }
    try {
      setState(() => msg = camera ? '正在打开相机…' : '请选择图片…');
      final r = await _cam.invokeMethod(camera ? 'takePhoto' : 'pickPhoto');
      if (!mounted) return;
      final url = (r is Map) ? r['dataUrl'] as String? : null;
      if (url == null) {
        setState(() => msg = '已取消');
        return;
      }
      final kb = (url.length * 3 / 4 / 1024).toStringAsFixed(0);
      setState(() => msg = '已获取照片（$kb KB），上传中…');
      final d = await apiPost('/api/camera/result', {
        'id': taskId,
        'image': url,
      });
      if (!mounted) return;
      setState(
        () => msg = d['ok'] == true ? '任务 #$taskId 已成功回传' : '照片未能上传，请重试',
      );
      await poll();
    } catch (e) {
      if (!mounted) return;
      setState(() => msg = '失败：${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('拍摄任务')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error.isNotEmpty
        ? errorState(context, error, poll)
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                task == null
                    ? '当前没有待处理任务\n有新的拍摄请求时，点击刷新即可查看。'
                    : '任务 #${task['id']}（${task['origin']}）\n${task['spec']}',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 20),
              if (task != null) ...[
                Semantics(
                  button: true,
                  label: '打开相机拍照回传',
                  child: FilledButton.icon(
                    onPressed: busy ? null : () => _shoot(camera: true),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('打开相机拍照回传'),
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  button: true,
                  label: '从相册选择',
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => _shoot(camera: false),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('从相册选择'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: '刷新任务',
                child: OutlinedButton(
                  onPressed: busy || fetching ? null : poll,
                  child: const Text('刷新任务'),
                ),
              ),
              const SizedBox(height: 8),
              if (busy || fetching) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(msg, style: const TextStyle(color: Colors.blue)),
            ],
          ),
  );
}

class QuotaPage extends AsyncPage {
  const QuotaPage({super.key})
    : super(title: '额度查询', apiPath: '/api/hub/quota');
  @override
  Widget buildBody(BuildContext c, dynamic d) {
    final acc = (d['accounts'] ?? {}) as Map;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (acc.isEmpty) emptyState('暂无额度数据', '连接模型账户后，刷新查看余额和用量。'),
        for (final name in acc.keys) _accountCard(name, acc[name]),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            d['cached'] == true ? '显示最近缓存的数据，下拉可重试查询' : '已从服务获取最新数据',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _accountCard(String name, dynamic a) {
    final rows = <Widget>[];
    if (a is Map) {
      a.forEach((k, v) {
        if (v is Map && v['percent'] != null) {
          final pct = (v['percent'] as num).toDouble();
          rows.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${const {'five_hour': '每 5 小时', 'monthly': '每月', 'weekly': '每周', 'rolling': '滚动周期'}[k] ?? k} · 已用 ${pct.toStringAsFixed(0)}% · ${v['reset'] ?? '待更新'} 重置',
                    style: const TextStyle(fontSize: 13),
                  ),
                  LinearProgressIndicator(
                    value: (pct / 100).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: Colors.grey.shade200,
                    color: pct > 80
                        ? Colors.red
                        : (pct > 60 ? Colors.orange : Colors.green),
                  ),
                ],
              ),
            ),
          );
        } else if (k == 'amount') {
          rows.add(
            Text(
              '余额 ¥$v',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          );
        }
      });
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              const {
                    'deepseek': 'DeepSeek',
                    'zhipu': '智谱 AI',
                    'opencode': 'OpenCode',
                  }[name] ??
                  name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class VbPage extends AsyncPage {
  const VbPage({super.key}) : super(title: '路由状态', apiPath: '/api/hub/vb');
  @override
  Widget buildBody(BuildContext c, dynamic d) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        color: d['banned_guess'] == true
            ? Colors.red.shade50
            : Colors.green.shade50,
        child: ListTile(
          title: Text(
            d['banned_guess'] == true ? '疑似有封禁生效' : '未见封禁',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      const SizedBox(height: 8),
      ExpansionTile(
        title: const Text('查看诊断详情'),
        children: [
          for (final l in ((d['raw'] as List?) ?? []))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelectableText('$l', style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    ],
  );
}

bool itemCanOpen(dynamic item) {
  final link = '${item['link'] ?? ''}';
  final file = '${item['file'] ?? ''}';
  return link.startsWith('https://') ||
      link.startsWith('http://') ||
      (file.startsWith('/api/') && !file.contains('..'));
}

Future<void> openPluginItem(BuildContext c, dynamic item) async {
  final link = '${item['link'] ?? ''}';
  if (link.startsWith('https://') || link.startsWith('http://')) {
    await openLink(c, link);
    return;
  }
  final file = '${item['file'] ?? ''}';
  if (file.startsWith('/api/') && !file.contains('..')) {
    await openPrivateFile(
      c,
      file,
      '${item['filename'] ?? '文件'}',
      '${item['mime'] ?? 'application/octet-stream'}',
    );
  }
}

Future<void> runPluginAction(
  BuildContext c,
  Map<String, dynamic> act,
  Future<void> Function() reload,
) async {
  if (act['type'] == 'open_url') {
    final url = '${act['url'] ?? ''}';
    if (url.startsWith('https://')) await openLink(c, url);
    return;
  }
  if (act['type'] != 'confirm_post') return;
  final path = '${act['path'] ?? ''}';
  if (!path.startsWith('/api/hub/') || path.contains('..')) return;
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text('${act['label'] ?? '确认'}'),
      content: Text('${act['confirm'] ?? '确认继续吗？'}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(d, true),
          child: const Text('确认'),
        ),
      ],
    ),
  );
  if (ok != true || !c.mounted) return;
  try {
    final result = await apiPost(path, {});
    if (result is Map && (result['ok'] == false || result['error'] != null)) {
      throw Exception('操作未完成，请稍后重试');
    }
    if (c.mounted) notice(c, '已经完成');
    await reload();
  } catch (e) {
    if (c.mounted) notice(c, '没有完成，请稍后再试');
  }
}

class HealthPage extends AsyncPage {
  const HealthPage({super.key})
    : super(title: '运动健康', apiPath: '/api/hub/mihealth?kind=summary&days=7');
  @override
  Widget buildBody(BuildContext c, dynamic d) {
    final records = List<dynamic>.from((d['data'] ?? []) as List)
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final list = records.length > 7
        ? records.sublist(records.length - 7)
        : records;
    final maxSteps = list.isEmpty
        ? 1.0
        : list
              .map((e) => ((e['steps'] ?? 0) as num).toDouble())
              .reduce((a, b) => a > b ? a : b);
    final today = list.isNotEmpty ? list.last : null;
    final sampleDate = today?['date']?.toString() ?? '';
    final todayDate = DateTime.now().toIso8601String().substring(0, 10);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (list.isEmpty) emptyState('暂无运动记录', '同步小米运动健康数据后，近七天的活动会显示在这里。'),
        if (sampleDate.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('数据日期：$sampleDate'),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _metric(
                  sampleDate == todayDate ? '今天步数' : '最近步数',
                  '${today?['steps'] ?? 0}',
                ),
                _metric(
                  '距离',
                  '${(((today?['distance_m'] ?? 0) as num) / 1000).toStringAsFixed(1)} km',
                ),
                _metric(
                  '消耗',
                  '${((today?['active_kcal'] ?? 0) as num).toStringAsFixed(0)} kcal',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '近 ${list.length} 天步数',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 150,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final e in list)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '${e['steps']}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Container(
                                height:
                                    6 +
                                    92 *
                                        (((e['steps'] ?? 0) as num) /
                                                (maxSteps > 0 ? maxSteps : 1))
                                            .toDouble(),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Color(0xFF7C3AED),
                                      Color(0xFF2563EB),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${e['date']}'.length >= 10
                                    ? '${'${e['date']}'.substring(8)}日'
                                    : '${e['date']}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '数据来源：小米运动健康 · 每晚 20:50 自动推送到邮箱',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _metric(String k, String v) => Expanded(
    child: Column(
      children: [
        Text(
          v,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 3),
        Text(k, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      ],
    ),
  );
}

class LobsterPage extends AsyncPage {
  const LobsterPage({super.key})
    : super(title: '网关管理', apiPath: '/api/hub/lobster');
  @override
  Widget buildBody(BuildContext c, dynamic d) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        color: d['active'] == true ? Colors.green.shade50 : Colors.red.shade50,
        child: ListTile(
          leading: Icon(
            d['active'] == true ? Icons.check_circle : Icons.error,
            color: d['active'] == true ? Colors.green : Colors.red,
            size: 32,
          ),
          title: Text(
            d['active'] == true ? '网关运行中' : '网关暂未运行',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: c,
            builder: (ctx) => AlertDialog(
              title: const Text('重启网关？'),
              content: const Text('重启期间服务会短暂中断，确认继续吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('确认重启'),
                ),
              ],
            ),
          );
          if (confirmed != true || !c.mounted) return;
          notice(c, '正在重启，请稍候…');
          try {
            final r = await apiPost('/api/hub/lobster/restart', {});
            if (c.mounted) {
              notice(c, r['ok'] == true ? '重启请求已完成，请刷新确认状态' : '重启未完成，请稍后重试');
            }
          } catch (_) {
            if (c.mounted) notice(c, '暂时无法重启，请检查网络后重试');
          }
        },
        icon: const Icon(Icons.restart_alt),
        label: const Text('一键重启网关'),
      ),
      const SizedBox(height: 12),
      ExpansionTile(
        title: const Text('查看服务诊断'),
        children: [
          for (final l in (d['detail'] as List?) ?? [])
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText('$l', style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    ],
  );
}

class AppkeyPage extends StatefulWidget {
  const AppkeyPage({super.key});
  @override
  State<AppkeyPage> createState() => _AppkeyPageState();
}

class _AppkeyPageState extends State<AppkeyPage> {
  final pw = TextEditingController();
  String? shown;
  String err = '';
  bool busy = false;
  @override
  void dispose() {
    pw.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (busy || pw.text.isEmpty) return;
    setState(() {
      busy = true;
      err = '';
    });
    try {
      final r = await apiPost('/api/hub/appkey/challenge', {
        'mode': 'password',
        'password': pw.text,
      });
      if (r['nonce'] == null) throw Exception('密码验证未通过，请重新输入');
      final d = await apiGet(
        '/api/hub/appkey?nonce=${Uri.encodeComponent('${r['nonce']}')}',
      );
      if (mounted) {
        setState(() {
          shown = d['appkey']?.toString();
          pw.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => err = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('激活密钥')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '激活密钥用于注册新账号。输入当前账号密码后查看，请妥善保管。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (shown == null) ...[
          TextField(
            controller: pw,
            obscureText: true,
            decoration: const InputDecoration(labelText: '账号密码'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : _verify,
            child: Text(busy ? '验证中…' : '验证并查看'),
          ),
          if (err.isNotEmpty)
            Text(err, style: const TextStyle(color: Colors.red)),
        ] else ...[
          const Text('激活密钥：', style: TextStyle(color: Colors.grey)),
          SelectableText(
            shown!,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 18),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => shown = null),
            child: const Text('隐藏密钥'),
          ),
          const Text(
            '注册新用户时使用',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ],
    ),
  );
}

class DreamPage extends AsyncPage {
  const DreamPage({super.key})
    : super(title: '项目进度', apiPath: '/api/hub/dream');
  @override
  Widget buildBody(BuildContext c, dynamic d) {
    final projects = (d['projects'] ?? []) as List;
    final md = (d['report_md'] ?? '') as String;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (projects.isEmpty) emptyState('暂无项目', '有项目运行后，这里显示进度与执行报告。'),
        for (final p in projects)
          Card(
            child: ListTile(
              title: Text(
                p['name'],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                p['progress'] ?? '',
                style: const TextStyle(fontSize: 13),
              ),
              trailing: _badge(p['status']),
            ),
          ),
        const SizedBox(height: 12),
        if (md.isNotEmpty)
          Card(
            child: ExpansionTile(
              title: const Text('查看完整进度报告'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    md,
                    style: const TextStyle(fontSize: 14, height: 1.7),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _badge(String? s) {
    final Color color;
    switch (s) {
      case 'done':
        color = Colors.green;
        break;
      case 'blocked':
        color = Colors.red;
        break;
      case 'stalled':
        color = Colors.amber;
        break;
      default:
        color = Colors.blue;
    }
    return Chip(
      backgroundColor: color.withValues(alpha: 0.08),
      label: Text(
        const {'done': '已完成', 'blocked': '需要处理', 'stalled': '已暂停'}[s] ?? '进行中',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

// ---------------- 设备控制台 ----------------
class ConsoleStatusPage extends StatefulWidget {
  const ConsoleStatusPage({super.key});
  @override
  State<ConsoleStatusPage> createState() => _ConsoleStatusPageState();
}

class _ConsoleStatusPageState extends State<ConsoleStatusPage> {
  dynamic d;
  String err = '';
  bool busy = true;
  bool powering = false;

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      busy = true;
      err = '';
    });
    try {
      d = await apiGet('/api/hub/console/status');
    } catch (e) {
      err = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _power(bool on) async {
    if (powering ||
        !await confirmOperation(
          context,
          '调整低功耗模式',
          on ? '将关闭一组闲置服务，相关功能会暂时不可用。确认开启？' : '将恢复此前关闭的闲置服务。确认关闭低功耗模式？',
        ) ||
        !mounted ||
        powering) {
      return;
    }
    setState(() => powering = true);
    try {
      final r = await apiPost('/api/hub/console/power', {
        'mode': on ? 'on' : 'off',
      });
      final ok = r['ok'] == true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? '低功耗模式已${on ? '开启' : '关闭'}' : '操作失败：${(r['detail'] ?? '')}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
    if (mounted) await load();
    if (mounted) setState(() => powering = false);
  }

  Future<void> _restartLobster() async {
    if (powering ||
        !await confirmOperation(context, '重启网关', '正在进行的对话可能短暂中断，确认重启？') ||
        !mounted ||
        powering) {
      return;
    }
    setState(() => powering = true);
    try {
      final r = await apiPost('/api/hub/lobster/restart', {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              r['ok'] == true
                  ? '龙虾网关已重启 ✅'
                  : '重启失败：${friendlyError(r['detail'] ?? 'unknown')}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
    if (mounted) setState(() => powering = false);
  }

  Color _svcColor(String? s) => s == 'active'
      ? Colors.green
      : (s == 'inactive' || s == 'failed' ? Colors.red : Colors.grey);

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('设备控制台'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '刷新',
          onPressed: busy || powering ? null : load,
        ),
      ],
    ),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : err.isNotEmpty
        ? errorState(context, err, load)
        : ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '106 服务器 · ${(d['UPT'] ?? '')}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '负载 ${(d['LOAD'] ?? '?')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        '内存 ${(d['MEM'] ?? '?')} MB · 交换空间 ${(d['SWAP'] ?? '?')} MB',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        '磁盘 ${(d['DISK'] ?? '?')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        '开机于 ${(d['SINCE'] ?? '?')}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: SwitchListTile(
                  value: (d['LOWPOWER'] ?? '') == 'active',
                  onChanged: powering ? null : _power,
                  title: const Text('低功耗模式', style: TextStyle(fontSize: 15)),
                  subtitle: Text(
                    powering ? '执行中…（约 1 分钟）' : '一键关闭/恢复 15 个闲置服务',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              ListTile(
                title: const Text(
                  '系统服务',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: TextButton(
                  onPressed: powering ? null : _restartLobster,
                  child: const Text('重启龙虾'),
                ),
              ),
              for (final e in {
                ...((d['services'] ?? {}) as Map),
                ...((d['user_services'] ?? {}) as Map),
              }.entries)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 5,
                    backgroundColor: _svcColor(e.value),
                  ),
                  title: Text(
                    e.key,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                  trailing: Text(
                    serviceStatusLabel(e.value),
                    style: TextStyle(fontSize: 11, color: _svcColor(e.value)),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConsoleLogPage(
                        unit: e.key,
                        isUser: (d['user_services'] ?? {}).containsKey(e.key),
                      ),
                    ),
                  ),
                ),
              for (final c in (d['containers'] ?? []) as List)
                ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.inventory_2,
                    size: 18,
                    color: Colors.blue,
                  ),
                  title: Text(
                    c.split(':').first,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                  subtitle: Text(
                    c.contains(':') ? c.split(':').last : '',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
  );
}

class ConsoleLogPage extends StatefulWidget {
  const ConsoleLogPage({super.key, required this.unit, this.isUser = false});
  final String unit;
  final bool isUser;
  @override
  State<ConsoleLogPage> createState() => _ConsoleLogPageState();
}

class _ConsoleLogPageState extends State<ConsoleLogPage> {
  String log = '加载中…';
  bool busy = false;
  Future<void> load() async {
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final r = await apiGet(
        '/api/hub/console/logs?unit=${widget.isUser ? 'user:' : ''}${widget.unit}&lines=300',
      );
      if (!mounted) return;
      setState(() => log = (r['log'] ?? '').toString());
    } catch (e) {
      if (!mounted) return;
      setState(() => log = '错误：$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.isUser ? "user:" : ""}${widget.unit} 日志'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '刷新',
          onPressed: busy ? null : load,
        ),
      ],
    ),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              log.isEmpty ? '（无日志）' : log,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ),
  );
}

// ---------------- 服务器终端（白名单 shell） ----------------
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});
  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  final ctl = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  final List<String> hist = [];
  int histIdx = 0;
  String out =
      '106 服务器终端（白名单命令）\n'
      'status=系统摘要 · 可用: uptime/df/free/systemctl/docker/journalctl/tail/crontab -l/ls/ip -brief\n'
      '↑↓ 键翻历史\n';
  bool busy = false;
  static const _quick = [
    'status',
    'uptime',
    'df -h',
    'free -m',
    'docker ps',
    'crontab -l',
    'ss -tlnp',
    'systemctl is-active nginx docker mysqld',
  ];

  Future<void> run(String cmd) async {
    cmd = cmd.trim();
    if (cmd.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      final r = await apiPost('/api/hub/console/exec', {'cmd': cmd});
      if (!mounted) return;
      final o = (r['out'] ?? '').toString();
      final e = (r['err'] ?? '').toString();
      if (r is Map && r['error'] != null) {
        setState(() => out += '\n\$ $cmd\n✗ ${r['error']}');
      } else {
        setState(() {
          out += '\n\$ $cmd\nexit=${r['rc']}\n$e$o';
          if (hist.isEmpty || hist.last != cmd) hist.add(cmd);
          histIdx = hist.length;
          ctl.clear();
        });
      }
    } catch (ex) {
      if (!mounted) return;
      setState(() => out += '\n\$ $cmd\n网络错误：$ex');
    }
    if (mounted) setState(() => busy = false);
    await Future.delayed(const Duration(milliseconds: 80));
    if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
  }

  @override
  void dispose() {
    ctl.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _nav(int dir) {
    if (hist.isEmpty) return;
    histIdx += dir;
    if (histIdx < 0) histIdx = 0;
    if (histIdx > hist.length) histIdx = hist.length;
    ctl.text = histIdx == hist.length ? '' : hist[histIdx];
    ctl.selection = TextSelection.collapsed(offset: ctl.text.length);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('服务器终端'),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: '清屏',
          onPressed: () => setState(() => out = ''),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              out,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final q in _quick)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(q, style: const TextStyle(fontSize: 11)),
                    onPressed: busy ? null : () => run(q),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: KeyboardListener(
                    focusNode: focus,
                    onKeyEvent: (ev) {
                      if (ev is KeyDownEvent) {
                        if (ev.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _nav(-1);
                        }
                        if (ev.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _nav(1);
                        }
                      }
                    },
                    child: TextField(
                      controller: ctl,
                      enabled: !busy,
                      onSubmitted: run,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: '输入命令，回车执行',
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '执行命令',
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: busy ? null : () => run(ctl.text),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ---------------- Minis 会话镜像 ----------------
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title, required this.note});
  final String title;
  final String note;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          note,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 15),
        ),
      ),
    ),
  );
}

// ---------------- 海淀医院 ----------------
class HdreportPage extends AsyncPage {
  const HdreportPage({super.key})
    : super(title: '医院报告', apiPath: '/api/hub/hdreport');
  @override
  Widget buildBody(BuildContext c, dynamic d) {
    final pdfs = (d['pdfs'] ?? []) as List;
    final age = d['session_age_hours'];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('报告更新状态'),
            subtitle: Text(
              age is num
                  ? '距上次登录 ${age.toStringAsFixed(1)} 小时。是否有效需实际刷新确认。'
                  : '尚无登录记录。',
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '需要更新报告时，请在 Mac 微信打开海淀医院小程序完成登录，再回来刷新。已保存的 PDF 可直接打开。',
            style: TextStyle(height: 1.6),
          ),
        ),
        Text(
          '已保存报告 · ${pdfs.length} 份',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (pdfs.isEmpty) emptyState('暂无报告', '完成医院小程序登录并获取报告后，在这里刷新。'),
        for (final f in pdfs)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const Icon(
                Icons.picture_as_pdf_outlined,
                color: Color(0xFF2563EB),
              ),
              title: Text('${f['name']}'),
              subtitle: Text(
                '${DateTime.fromMillisecondsSinceEpoch(((f['mtime'] ?? 0) as num).toInt() * 1000).toString().substring(0, 10)} · ${(((f['size'] ?? 0) as num) / 1024).toStringAsFixed(0)} KB',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => openPrivateFile(
                c,
                '/api/hub/hdreport/pdf?name=${Uri.encodeComponent('${f['name']}')}',
                '${f['name']}',
                'application/pdf',
              ),
            ),
          ),
      ],
    );
  }
}

class WerssPage extends AsyncPage {
  const WerssPage({super.key})
    : super(title: '公众号阅读', apiPath: '/api/hub/werss');
  @override
  Widget buildBody(BuildContext c, dynamic d) {
    final feeds = (d['feeds'] ?? []) as List,
        articles = (d['articles'] ?? []) as List;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '订阅 ${feeds.length} 个公众号',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '最新文章 ${articles.length} 篇 · 下拉刷新',
          style: const TextStyle(color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => openLink(c, runtimeConfig.subscriptionUrl),
          icon: const Icon(Icons.manage_accounts_outlined),
          label: const Text('管理订阅与微信授权'),
        ),
        if (feeds.isNotEmpty)
          ExpansionTile(
            title: const Text('已订阅公众号'),
            children: [
              for (final f in feeds)
                ListTile(
                  title: Text(
                    '${f is Map ? f['mp_name'] ?? f['name'] ?? '公众号' : f}',
                  ),
                ),
            ],
          ),
        if (articles.isEmpty)
          emptyState(
            '暂无文章',
            feeds.isEmpty ? '先打开订阅管理，完成微信授权并添加公众号。' : '公众号文章同步后会出现在这里，请稍后刷新。',
          ),
        for (final a in articles)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(
                '${a['title'] ?? '未命名文章'}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${a['mp_name'] ?? a['author'] ?? '公众号文章'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final url = '${a['url'] ?? a['link'] ?? ''}';
                if (url.startsWith('https://') || url.startsWith('http://')) {
                  openLink(c, url);
                } else {
                  notice(c, '这篇文章暂未提供阅读链接，请在订阅管理中查看');
                }
              },
            ),
          ),
      ],
    );
  }
}

String propertyLabel(String key) =>
    const {
      'on': '电源开关',
      'brightness': '亮度',
      'color-temperature': '色温',
      'temperature': '温度',
      'humidity': '湿度',
      'battery-level': '剩余电量',
      'mode': '运行模式',
      'fan-level': '风速',
      'target-temperature': '目标温度',
      'status': '运行状态',
      'volume': '音量',
      'power': '功率',
      'pm2.5-density': 'PM2.5 浓度',
      'filter-life-level': '滤芯余量',
    }[key] ??
    key;

// ---------------- 点评免费试（124 hub 转发 106 deals-ops -> MApi 匿名读）----------------
class DealsPage extends StatefulWidget {
  const DealsPage({super.key});
  @override
  State<DealsPage> createState() => _DealsPageState();
}

class _DealsPageState extends State<DealsPage> {
  List items = [];
  bool busy = true, vipOnly = false, applying = false;
  String? applyingId;
  String err = '', loginState = '';

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      busy = true;
      err = '';
    });
    try {
      final d = await apiGet(
        '/api/hub/deals/freetry/list?page=1&filter=${vipOnly ? 4 : 0}',
      );
      items = ((d['items'] ?? []) as List);
    } catch (e) {
      err = e.toString();
    }
    if (!mounted) return;
    try {
      final s = await apiGet('/api/hub/deals/status');
      loginState = s['login'] == true ? 'ok' : 'expired';
    } catch (_) {}
    if (mounted) setState(() => busy = false);
  }

  Future<void> _apply(Map it) async {
    if (applying || busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认报名'),
        content: Text('报名「${it['title']}」免费试？\n\n报名不等于中奖；若中奖请自行到店预约使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('报名'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || applying) return;
    setState(() {
      applying = true;
      applyingId = '${it['id']}';
    });
    String msg;
    try {
      final r = await apiClient
          .post(
            Uri.parse('$baseUrl/api/hub/deals/freetry/apply'),
            headers: {
              'Authorization': 'Bearer ${await token()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'offer_id': it['id']}),
          )
          .timeout(const Duration(seconds: 280));
      Map d = {};
      try {
        d = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      } catch (_) {}
      if (d['ok'] == true) {
        msg = (d['note'] == 'already_applied')
            ? '这个已经报过名啦'
            : '报名成功，开奖：${d['draw_date'] ?? d['draw'] ?? '见点评App'}';
      } else if (d['reason'] == 'login_required') {
        loginState = 'expired';
        msg = '点评授权已失效，请点击重新授权，完成后再报名';
      } else {
        msg = '报名未成功：${d['reason'] ?? d['error'] ?? r.statusCode}';
      }
    } catch (e) {
      msg = e is TimeoutException
          ? '等待报名结果超时，暂不确定是否成功。请先在点评查看报名记录，再决定是否重试。'
          : '报名未完成：${friendlyError(e)}';
    }
    if (!mounted) return;
    notice(context, msg);
    setState(() {
      applying = false;
      applyingId = null;
    });
    await load();
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  String _sub(Map it) {
    final parts = <String>[];
    if (it['distance'] != null) parts.add('${it['distance']}');
    if (it['cost'] != null) parts.add('价值¥${it['cost']}');
    if (it['applyCount'] != null) parts.add('${it['applyCount']}人已报');
    if (it['winCount'] != null) parts.add('奖${it['winCount']}份');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('点评免费试'),
      actions: [
        IconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
          onPressed: busy || applying ? null : load,
        ),
      ],
    ),
    body: Column(
      children: [
        if (loginState == 'expired')
          Card(
            color: const Color(0xFFFFF7ED),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('点评授权已失效，完成授权后即可报名。'),
                  TextButton.icon(
                    onPressed: () =>
                        openLink(context, runtimeConfig.dealsAuthorizationUrl),
                    icon: const Icon(Icons.login),
                    label: const Text('重新授权'),
                  ),
                ],
              ),
            ),
          ),
        if (applying)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 8),
                Text('正在提交报名，请稍候。结果返回前请勿重复报名。'),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: !vipOnly,
                onSelected: busy || applying
                    ? null
                    : (_) {
                        vipOnly = false;
                        load();
                      },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('橙V专享'),
                selected: vipOnly,
                onSelected: busy || applying
                    ? null
                    : (_) {
                        vipOnly = true;
                        load();
                      },
              ),
            ],
          ),
        ),
        Expanded(
          child: busy
              ? const Center(child: CircularProgressIndicator())
              : err.isNotEmpty
              ? errorState(context, err, load)
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(10),
                    children: [
                      if (items.isEmpty)
                        emptyState('暂时没有免费试活动', '切换筛选条件，或下拉刷新看看。'),
                      for (final it in items) _card(it),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _card(dynamic raw) {
    final it = raw as Map;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    '${it['pic'] ?? ''}',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 64,
                      height: 64,
                      child: Icon(Icons.storefront_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${it['title'] ?? '免费试活动'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _sub(it),
              style: const TextStyle(color: Color(0xFF64748B), height: 1.5),
            ),
            const SizedBox(height: 12),
            if (it['applied'] == true)
              const Chip(label: Text('已报名'))
            else if (it['vip'] == true)
              const Chip(label: Text('橙V专享'))
            else
              FilledButton(
                onPressed: applying || busy || loginState == 'expired'
                    ? null
                    : () => _apply(it),
                child: Text(applyingId == '${it['id']}' ? '提交中…' : '报名免费试'),
              ),
          ],
        ),
      ),
    );
  }
}
