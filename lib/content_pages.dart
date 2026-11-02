part of 'main.dart';

Widget qrImage(String source) {
  try {
    return Image.memory(
      base64Decode(source),
      height: 180,
      errorBuilder: (_, __, ___) => const Text('二维码暂时无法显示，请刷新'),
    );
  } catch (_) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text('二维码暂时无法显示，请刷新'),
    );
  }
}

Future<bool> confirmOperation(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;

Widget updateWarning(String error, VoidCallback retry) => Card(
  color: const Color(0xFFFFF7ED),
  child: Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '更新未完成，以下为上次获取的内容。\n${friendlyError(error)}',
          style: const TextStyle(height: 1.5),
        ),
        TextButton(onPressed: retry, child: const Text('重试')),
      ],
    ),
  ),
);

class PluginPage extends StatefulWidget {
  const PluginPage({super.key, required this.id, required this.title});
  final String id, title;
  @override
  State<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends State<PluginPage> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = false, acting = false;
  DateTime? fetched;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!mounted || loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await apiGet(
        '/api/hub/plugins/open?id=${Uri.encodeComponent(widget.id)}',
      );
      if (result is! Map || result['items'] is! List) {
        throw const FormatException('内容格式异常，请稍后重试');
      }
      if (mounted) {
        setState(() {
          data = Map<String, dynamic>.from(result);
          fetched = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> action(Map<String, dynamic> value) async {
    if (acting || loading) return;
    setState(() => acting = true);
    try {
      await runPluginAction(context, value, load);
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = data?['items'] as List? ?? [];
    final actions = data?['actions'] as List? ?? [];
    final footnote = '${data?['footnote'] ?? ''}';
    return Scaffold(
      appBar: AppBar(
        title: Text('${data?['title'] ?? widget.title}'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: loading || acting ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: data == null
          ? loading
                ? const Center(child: CircularProgressIndicator())
                : errorState(context, error ?? '无法加载内容', load)
          : RefreshIndicator(
              onRefresh: acting ? () async {} : load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  if (loading || acting)
                    const LinearProgressIndicator(minHeight: 2),
                  if (error != null) updateWarning(error!, load),
                  if (fetched != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '获取于 ${shortTime(fetched!)} · 下拉刷新',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  for (final act in actions.whereType<Map>())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FilledButton.icon(
                        onPressed: acting || loading
                            ? null
                            : () => action(Map<String, dynamic>.from(act)),
                        icon: Icon(
                          acting ? Icons.hourglass_top : Icons.arrow_forward,
                        ),
                        label: Text(
                          acting ? '处理中…' : '${act['label'] ?? '继续'}',
                        ),
                      ),
                    ),
                  if (items.isEmpty)
                    emptyState(
                      '${data?['empty_title'] ?? '这里还没有内容'}',
                      '${data?['empty_body'] ?? '下拉刷新，稍后再来看看。'}',
                    ),
                  for (final item in items.whereType<Map>())
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: itemCanOpen(item)
                            ? () => openPluginItem(context, item)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item['title'] ?? ''}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                ),
                              ),
                              if ('${item['subtitle'] ?? ''}'.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '${item['subtitle']}',
                                    style: const TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontWeight: FontWeight.w600,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              if ('${item['body'] ?? ''}'.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: SelectableText(
                                    '${item['body']}',
                                    style: const TextStyle(
                                      height: 1.65,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                ),
                              if (itemCanOpen(item))
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Row(
                                    children: [
                                      Icon(
                                        item['file'] != null
                                            ? Icons.file_download_outlined
                                            : Icons.open_in_new,
                                        size: 18,
                                        color: const Color(0xFF2563EB),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        item['file'] != null
                                            ? '下载并打开文件'
                                            : '打开原文',
                                        style: const TextStyle(
                                          color: Color(0xFF2563EB),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (footnote.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        footnote,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          height: 1.6,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});
  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  Map? data;
  String? dataSession;
  String query = '', error = '';
  bool loading = false;
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!mounted || loading) return;
    final captured = await token();
    if (!mounted) return;
    setState(() {
      if (dataSession != captured) data = null;
      dataSession = captured;
      loading = true;
      error = '';
    });
    try {
      final result = await apiGet('/api/hub/sessions');
      if (result is! Map || result['sessions'] is! List) {
        throw const FormatException('会话列表格式异常');
      }
      if (mounted && await token() == captured) setState(() => data = result);
    } catch (e) {
      if (mounted && await token() == captured) {
        setState(() {
          if (e is SessionExpired || e is AccessDenied) data = null;
          error = friendlyError(e);
        });
      }
    } finally {
      if (mounted) {
        final active = await token();
        if (mounted) {
          setState(() {
            if (active != captured) {
              data = null;
              error = '账号已变化，请刷新确认';
            }
            loading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = data?['sessions'] as List? ?? [];
    final shown = all
        .whereType<Map>()
        .where(
          (s) => '${s['title'] ?? ''} ${s['preview'] ?? ''}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('会话镜像'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: data == null
          ? loading
                ? const Center(child: CircularProgressIndicator())
                : errorState(context, error, load)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: TextField(
                    controller: search,
                    onChanged: (value) => setState(() => query = value.trim()),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: '搜索会话标题或内容',
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
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${shown.length} / ${all.length} 个会话${data?['generated_at'] == null ? '' : ' · 镜像更新 ${data!['generated_at']}'}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                if (loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (error.isNotEmpty) updateWarning(error, load),
                        if (shown.isEmpty)
                          emptyState(
                            query.isEmpty ? '还没有会话记录' : '没有匹配的会话',
                            query.isEmpty
                                ? 'Minis 对话同步后会出现在这里，下拉可以刷新。'
                                : '换个关键词，或清除搜索查看全部会话。',
                          ),
                        for (final item in shown)
                          Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              title: Text(
                                '${item['title'] ?? '未命名会话'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item['preview'] ?? ''}',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(height: 1.5),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${item['count'] ?? 0} 条消息${'${item['last_active'] ?? ''}'.isEmpty ? '' : ' · ${item['last_active']}'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SessionDetailPage(
                                    id: '${item['id']}',
                                    title: '${item['title'] ?? '会话详情'}',
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({super.key, required this.id, required this.title});
  final String id, title;
  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  Map? data;
  String? dataSession;
  String error = '';
  bool loading = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!mounted || loading) return;
    final captured = await token();
    if (!mounted) return;
    setState(() {
      if (dataSession != captured) data = null;
      dataSession = captured;
      loading = true;
      error = '';
    });
    try {
      final result = await apiGet(
        '/api/hub/sessions/detail?id=${Uri.encodeComponent(widget.id)}',
      );
      if (result is! Map || result['messages'] is! List) {
        throw const FormatException('会话内容格式异常');
      }
      if (mounted && await token() == captured) setState(() => data = result);
    } catch (e) {
      if (mounted && await token() == captured) {
        setState(() {
          if (e is SessionExpired || e is AccessDenied) data = null;
          error = friendlyError(e);
        });
      }
    } finally {
      if (mounted) {
        final active = await token();
        if (mounted) {
          setState(() {
            if (active != captured) {
              data = null;
              error = '账号已变化，请刷新确认';
            }
            loading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = data?['messages'] as List? ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: data == null
          ? loading
                ? const Center(child: CircularProgressIndicator())
                : errorState(context, error, load)
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  if (loading) const LinearProgressIndicator(minHeight: 2),
                  if (error.isNotEmpty) updateWarning(error, load),
                  if (messages.isEmpty)
                    emptyState('这段会话还没有消息', '下拉刷新，获取最新的镜像记录。'),
                  for (final m in messages.whereType<Map>())
                    Align(
                      alignment: m['role'] == 'user'
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
                        ),
                        decoration: BoxDecoration(
                          color: m['role'] == 'user'
                              ? const Color(0xFFE8F0FD)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${m['role'] == 'user' ? '你' : '助手'}${'${m['at'] ?? ''}'.isEmpty ? '' : ' · ${m['at']}'}',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              '${m['text'] ?? ''}',
                              style: const TextStyle(fontSize: 15, height: 1.6),
                            ),
                            if ((m['calls'] is List) &&
                                (m['calls'] as List).isNotEmpty)
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: Text(
                                  '工具调用 · ${(m['calls'] as List).length}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                children: [
                                  for (final call
                                      in (m['calls'] as List).whereType<Map>())
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: SelectableText(
                                        '${call['name']}\n${call['input'] ?? ''}',
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
