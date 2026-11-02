part of 'main.dart';

class ToolEntry {
  const ToolEntry(
    this.id,
    this.title,
    this.description,
    this.category,
    this.icon,
    this.page,
  );
  final String id, title, description, category;
  final IconData icon;
  final Widget page;
}

IconData pluginIcon(String name) =>
    const <String, IconData>{
      'bike': Icons.directions_bike,
      'car': Icons.directions_car,
      'home': Icons.home_outlined,
      'health': Icons.favorite_border,
      'mail': Icons.mail_outline,
      'place': Icons.place,
      'list': Icons.list,
      'chart': Icons.bar_chart,
      'router': Icons.router_outlined,
      'night': Icons.nights_stay_outlined,
      'doc': Icons.description_outlined,
      'hub': Icons.hub_outlined,
      'article': Icons.article_outlined,
      'qr': Icons.qr_code_rounded,
      'gift': Icons.card_giftcard_outlined,
      'camera': Icons.photo_camera_outlined,
      'chat': Icons.forum_outlined,
      'desktop': Icons.desktop_windows_outlined,
      'terminal': Icons.terminal_outlined,
      'key': Icons.key_outlined,
    }[name] ??
    Icons.extension_outlined;

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.sceneMode = false});
  final bool sceneMode;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final search = TextEditingController();
  String query = '', category = '全部', scope = '';
  bool loading = true, saving = false;
  String? directoryError;
  DateTime? updatedAt;
  String directoryOrigin = '预置目录';
  List<Map<String, dynamic>> plugins = [];
  List<String> favorites = [], recent = [];

  String key(String kind) => 'dashboard.v2.$scope.$kind';
  List<ToolEntry> get tools => [
    for (final p in plugins)
      ToolEntry(
        'plugin:${p['id']}',
        '${p['title']}',
        '${p['subtitle'] ?? ''}',
        pluginCategories.contains(p['category'])
            ? '${p['category']}'
            : p['group'] == '服务管理'
            ? '开发运维'
            : '生活服务',
        pluginIcon('${p['icon']}'),
        pluginDestination(p),
      ),
  ];

  String directoryKey() => 'dashboard.v2.$scope.directory';

  @override
  void initState() {
    super.initState();
    boot();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> boot() async {
    final prefs = await _prefs();
    final session = await token();
    if (!mounted) return;
    // A session-to-account binding permits offline use without mixing accounts.
    final binding =
        'dashboard.account.${cryptoSha256(utf8.encode('$baseUrl|$session'))}';
    var identity = prefs.getString(binding);
    if (identity == null && session != null) {
      try {
        final me = await apiGet('/api/me');
        if (me is Map && me['username'] is String) {
          identity = cryptoSha256(utf8.encode('$baseUrl|${me['username']}'));
          if (mounted && await token() == session) {
            await prefs.setString(binding, identity);
          }
        }
      } catch (_) {}
    }
    if (!mounted || await token() != session) return;
    scope = identity ?? '';
    favorites = scope.isEmpty
        ? []
        : migratePluginIds(
            prefs.getStringList(key('favorites')) ??
                prefs.getStringList('dashboard.v1.$scope.favorites') ??
                [],
          );
    recent = scope.isEmpty
        ? []
        : migratePluginIds(
            prefs.getStringList(key('recent')) ??
                prefs.getStringList('dashboard.v1.$scope.recent') ??
                [],
          );
    if (scope.isNotEmpty) {
      await prefs.setStringList(key('favorites'), favorites);
      await prefs.setStringList(key('recent'), recent);
    }
    var restored = false;
    try {
      if (scope.isNotEmpty) {
        final cached = jsonDecode(prefs.getString(directoryKey()) ?? 'null');
        if (cached is Map && cached['schema_version'] == 2) {
          plugins = parseDirectory(cached['plugins']);
          updatedAt = DateTime.tryParse('${cached['at']}');
          directoryOrigin = '缓存目录';
          restored = true;
        }
      }
    } catch (_) {
      /* Ignore damaged directory metadata. */
    }
    if (!restored) {
      try {
        final packaged = await loadBundledPluginCatalog();
        plugins = parseDirectory(packaged['plugins']);
        directoryOrigin = '预置目录';
        updatedAt = null;
      } catch (_) {
        plugins = [];
      }
    }
    if (!mounted) return;
    setState(() {});
    await loadPlugins(initial: true);
  }

  List<Map<String, dynamic>> parseDirectory(
    dynamic raw, {
    bool serverAuthorized = false,
  }) {
    if (raw is! List) throw const FormatException('工具目录格式异常');
    final seen = <String>{};
    return [
      for (final p in raw)
        if (p is Map &&
            p['enabled'] != false &&
            (serverAuthorized ||
                (p['owner_only'] != true && p['id'] != 'server-monitor')) &&
            p['id'] is String &&
            RegExp(r'^[A-Za-z0-9-]{1,40}$').hasMatch(p['id']) &&
            '${p['id']}'.isNotEmpty &&
            p['title'] is String &&
            seen.add(p['id']))
          Map<String, dynamic>.from(p),
    ];
  }

  Future<void> loadPlugins({bool initial = false}) async {
    if (!mounted || (!initial && loading)) return;
    if (!initial && scope.isEmpty) {
      setState(() => loading = true);
      await boot();
      return;
    }
    setState(() {
      loading = true;
      directoryError = null;
    });
    final session = await token();
    try {
      final result = await apiGet('/api/hub/plugins?schema=2');
      if (result is! Map || result['schema_version'] != 2) {
        throw const FormatException('服务器插件目录版本不兼容，请稍后重试');
      }
      final next = parseDirectory(result['plugins'], serverAuthorized: true);
      if (!mounted || await token() != session) return;
      final now = DateTime.now();
      setState(() {
        plugins = next;
        updatedAt = now;
        directoryOrigin = '服务器目录';
      });
      try {
        if (scope.isNotEmpty) {
          await (await _prefs()).setString(
            directoryKey(),
            jsonEncode({
              'schema_version': 2,
              'plugins': next,
              'at': now.toIso8601String(),
            }),
          );
        }
      } catch (_) {
        if (mounted) notice(context, '工具已更新，但未能保存离线目录');
      }
    } catch (e) {
      if (mounted) setState(() => directoryError = friendlyError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> favorite(ToolEntry tool) async {
    if (saving || scope.isEmpty) return;
    setState(() => saving = true);
    final next = [...favorites];
    next.contains(tool.id) ? next.remove(tool.id) : next.add(tool.id);
    try {
      final ok = await (await _prefs()).setStringList(key('favorites'), next);
      if (!ok) throw Exception('保存失败');
      if (mounted) setState(() => favorites = next);
    } catch (_) {
      if (mounted) notice(context, '收藏未保存，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> open(ToolEntry tool) async {
    if (scope.isEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => tool.page),
      );
      return;
    }
    final next = [
      tool.id,
      ...recent.where((id) => id != tool.id),
    ].take(6).toList();
    setState(() => recent = next);
    try {
      await (await _prefs()).setStringList(key('recent'), next);
    } catch (_) {
      if (mounted) notice(context, '最近使用记录未保存');
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => tool.page));
  }

  Future<void> settings(String value) async {
    if (value == 'update') {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        notice(context, 'iOS 内测版本请在 TestFlight 中更新');
        return;
      }
      notice(context, '正在检查更新…');
      final data = await checkOta();
      if (!mounted) return;
      if (data == null) {
        notice(context, '暂时无法检查更新，请重试');
        return;
      }
      if ((int.tryParse('${data['versionCode']}') ?? 0) > currentVersionCode) {
        showUpdateDialog(context, data);
      } else {
        notice(context, '当前已是最新版本');
      }
    } else if (value == 'lock') {
      const channel = MethodChannel('site.zhangyue.vault/install');
      try {
        final enabled =
            await channel.invokeMethod<bool>('lockEnabled') ?? false;
        final verified = await channel.invokeMethod<bool>('bioAuth') ?? false;
        if (!mounted) return;
        if (!verified) {
          notice(context, '未完成系统验证，请先配置手机锁屏密码');
          return;
        }
        await channel.invokeMethod('setLock', {'off': enabled});
        if (mounted) notice(context, enabled ? '应用锁已关闭' : '应用锁已开启，下次进入需验证');
      } catch (_) {
        if (mounted) notice(context, '无法配置应用锁，请稍后重试');
      }
    } else if (value == 'logout') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('退出登录？'),
          content: const Text('再次使用时需要登录，收藏会为当前账号保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('退出登录'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await (await _prefs()).remove('token');
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        );
      }
    }
  }

  Widget tile(ToolEntry tool, {bool compact = false}) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => open(tool),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(tool.icon, color: const Color(0xFF2563EB), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 5),
                    Text(
                      tool.description,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!compact)
              IconButton(
                tooltip:
                    '${favorites.contains(tool.id) ? '取消收藏' : '收藏'}${tool.title}',
                onPressed: saving || scope.isEmpty
                    ? null
                    : () => favorite(tool),
                icon: Icon(
                  favorites.contains(tool.id)
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: favorites.contains(tool.id)
                      ? const Color(0xFFD97706)
                      : const Color(0xFF94A3B8),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget section(
    String title,
    List<ToolEntry> entries, {
    bool compact = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      LayoutBuilder(
        builder: (c, constraints) {
          final columns =
              constraints.maxWidth >= 680 &&
                  MediaQuery.textScalerOf(c).scale(16) <= 24
              ? 2
              : 1;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final tool in entries)
                SizedBox(
                  width: width,
                  child: tile(tool, compact: compact),
                ),
            ],
          );
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final all = tools;
    final filtered = all
        .where(
          (t) =>
              (category == '全部' || t.category == category) &&
              '${t.title} ${t.description}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    final idle = query.isEmpty && category == '全部';
    final stars = all.where((t) => favorites.contains(t.id)).toList();
    final history = [for (final id in recent) ...all.where((t) => t.id == id)];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sceneMode ? '场景与工具' : '乐天助手'),
        actions: [
          IconButton(
            tooltip: '刷新工具目录',
            onPressed: loading ? null : loadPlugins,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: '设置',
            onSelected: settings,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'lock', child: Text('应用锁')),
              const PopupMenuItem(value: 'update', child: Text('检查更新')),
              const PopupMenuItem(value: 'logout', child: Text('退出登录')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: loadPlugins,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: const Color(0xFF173D72),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '把日常，安排得更轻松',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              '设备、生活服务与工作记录，都在手边。',
                              style: TextStyle(
                                color: Color(0xFFDAE8FA),
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: search,
                        onChanged: (s) => setState(() => query = s.trim()),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: '搜索工具与服务',
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清除搜索',
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    search.clear();
                                    setState(() => query = '');
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final group in ['全部', '生活服务', '设备管理', '开发运维'])
                            ChoiceChip(
                              label: Text(group),
                              selected: group == category,
                              onSelected: (_) =>
                                  setState(() => category = group),
                            ),
                        ],
                      ),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (directoryError != null)
                        Card(
                          color: const Color(0xFFFFF7ED),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '工具目录暂时无法更新',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${directoryOrigin == '预置目录' ? '正在使用预置目录，联网后可更新。' : '正在显示上次保存的工具目录。'} ${directoryError!}',
                                  style: const TextStyle(height: 1.5),
                                ),
                                TextButton(
                                  onPressed: loadPlugins,
                                  child: const Text('重试'),
                                ),
                                if (directoryError!.contains('登录已过期'))
                                  TextButton(
                                    onPressed: () => settings('logout'),
                                    child: const Text('重新登录'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (!loading && scope.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextButton(
                            onPressed: loadPlugins,
                            child: const Text('账号信息暂未确认，点击重试后即可收藏'),
                          ),
                        ),
                      if (idle && stars.isNotEmpty) section('我的收藏', stars),
                      if (idle && history.isNotEmpty)
                        section('最近使用', history, compact: true),
                      if (filtered.isEmpty && !loading) ...[
                        emptyState('没有找到相关工具', '换个关键词，或切换到其他分类。'),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              search.clear();
                              setState(() {
                                query = '';
                                category = '全部';
                              });
                            },
                            child: const Text('清除搜索'),
                          ),
                        ),
                      ] else if (widget.sceneMode && idle) ...[
                        for (final scene in [
                          '出行',
                          '健康',
                          '居家与设备',
                          'AI与工作',
                          '阅读与资料',
                          '生活福利',
                          '服务管理',
                          '账号与连接',
                        ])
                          section(
                            scene,
                            filtered
                                .where((t) => toolScene(t.id) == scene)
                                .toList(),
                          ),
                      ] else
                        section(
                          query.isEmpty
                              ? '全部工具 · ${filtered.length}'
                              : '搜索结果 · ${filtered.length}',
                          filtered,
                        ),
                      const SizedBox(height: 24),
                      if (idle && stars.isEmpty)
                        const Text(
                          '点击工具右侧的星标，把常用入口放到首页。',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            height: 1.5,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        '乐天助手 $currentVersion · $directoryOrigin${updatedAt == null ? '' : ' · 目录更新 ${shortTime(updatedAt!)}'}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String shortTime(DateTime value) =>
    '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String toolScene(String id) => switch (id.replaceFirst('plugin:', '')) {
  'vehicles' => '出行',
  'health' || 'hospital' => '健康',
  'home' || 'route' => '居家与设备',
  'quota' || 'sessions' || 'dream' => 'AI与工作',
  'notes' || 'werss' => '阅读与资料',
  'deals' => '生活福利',
  'auth' || 'appkey' => '账号与连接',
  _ => '服务管理',
};
