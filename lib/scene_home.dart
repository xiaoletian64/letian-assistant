part of 'main.dart';

const sceneBlue = Color(0xFF1769FF);
const sceneInk = Color(0xFF122448);
const sceneMuted = Color(0xFF64748B);
const sceneAmber = Color(0xFFB45309);

class SceneShell extends StatefulWidget {
  const SceneShell({super.key});
  @override
  State<SceneShell> createState() => _SceneShellState();
}

class _SceneShellState extends State<SceneShell> with WidgetsBindingObserver {
  int tab = 0, generation = 0;
  String? session;
  String username = '', identityError = '', directoryError = '';
  bool refreshing = false;
  final Set<int> visited = {0};
  List<Map<String, dynamic>> directory = [];
  final Map<String, Map<String, dynamic>> values = {};
  final Map<String, String> errors = {};
  final Set<String> pending = {};
  final scroll = ScrollController();
  final vehicleKey = GlobalKey(), quotaKey = GlobalKey();
  String filter = '全部';

  bool allowed(String id) => directory.any((p) => p['id'] == id);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<bool> current(String? captured, int version) async =>
      mounted && generation == version && await token() == captured;
  Future<void> expire(String? captured, int version) async {
    final prefs = await _prefs();
    if (!mounted ||
        generation != version ||
        prefs.getString('token') != captured) {
      return;
    }
    generation++;
    values.clear();
    errors.clear();
    directory.clear();
    username = '';
    await clearAlertsBeforeLogout(context, captured);
    await prefs.remove('token');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  Future<dynamic> get(String path, String captured) async => decodeResponse(
    await apiClient
        .get(
          Uri.parse(baseUrl + path),
          headers: {'Authorization': 'Bearer $captured'},
        )
        .timeout(const Duration(seconds: 65)),
  );
  Future<void> refresh() async {
    final captured = await token();
    if (!mounted) return;
    if (refreshing && captured == session) return;
    final version = ++generation;
    if (captured != session) {
      values.clear();
      errors.clear();
      pending.clear();
      directory.clear();
      username = '';
      visited.clear();
      visited.add(0);
      tab = 0;
    }
    session = captured;
    setState(() {
      refreshing = true;
      identityError = '';
      directoryError = '';
    });
    if (captured == null || captured.isEmpty) {
      await expire(captured, version);
      return;
    }
    var identityChecked = false;
    try {
      final me = sceneMap(await get('/api/me', captured));
      if (!await current(captured, version)) return;
      if (me['username'] is! String || '${me['username']}'.isEmpty) {
        throw const FormatException('账号信息格式异常');
      }
      identityChecked = true;
      setState(() => username = '${me['username']}');
      await (await _prefs()).setString(
        'dashboard.account.${cryptoSha256(utf8.encode('$baseUrl|$captured'))}',
        cryptoSha256(utf8.encode('$baseUrl|$username')),
      );
      if (!await current(captured, version)) return;
      final catalog = sceneMap(
        await get('/api/hub/plugins?schema=2', captured),
      );
      if (catalog['schema_version'] != 2 || catalog['plugins'] is! List) {
        throw const FormatException('工具目录版本不兼容');
      }
      if (!await current(captured, version)) return;
      setState(() {
        directory = sceneList(
          catalog['plugins'],
        ).where((p) => p['enabled'] != false).toList();
        values.removeWhere((key, _) => !allowed(key));
        errors.removeWhere((key, _) => !allowed(key));
      });
      unawaited(syncNotificationBinding().catchError((_) {}));
      unawaited(openPendingNotification(captured, version));
      const paths = {
        'quota': '/api/quota/summary',
        'vehicles': '/api/hub/vehicles',
        'sessions': '/api/hub/sessions',
        'auth': '/api/qr/all',
      };
      await Future.wait(
        paths.entries
            .where((p) => allowed(p.key))
            .map((p) => load(p.key, p.value, captured, version)),
      );
    } on SessionExpired {
      await expire(captured, version);
    } catch (e) {
      if (await current(captured, version)) {
        setState(() {
          if (e is AccessDenied) {
            values.clear();
            errors.clear();
            directory.clear();
            visited.remove(2);
          }
          if (!identityChecked) {
            identityError = friendlyError(e);
          } else {
            directoryError = friendlyError(e);
          }
        });
      }
    } finally {
      if (mounted && generation == version) {
        if (await token() != captured) {
          setState(() {
            values.clear();
            errors.clear();
            pending.clear();
            directory.clear();
            username = '';
            refreshing = false;
            identityError = '账号已变化，请刷新确认';
            visited.clear();
            visited.add(0);
            tab = 0;
          });
        } else {
          setState(() => refreshing = false);
        }
      }
    }
  }

  Future<void> load(
    String id,
    String path,
    String captured,
    int version,
  ) async {
    if (!await current(captured, version)) return;
    setState(() {
      pending.add(id);
      errors.remove(id);
    });
    try {
      final data = await get(path, captured);
      final map = sceneMap(data);
      final valid = switch (id) {
        'quota' =>
          map['accounts'] is Map || map['push'] is Map || map['errors'] is Map,
        'vehicles' => map['vehicles'] is List,
        'sessions' => map['sessions'] is List,
        'auth' => data is Map && !map.containsKey('error'),
        _ => false,
      };
      if (!valid) throw const FormatException('来源数据格式异常');
      if (await current(captured, version) && allowed(id)) {
        setState(() => values[id] = map);
      }
    } on SessionExpired {
      await expire(captured, version);
    } catch (e) {
      if (await current(captured, version) && allowed(id)) {
        setState(() {
          if (e is AccessDenied) {
            values.clear();
            directory.clear();
            visited.remove(2);
            directoryError = friendlyError(e);
          } else {
            errors[id] = friendlyError(e);
          }
        });
      }
    } finally {
      if (await current(captured, version)) setState(() => pending.remove(id));
    }
  }

  void changeTab(int next) => setState(() {
    tab = next;
    visited.add(next);
  });
  Future<void> openPendingNotification(String captured, int version) async {
    try {
      final event = await consumeNotificationOpenEvent();
      if (event == null || !await current(captured, version)) return;
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationsPage()),
      );
    } catch (_) {
      /* Notification access never blocks normal startup. */
    }
  }

  Future<void> open(String id) async {
    if (!allowed(id)) return;
    final descriptor = directory.firstWhere((p) => p['id'] == id);
    final page = id == 'quota'
        ? const SceneDataPage(kind: 'quota')
        : id == 'vehicles'
        ? const SceneDataPage(kind: 'vehicles')
        : pluginDestination(descriptor);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) refresh();
  }

  Widget status(String id) {
    if (errors[id] != null) {
      return inlineMessage(
        '${values[id] == null ? '' : '显示上次数据 · '}${errors[id]}',
        refresh,
      );
    }
    if (pending.contains(id)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    return const SizedBox.shrink();
  }

  List<VehicleStatus> get cars => sceneList(
    values['vehicles']?['vehicles'],
  ).map(VehicleStatus.new).toList();
  List<QuotaAccount> get accounts => quotaAccounts(values['quota'] ?? {});
  Widget homepage() {
    final alerts = <Widget>[];
    for (final car in cars) {
      final days = car.daysToExpiry(DateTime.now());
      if (days != null && days <= 7) {
        alerts.add(
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 36),
              foregroundColor: sceneAmber,
            ),
            onPressed: () => Scrollable.ensureVisible(
              vehicleKey.currentContext!,
              duration: const Duration(milliseconds: 200),
            ),
            icon: const Icon(Icons.event_available),
            label: Text('${car.name} ${car.renewalSummary(DateTime.now())}'),
          ),
        );
      }
    }
    for (final a in accounts) {
      if (!a.stale &&
          a.error.isEmpty &&
          a.windows.any((w) => w.remaining != null && w.remaining! <= 15)) {
        alerts.add(
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 36),
              foregroundColor: sceneAmber,
            ),
            onPressed: () => Scrollable.ensureVisible(
              quotaKey.currentContext!,
              duration: const Duration(milliseconds: 200),
            ),
            icon: const Icon(Icons.data_usage),
            label: Text('${a.platform} 额度偏低'),
          ),
        );
      }
    }
    bool show(String scene) => filter == '全部' || filter == scene;
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF8FF), Color(0xFFDAEEFF), Color(0xFFF2FAFF)],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: refresh,
          child: SingleChildScrollView(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              12,
              MediaQuery.paddingOf(context).top + 12,
              12,
              20,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipOval(
                          child: Image.asset(
                            'assets/images/avatar.png',
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const CircleAvatar(
                              radius: 22,
                              backgroundColor: Color(0xFFBDE2FF),
                              child: Icon(Icons.person, color: sceneBlue),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '乐天助手',
                                style: TextStyle(
                                  color: sceneInk,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color:
                                          username.isEmpty ||
                                              identityError.isNotEmpty
                                          ? sceneMuted
                                          : const Color(0xFF12BF87),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      '${username.isEmpty ? '账号待确认' : username} · ${identityError.isNotEmpty
                                          ? '身份待确认'
                                          : username.isEmpty
                                          ? '核对中'
                                          : '已登录'}',
                                      style: const TextStyle(
                                        color: sceneMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '账号与连接',
                          onPressed: () => changeTab(3),
                          icon: const Icon(
                            Icons.settings_outlined,
                            color: sceneInk,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '关心的事，一眼掌握',
                      style: TextStyle(
                        color: sceneInk,
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (identityError.isNotEmpty)
                      inlineMessage('账号暂未确认 · $identityError', refresh),
                    if (directoryError.isNotEmpty)
                      inlineMessage('目录未更新 · $directoryError', refresh),
                    if (refreshing)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final s in ['全部', '出行', 'AI工作', '健康', '居家'])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                showCheckmark: false,
                                selectedColor: sceneBlue,
                                backgroundColor: const Color(0xFFF8FCFF),
                                shape: const StadiumBorder(
                                  side: BorderSide(color: Color(0xFFD6E8FF)),
                                ),
                                labelStyle: TextStyle(
                                  color: filter == s ? Colors.white : sceneInk,
                                ),
                                label: Text(s),
                                selected: filter == s,
                                onSelected: (_) => setState(() => filter = s),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (alerts.isNotEmpty && filter == '全部')
                      sceneSurface(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFEFD6), Color(0xFFFFF9F0)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🔔 需要关注 ${alerts.length} 项',
                                style: const TextStyle(
                                  color: sceneAmber,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final alert in alerts)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 12,
                                        ),
                                        child: alert,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (allowed('server-monitor') && filter == '全部')
                      sceneSurface(
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            key: const ValueKey('server-monitor-entry'),
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.monitor_heart_outlined,
                              color: sceneBlue,
                            ),
                            title: const Text(
                              '服务器监控',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text('查看服务器运行状态与资源使用情况'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => open('server-monitor'),
                          ),
                        ),
                      ),
                    if (allowed('lobsterchat') &&
                        (filter == '全部' || filter == 'AI工作'))
                      sceneSurface(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.smart_toy_outlined,
                            color: sceneBlue,
                          ),
                          title: const Text(
                            '和龙虾对话',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text('发消息给106上的龙虾'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => open('lobsterchat'),
                        ),
                      ),
                    if (allowed('vehicles') && show('出行'))
                      Container(
                        key: vehicleKey,
                        child: Column(
                          children: [
                            status('vehicles'),
                            if (cars.isEmpty)
                              sceneSurface(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    sceneHeading(Icons.electric_moped, '我的车'),
                                    const SizedBox(height: 12),
                                    Text(
                                      pending.contains('vehicles')
                                          ? '正在获取车辆状态…'
                                          : '暂无可展示车辆',
                                    ),
                                    TextButton(
                                      onPressed: () => open('vehicles'),
                                      child: const Text('查看车辆'),
                                    ),
                                  ],
                                ),
                              ),
                            for (final car in cars)
                              VehicleStatusCard(
                                vehicle: car,
                                onDetails: () => open('vehicles'),
                              ),
                          ],
                        ),
                      ),
                    if (allowed('quota') && show('AI工作'))
                      KeyedSubtree(
                        key: quotaKey,
                        child: sceneSurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              sceneHeading(
                                Icons.dns_outlined,
                                '模型额度',
                                action: () => open('quota'),
                              ),
                              const Text(
                                '全部平台 · 每个账号、每个周期分别展示',
                                style: TextStyle(
                                  color: sceneMuted,
                                  fontSize: 12,
                                ),
                              ),
                              status('quota'),
                              if (accounts.isEmpty &&
                                  !pending.contains('quota'))
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('暂未获取额度，点击刷新重试'),
                                ),
                              ...quotaPlatformCards(accounts),
                              const TiboChallengeCard(),
                            ],
                          ),
                        ),
                      ),
                    if (allowed('hospital') && show('健康'))
                      sceneSurface(
                        child: ListTile(
                          key: const ValueKey('hospital-entry'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.description_outlined,
                            color: sceneBlue,
                          ),
                          title: const Text('医院报告'),
                          subtitle: const Text('查看已同步的检查报告'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => open('hospital'),
                        ),
                      ),
                    if (allowed('sessions') && show('AI工作'))
                      sceneSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            sceneHeading(
                              Icons.forum_outlined,
                              '最近会话',
                              action: () => changeTab(2),
                            ),
                            status('sessions'),
                            ...sceneList(values['sessions']?['sessions'])
                                .take(1)
                                .map(
                                  (s) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text('${s['title'] ?? '未命名会话'}'),
                                    subtitle: Text(
                                      'Minis 镜像 · ${s['last_active'] ?? '活动时间未提供'}',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => SessionDetailPage(
                                          id: '${s['id']}',
                                          title: '${s['title'] ?? '会话详情'}',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            if (sceneList(
                              values['sessions']?['sessions'],
                            ).isEmpty)
                              const Text('尚无同步记录，可进入会话页查看同步状态'),
                            Text(
                              '镜像来源更新：${values['sessions']?['generated_at'] ?? '未提供'}',
                              style: const TextStyle(
                                color: sceneMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (allowed('home') && show('居家'))
                      sceneSurface(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.home_outlined,
                            color: sceneBlue,
                          ),
                          title: const Text('居家与设备'),
                          subtitle: const Text('查看设备状态、场景与网络限制'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => open('home'),
                        ),
                      ),
                    if (directory.isEmpty && !refreshing)
                      emptyState('暂无可用场景', '当前账号没有可展示的服务，或目录暂时不可用。'),
                    TextButton.icon(
                      onPressed: () => changeTab(1),
                      icon: const Icon(Icons.grid_view),
                      label: const Text('查看全部场景与工具'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget mypage() => Scaffold(
    appBar: AppBar(title: const Text('我的')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        sceneSurface(
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFE8F1FF),
                foregroundColor: sceneBlue,
                radius: 28,
                child: Icon(Icons.person_outline, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username.isEmpty ? '账号待确认' : username,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      identityError.isNotEmpty
                          ? '身份暂未确认'
                          : username.isEmpty
                          ? '正在核对登录状态'
                          : '当前登录账号',
                      style: const TextStyle(color: sceneMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (identityError.isNotEmpty) inlineMessage(identityError, refresh),
        sceneSurface(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('应用锁'),
                subtitle: const Text('使用手机锁屏验证保护应用'),
                onTap: () => accountSetting(context, 'lock'),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('通知提醒'),
                subtitle: const Text('额度、余额与服务器状态'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsPage()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.system_update),
                title: const Text('检查更新'),
                subtitle: const Text('乐天助手 $currentVersion'),
                onTap: () => accountSetting(context, 'update'),
              ),
            ],
          ),
        ),
        if (allowed('auth'))
          sceneSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sceneHeading(Icons.link, '平台连接', action: () => open('auth')),
                status('auth'),
                for (final e in {'douyin': '抖音', 'dianping': '大众点评'}.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(e.value),
                    subtitle: Text(
                      values['auth'] == null || values['auth']?[e.key] is! Map
                          ? '状态未获取'
                          : sceneMap(values['auth']?[e.key])['error'] != null
                          ? '暂时无法读取状态'
                          : sceneMap(values['auth']?[e.key])['logged_in'] ==
                                true
                          ? '已连接'
                          : '待授权或未连接',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open('auth'),
                  ),
                TextButton(
                  onPressed: () => open('auth'),
                  child: const Text('全部平台与扫码授权'),
                ),
              ],
            ),
          ),
        if (allowed('sessions'))
          sceneSurface(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.forum_outlined, color: sceneBlue),
              title: const Text('会话镜像'),
              subtitle: Text(
                '来源：Minis\n镜像更新：${values['sessions']?['generated_at'] ?? '未提供'}\n这里只读查看同步记录',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => changeTab(2),
            ),
          ),
        if (allowed('appkey'))
          sceneSurface(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key_outlined),
              title: const Text('激活密钥'),
              subtitle: const Text('保留账号密码二次验证'),
              onTap: () => open('appkey'),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final yes = await confirmLogout(context);
            if (yes) await expire(session, generation);
          },
          icon: const Icon(Icons.logout),
          label: const Text('退出登录'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: tab,
      children: [
        homepage(),
        visited.contains(1)
            ? const HomePage(sceneMode: true)
            : const SizedBox(),
        visited.contains(2) && (allowed('sessions') || allowed('lobsterchat'))
            ? ConversationHub(
                key: ValueKey(session),
                chat: allowed('lobsterchat'),
                mirror: allowed('sessions'),
              )
            : Scaffold(
                appBar: AppBar(title: const Text('会话')),
                body: emptyState('暂无可用会话镜像', '当前账号未开通此服务或目录尚未加载。'),
              ),
        mypage(),
      ],
    ),
    bottomNavigationBar: NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? sceneBlue
                : const Color(0xFF52628A),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            color: states.contains(WidgetState.selected) ? sceneBlue : sceneInk,
          ),
        ),
      ),
      child: NavigationBar(
        height: 64,
        selectedIndex: tab,
        onDestinationSelected: changeTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: '场景',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: '会话',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    ),
  );
}

