part of 'main.dart';

Map<String, dynamic>? _bundledPluginCatalog;
Future<Map<String, dynamic>> loadBundledPluginCatalog() async {
  if (_bundledPluginCatalog != null) return _bundledPluginCatalog!;
  final value = jsonDecode(
    await rootBundle
        .loadString('assets/plugins.json')
        .timeout(const Duration(seconds: 3)),
  );
  if (value is! Map ||
      value['schema_version'] != 2 ||
      value['plugins'] is! List) {
    throw const FormatException('预置插件目录不可用');
  }
  _bundledPluginCatalog = Map<String, dynamic>.from(value);
  return _bundledPluginCatalog!;
}

const pluginCategories = ['生活服务', '设备管理', '开发运维'];

List<String> migratePluginIds(List<String> ids) => ids
    .map((id) => id.startsWith('plugin:') ? id : 'plugin:$id')
    .toSet()
    .toList();

Widget pluginDestination(Map<String, dynamic> descriptor) {
  final minimum = int.tryParse('${descriptor['min_client_code'] ?? 0}') ?? 0;
  if (minimum > currentVersionCode) {
    return PluginUpgradePage(title: '${descriptor['title']}');
  }
  switch (descriptor['renderer'] ?? 'content') {
    case 'content':
      if (descriptor['id'] == 'quota' || descriptor['id'] == 'vehicles') {
        return SceneDataPage(kind: '${descriptor['id']}');
      }
      return PluginPage(
        id: '${descriptor['id']}',
        title: '${descriptor['title']}',
      );
    case 'server-monitor':
      return const ServerMonitorPage();
    case 'devices':
      return const MihomePage();
    case 'authorization':
      return const QrPage();
    case 'deals':
      return const DealsPage();
    case 'camera':
      return const CameraPage();
    case 'chat':
      return const LobsterChatPage();
    case 'sessions':
      return const SessionsPage();
    case 'console':
      return const ConsoleStatusPage();
    case 'terminal':
      return const ShellPage();
    case 'appkey':
      return const AppkeyPage();
    default:
      return PluginUpgradePage(title: '${descriptor['title']}');
  }
}

class PluginUpgradePage extends StatelessWidget {
  const PluginUpgradePage({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        emptyState('此插件需要更新客户端', '当前版本尚不支持这个插件，请返回首页，在设置中检查更新。'),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回首页'),
        ),
      ],
    ),
  );
}
