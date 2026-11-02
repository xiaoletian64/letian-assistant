part of 'main.dart';

class IosBackupPage extends StatefulWidget {
  const IosBackupPage({super.key});
  @override
  State<IosBackupPage> createState() => _IosBackupPageState();
}

class _IosBackupPageState extends State<IosBackupPage> {
  static const channel = MethodChannel('site.zhangyue.vault/sync');
  bool busy = false;
  String directory = '', status = '';
  Future<void> choose() async {
    if (busy) return;
    setState(() {
      busy = true;
      status = '';
    });
    try {
      final selected = await channel.invokeMethod('pickTree');
      if (!mounted) return;
      if (selected is Map && selected['name'] is String) {
        setState(() => directory = selected['name']);
      } else {
        setState(() => status = '已取消选择');
      }
    } catch (_) {
      if (mounted) setState(() => status = '无法读取目录，请重新选择并允许访问。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> upload() async {
    if (busy || directory.isEmpty) return;
    setState(() {
      busy = true;
      status = '正在上传备份，请保留原始文件…';
    });
    final account = await token();
    try {
      if (account == null) throw SessionExpired();
      final result = await channel.invokeMethod('syncBackup', {
        'server': baseUrl,
        'token': account,
      });
      if (!mounted || await token() != account) return;
      if (result is! Map) throw const FormatException();
      setState(
        () => status =
            '上传 ${result['uploaded'] ?? '未知'} 份，失败 ${result['failed'] ?? '未知'} 份。请在云端核对内容后再删除原始备份。',
      );
    } catch (_) {
      if (mounted) setState(() => status = '备份未完成，请检查目录权限和网络后重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Minis 备份与云端内容')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '先从 Minis 导出备份，再选择包含 .minisbak 文件的目录。iOS 仅访问您主动授权的文件，不会读取其他应用的私有目录。',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: busy ? null : choose,
          icon: const Icon(Icons.folder_open),
          label: Text(directory.isEmpty ? '选择备份目录' : directory),
        ),
        FilledButton.icon(
          onPressed: busy || directory.isEmpty ? null : upload,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('上传所选目录的备份'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(status),
          ),
        const Divider(),
        const Text('云端会话', style: TextStyle(fontWeight: FontWeight.w600)),
        const Text('查看当前乐天账号已同步的内容。上传备份与完整恢复到另一设备需分别核对。'),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SessionsPage()),
          ),
          child: const Text('查看会话镜像'),
        ),
        if (runtimeConfig.minisUrl.isNotEmpty)
          TextButton(
            onPressed: () => openLink(context, runtimeConfig.minisUrl),
            child: const Text('打开 Minis 入口'),
          ),
      ],
    ),
  );
}