Widget inlineMessage(String message, VoidCallback retry) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(color: sceneAmber)),
          TextButton(onPressed: retry, child: const Text('重试')),
        ],
      ),
    ),
  ),
);
Widget sceneSurface({required Widget child}) => Padding(
  padding: const EdgeInsets.only(top: 7),
  child: Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFFDDE8F6)),
    ),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: double.infinity,
      child: Padding(padding: const EdgeInsets.all(9), child: child),
    ),
  ),
);
Widget sceneHeading(IconData icon, String title, {VoidCallback? action}) => Row(
  children: [
    Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF3FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: sceneBlue),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: sceneInk,
        ),
      ),
    ),
    if (action != null)
      IconButton(
        tooltip: '查看$title',
        onPressed: action,
        icon: const Icon(Icons.chevron_right),
      ),
  ],
);

// Group only the platform presentation. Distinct source accounts and windows
// remain intact: the quota API does not provide a shared account identity.
List<Widget> quotaPlatformCards(List<QuotaAccount> accounts) {
  final platforms = <String, List<QuotaAccount>>{};
  for (final account in accounts) {
    platforms.putIfAbsent(account.platform, () => []).add(account);
  }
  return platforms.entries.map((entry) {
    final separatePush =
        entry.key == 'Cursor' &&
        entry.value.any((account) => account.source == '直接采集');
    final primary = entry.value.where(
      (account) => !separatePush || account.source != '推送采集',
    );
    final pushed = entry.value.where((account) => account.source == '推送采集');
    final attention = entry.value
        .where((account) => account.unavailable || account.low)
        .length;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('quota-platform-${entry.key}'),
        initiallyExpanded: false,
        maintainState: false,
        leading: quotaBrandMark(entry.key),
        title: Text(entry.key),
        subtitle: Text(
          '${entry.value.length} 个来源账号 · 点击查看额度'
          '${attention > 0 ? ' · $attention 个需关注' : ''}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [
          if (separatePush) const Text('主来源：直接采集'),
          for (final account in primary)
            QuotaAccountCard(account: account, showPlatform: false),
          if (separatePush && pushed.isNotEmpty)
            ExpansionTile(
              title: Text('推送来源详情（${pushed.length} 个账号）'),
              subtitle: const Text('备用观测 · 账号身份未核对，不合并或累加'),
              children: [
                for (final account in pushed)
                  QuotaAccountCard(account: account, showPlatform: false),
              ],
            ),
        ],
      ),
    );
  }).toList();
}

