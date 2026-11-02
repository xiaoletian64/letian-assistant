part of 'main.dart';

RuntimeConfig runtimeConfig = const RuntimeConfig();

class RuntimeConfig {
  const RuntimeConfig({
    this.apiBaseUrl = 'https://example.invalid',
    this.updateManifestUrl = 'https://example.invalid/update.json',
    this.authorizationUrl = '',
    this.subscriptionUrl = '',
    this.dealsAuthorizationUrl = '',
    this.minisUrl = '',
    this.appStoreUrl = '',
    this.minisDownloadUrl = '',
    this.configured = false,
  });
  final String apiBaseUrl,
      updateManifestUrl,
      authorizationUrl,
      subscriptionUrl,
      dealsAuthorizationUrl,
      minisUrl,
      minisDownloadUrl,
      appStoreUrl;
  final bool configured;

  factory RuntimeConfig.fromJson(Map<String, dynamic> json) {
    const allowed = {
      'schema_version',
      'api_base_url',
      'update_manifest_url',
      'authorization_url',
      'subscription_url',
      'deals_authorization_url',
      'minis_url',
      'minis_download_url',
      'app_store_url',
    };
    if (json.keys.any((k) => !allowed.contains(k)) ||
        json['schema_version'] != 1) {
      throw const FormatException('配置格式不支持');
    }
    String readUrl(String key, {bool required = false}) {
      final value = json[key];
      if (value == null && !required) return '';
      if (value is! String) throw const FormatException('配置地址格式错误');
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.host == 'example.invalid') {
        throw const FormatException('配置需要有效的 HTTPS 地址');
      }
      if (key == 'api_base_url' && uri.path.isNotEmpty && uri.path != '/') {
        throw const FormatException('服务地址不能包含路径');
      }
      return key == 'api_base_url'
          ? value.replaceFirst(RegExp(r'/$'), '')
          : value;
    }

    if (json.containsKey('app_store_url')) readUrl('app_store_url');
    return RuntimeConfig(
      apiBaseUrl: readUrl('api_base_url', required: true),
      updateManifestUrl: readUrl('update_manifest_url', required: true),
      authorizationUrl: readUrl('authorization_url'),
      subscriptionUrl: readUrl('subscription_url'),
      dealsAuthorizationUrl: readUrl('deals_authorization_url'),
      minisUrl: readUrl('minis_url'),
      appStoreUrl: readUrl('app_store_url'),
      minisDownloadUrl: readUrl('minis_download_url'),
      configured: true,
    );
  }

  static Future<RuntimeConfig> load() async {
    try {
      final raw = jsonDecode(
        await rootBundle.loadString('assets/runtime-config.json'),
      );
      if (raw is! Map<String, dynamic>) return const RuntimeConfig();
      return RuntimeConfig.fromJson(raw);
    } catch (_) {
      return const RuntimeConfig();
    }
  }
}

class ConfigurationRequiredApp extends StatelessWidget {
  const ConfigurationRequiredApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.settings_outlined, size: 48),
                SizedBox(height: 24),
                Text(
                  '尚未配置服务',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 12),
                Text('这是通用构建版本，请使用已配置服务的安装包。', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