class QuotaAccountCard extends StatelessWidget {
  const QuotaAccountCard({
    super.key,
    required this.account,
    this.showPlatform = true,
  });
  final QuotaAccount account;
  final bool showPlatform;

  Widget windowBody(QuotaWindow window, {bool historical = false}) {
    final color = historical
        ? sceneMuted
        : window.remaining != null && window.remaining! <= 15
        ? sceneAmber
        : sceneBlue;
    final primary = window.summary == null
        ? window.value
        : window.remaining == null
        ? window.summary!
        : '剩余 ${window.remaining!.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}%';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            window.period,
            style: const TextStyle(fontSize: 12, color: sceneMuted),
          ),
          const SizedBox(height: 3),
          Text(
            historical ? window.value : primary,
            style: TextStyle(
              fontSize: historical ? 14 : 23,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (!historical && window.remaining != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: window.remaining! / 100,
                  minHeight: 6,
                  color: color,
                  backgroundColor: const Color(0xFFDFEAFC),
                ),
              ),
            ),
          if (!historical && window.summary != null && window.remaining != null)
            Text(window.summary!, style: TextStyle(fontSize: 13, color: color)),
          Text(
            window.reset,
            style: const TextStyle(fontSize: 11, color: sceneMuted),
          ),
          if (!historical && window.summary != null)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                '查看完整额度',
                style: TextStyle(fontSize: 12, color: sceneMuted),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    window.value,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unavailable = account.unavailable;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE4EEFA)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (showPlatform) quotaBrandMark(account.platform),
                if (showPlatform)
                  Text(
                    account.platform,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: sceneInk,
                    ),
                  ),
                if (unavailable || account.low)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      account.status,
                      style: const TextStyle(fontSize: 11, color: sceneAmber),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              account.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: sceneInk,
              ),
            ),
            Text(
              '来源更新 ${account.observed} · 北京时间',
              style: const TextStyle(fontSize: 11, color: sceneMuted),
            ),
            if (unavailable) ...[
              const SizedBox(height: 12),
              Text(
                account.balanceOnly ||
                        const [
                          'DeepSeek',
                          '腾讯云',
                          'JEV',
                        ].contains(account.platform)
                    ? '当前余额未知'
                    : '当前额度未知',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: sceneInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                account.error.isNotEmpty
                    ? account.error
                    : account.sourceDate == null
                    ? '未取得有效的来源时间，请刷新后再查看。'
                    : '尚未取得有效的新数据，请刷新后再查看。',
                style: const TextStyle(fontSize: 12, color: sceneMuted),
              ),
              if (account.error.isNotEmpty &&
                  account.stale &&
                  account.sourceDate != null)
                const Text(
                  '上次数据已过期',
                  style: TextStyle(fontSize: 11, color: sceneMuted),
                ),
              if (account.windows.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text(
                    '查看上次观测记录',
                    style: TextStyle(fontSize: 12, color: sceneMuted),
                  ),
                  subtitle: const Text(
                    '历史记录，当前可用额度未确认',
                    style: TextStyle(fontSize: 11, color: sceneMuted),
                  ),
                  children: [
                    for (final window in account.windows)
                      windowBody(window, historical: true),
                  ],
                ),
            ] else ...[
              for (final window in account.windows) windowBody(window),
            ],
          ],
        ),
      ),
    );
  }
}

class VehicleStatusCard extends StatelessWidget {
  const VehicleStatusCard({
    super.key,
    required this.vehicle,
    required this.onDetails,
  });
  final VehicleStatus vehicle;
  final VoidCallback onDetails;
  @override
  Widget build(BuildContext context) {
    final days = vehicle.daysToExpiry(DateTime.now());
    final warning = days != null && days <= 7;
    return sceneSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.electric_moped, color: sceneInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '我的车 · ${vehicle.name}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: sceneInk,
                  ),
                ),
              ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0FAEC),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'ϟ ${vehicle.charging}',
                    style: const TextStyle(
                      color: Color(0xFF00A964),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.stale ? '上次上报电量' : '电量',
                      style: const TextStyle(color: sceneMuted),
                    ),
                    Text(
                      vehicle.battery == null
                          ? '未知'
                          : '${sceneDecimal(vehicle.battery!)}%',
                      style: const TextStyle(
                        color: sceneInk,
                        fontSize: 46,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (vehicle.battery != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: vehicle.battery! / 100,
                          minHeight: 8,
                          color: const Color(0xFF15B888),
                          backgroundColor: const Color(0xFFE1EBFA),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: MediaQuery.sizeOf(context).width < 360 ? 96 : 135,
                height: 126,
                child:
                    vehicle.raw['image_url'] is String &&
                        '${vehicle.raw['image_url']}'.startsWith('https://')
                    ? Image.network(
                        '${vehicle.raw['image_url']}',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.electric_moped,
                          size: 64,
                          color: sceneBlue,
                        ),
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: Image.asset(
                              'assets/images/commuter-scooter.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.electric_moped,
                                size: 80,
                                color: sceneBlue,
                              ),
                            ),
                          ),
                          const Text(
                            '车辆配图',
                            style: TextStyle(fontSize: 9, color: sceneMuted),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.bolt, color: Color(0xFF00B77D), size: 20),
              const Text(
                '充电状态',
                style: TextStyle(color: sceneMuted, fontSize: 12),
              ),
              Text(
                vehicle.charging,
                style: const TextStyle(
                  color: Color(0xFF00A964),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (vehicle.charging != '充电中')
                Text(
                  vehicle.state,
                  style: const TextStyle(color: sceneMuted, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.location_on, color: sceneInk, size: 19),
              Text(
                vehicle.address,
                style: const TextStyle(fontSize: 13, color: sceneInk),
              ),
              Text(
                '定位更新 ${vehicle.locationTime}',
                style: const TextStyle(fontSize: 11, color: sceneMuted),
              ),
            ],
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: warning
                  ? const Color(0xFFFFF3DF)
                  : const Color(0xFFF0F5FD),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${vehicle.serviceName} · ${vehicle.renewalSummary(DateTime.now())}',
                  style: TextStyle(
                    color: warning ? sceneAmber : sceneInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  vehicle.expiryText,
                  style: const TextStyle(fontSize: 12, color: sceneMuted),
                ),
                if (vehicle.expiry == null && days != null)
                  const Text(
                    '剩余天数来自平台，不推算精确到期日期',
                    style: TextStyle(fontSize: 12, color: sceneMuted),
                  ),
                Text(
                  '服务查询：${sceneTime(vehicle.raw['observed_at'], missing: '查询时间未提供')}',
                  style: const TextStyle(fontSize: 12, color: sceneMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '车辆上报：${vehicle.reportTime}${vehicle.stale ? '\n上次数据，当前状态可能已变化' : ''}',
            style: const TextStyle(fontSize: 12, color: sceneMuted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (c) => SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(vehicle.address),
                          Text('定位：${vehicle.locationTime}'),
                          const Text('位置为最后一次上报，可能已变化。'),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                icon: const Icon(Icons.place_outlined),
                label: const Text('查看位置'),
              ),
              OutlinedButton.icon(
                onPressed: onDetails,
                icon: const Icon(Icons.event_outlined),
                label: const Text('续期详情'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SceneDataPage extends StatefulWidget {
  const SceneDataPage({super.key, required this.kind});
  final String kind;
  @override
  State<SceneDataPage> createState() => _SceneDataPageState();
}

class _SceneDataPageState extends State<SceneDataPage> {
  String? dataSession;
  Map<String, dynamic>? data;
  String error = '';
  bool loading = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
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
        widget.kind == 'quota' ? '/api/quota/summary' : '/api/hub/vehicles',
      );
      if (mounted && await token() == captured) {
        setState(() => data = sceneMap(result));
      }
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.kind == 'quota' ? '模型额度' : '我的车'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: data == null && error.isNotEmpty
        ? errorState(context, error, load)
        : RefreshIndicator(
            onRefresh: load,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (loading) const LinearProgressIndicator(),
                  if (error.isNotEmpty) inlineMessage(error, load),
                  if (widget.kind == 'quota')
                    ...quotaPlatformCards(quotaAccounts(data ?? {}))
                  else
                    ...sceneList(data?['vehicles']).map(
                      (v) => VehicleStatusCard(
                        vehicle: VehicleStatus(v),
                        onDetails: () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (c) {
                            final car = VehicleStatus(v);
                            return SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      car.serviceName,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(car.expiryText),
                                    Text(
                                      '平台剩余天数：${car.daysToExpiry(DateTime.now()) ?? '未提供'}',
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('如需续期，请在对应车辆官方应用内查看服务与办理。'),
                                    TextButton(
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('关闭'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  if (!loading &&
                      data != null &&
                      (widget.kind == 'quota'
                          ? quotaAccounts(data!).isEmpty
                          : sceneList(data!['vehicles']).isEmpty))
                    emptyState('暂无数据', '来源暂未提供记录，下拉可重试。'),
                ],
              ),
            ),
          ),
  );
}

Future<bool> confirmLogout(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('收藏为当前账号保留，再次使用需要登录。'),
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
    ) ==
    true;
Future<void> accountSetting(BuildContext context, String kind) async {
  if (kind == 'update') {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      notice(context, 'iOS 内测版本请在 TestFlight 中更新');
      return;
    }
    notice(context, '正在检查更新…');
    final data = await checkOta();
    if (!context.mounted) return;
    if (data == null) {
      notice(context, '暂时无法检查更新，请重试');
    } else if ((int.tryParse('${data['versionCode']}') ?? 0) >
        currentVersionCode) {
      showUpdateDialog(context, data);
    } else {
      notice(context, '当前已是最新版本');
    }
    return;
  }
  try {
    const channel = MethodChannel('site.zhangyue.vault/install');
    final enabled = await channel.invokeMethod<bool>('lockEnabled') ?? false;
    final verified = await channel.invokeMethod<bool>('bioAuth') ?? false;
    if (!context.mounted) return;
    if (!verified) {
      notice(context, '未完成系统验证，请先配置手机锁屏密码');
      return;
    }
    await channel.invokeMethod('setLock', {'off': enabled});
    if (context.mounted) notice(context, enabled ? '应用锁已关闭' : '应用锁已开启，下次进入需验证');
  } catch (_) {
    if (context.mounted) notice(context, '无法配置应用锁，请稍后重试');
  }
}

IconData quotaPlatformIcon(String platform) => switch (platform) {
  'Codex' => Icons.auto_awesome,
  'GLM' => Icons.grain,
  'MiMo' => Icons.waves,
  'OpenCode' => Icons.code,
  '腾讯云' => Icons.cloud_outlined,
  'Cursor' => Icons.near_me_outlined,
  'DeepSeek' => Icons.water,
  'GitHub Actions' => Icons.account_tree_outlined,
  _ => Icons.data_usage,
};

Widget quotaBrandMark(String platform) {
  const files = {
    'Codex': 'openai',
    'GLM': 'glm',
    'MiMo': 'mimo',
    'OpenCode': 'opencode',
    'DeepSeek': 'deepseek',
    'Cursor': 'cursor',
    'GitHub Actions': 'github',
  };
  final name = files[platform];
  if (name == null) {
    return Icon(quotaPlatformIcon(platform), size: 26, color: sceneBlue);
  }
  return Image.asset(
    'assets/images/$name.png',
    width: 26,
    height: 26,
    fit: BoxFit.contain,
    errorBuilder: (_, __, ___) =>
        Icon(quotaPlatformIcon(platform), size: 26, color: sceneBlue),
  );
}
