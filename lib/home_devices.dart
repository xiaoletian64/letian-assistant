part of 'main.dart';

const _homeInk = Color(0xFF243F35);
const _homeGreen = Color(0xFF537D65);
const _homePaper = Color(0xFFF4F5F0);

IconData deviceTypeIcon(String category) {
  const icons = <String, IconData>{
    'light': Icons.lightbulb_outline_rounded,
    'switch': Icons.toggle_on_outlined,
    'plug': Icons.power_outlined,
    'powerstrip': Icons.electrical_services_outlined,
    'acpartner': Icons.ac_unit_rounded,
    'airc': Icons.ac_unit_rounded,
    'aircondition': Icons.ac_unit_rounded,
    'camera': Icons.videocam_outlined,
    'cateye': Icons.doorbell_outlined,
    'fan': Icons.air_rounded,
    'airpurifier': Icons.air_rounded,
    'humidifier': Icons.water_drop_outlined,
    'waterheater': Icons.hot_tub_rounded,
    'vacuum': Icons.cleaning_services_outlined,
    'wifispeaker': Icons.speaker_outlined,
    'tv': Icons.tv_outlined,
    'tvbox': Icons.connected_tv_outlined,
    'projector': Icons.video_camera_back_outlined,
    'router': Icons.router_outlined,
    'gateway': Icons.hub_outlined,
    'kettle': Icons.kitchen_outlined,
    'cooker': Icons.rice_bowl_outlined,
    'ihcooker': Icons.soup_kitchen_outlined,
    'fryer': Icons.soup_kitchen_outlined,
    'hood': Icons.countertops_outlined,
    'waterpuri': Icons.water_drop_outlined,
    'pet_waterer': Icons.pets_outlined,
    'pettoy': Icons.pets_outlined,
    'scales': Icons.monitor_weight_outlined,
    'watch': Icons.watch_outlined,
    'bracelet': Icons.watch_outlined,
    'tracker': Icons.location_on_outlined,
    'sensor_ht': Icons.thermostat_outlined,
    'thermo': Icons.thermostat_outlined,
    'sensor_magnet': Icons.sensor_door_outlined,
    'sensor_motion': Icons.sensors_outlined,
    'sensor_occupy': Icons.sensors_outlined,
    'senpres': Icons.sensors_outlined,
    'motion': Icons.sensors_outlined,
    'sensor_switch': Icons.touch_app_outlined,
    'remote': Icons.settings_remote_outlined,
    'sensor_cube': Icons.view_in_ar_outlined,
    'sen_ill': Icons.wb_sunny_outlined,
    'flood': Icons.water_outlined,
    'clock': Icons.schedule_rounded,
    'diffuser': Icons.spa_outlined,
    'toothbrush': Icons.clean_hands_outlined,
    'printer': Icons.print_outlined,
    'radio': Icons.radio_outlined,
    'mosq': Icons.bug_report_outlined,
    'ir': Icons.settings_remote_outlined,
  };
  return icons[category] ?? Icons.devices_other_outlined;
}

class DeviceArtwork extends StatefulWidget {
  const DeviceArtwork({super.key, required this.device, this.size = 76});
  final Map device;
  final double size;
  @override
  State<DeviceArtwork> createState() => _DeviceArtworkState();
}

class _DeviceArtworkState extends State<DeviceArtwork> {
  Future<List<int>?>? image;
  String? loadedPath;
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(covariant DeviceArtwork old) {
    super.didUpdateWidget(old);
    if (loadedPath != widget.device['art']?['path']) {
      _read();
    }
  }

  void _read() {
    final path = widget.device['art']?['path'];
    loadedPath = path is String ? path : null;
    if (path is String && path.startsWith('/api/hub/mihome/icons/')) {
      image = () async {
        try {
          final response = await http
              .get(
                Uri.parse(baseUrl + path),
                headers: {'Authorization': 'Bearer ${await token()}'},
              )
              .timeout(const Duration(seconds: 15));
          return response.statusCode == 200 ? response.bodyBytes : null;
        } catch (_) {
          return null;
        }
      }();
    } else {
      image = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: const Color(0xFFECF1E9),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Icon(
        deviceTypeIcon('${widget.device['category'] ?? ''}'),
        size: widget.size * .53,
        color: _homeGreen,
      ),
    );
    if (image == null) return fallback;
    return FutureBuilder<List<int>?>(
      future: image,
      builder: (context, snapshot) {
        if (snapshot.data == null) return fallback;
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.memory(
            Uint8List.fromList(snapshot.data!),
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          ),
        );
      },
    );
  }
}

class HomeDeviceCard extends StatelessWidget {
  const HomeDeviceCard({
    super.key,
    required this.device,
    required this.onOpen,
    required this.onSettings,
  });
  final Map device;
  final VoidCallback onOpen, onSettings;
  @override
  Widget build(BuildContext context) {
    final online = device['online'] == true;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DeviceArtwork(device: device, size: 66),
                    ),
                  ),
                  IconButton(
                    tooltip: '设备设置',
                    onPressed: onSettings,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      device['favorite'] == true
                          ? Icons.star_rounded
                          : Icons.more_horiz_rounded,
                      color: device['favorite'] == true
                          ? const Color(0xFFB6924B)
                          : const Color(0xFF8B978F),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '${device['name'] ?? '智能设备'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _homeInk,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: online ? _homeGreen : const Color(0xFFADB4AE),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      online
                          ? '${device['room'] == '未分房间' ? device['category_label'] : device['room']}'
                          : '设备离线',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF77847A),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> sendHomeCommand(Map<String, dynamic> payload) async {
  final confirmation = await apiPost('/api/hub/mihome/confirm', payload);
  if (confirmation is! Map || confirmation['token'] == null) {
    throw Exception('设备暂时没有响应，请稍后重试');
  }
  final result = await apiPost('/api/hub/mihome/cmd', {
    'token': confirmation['token'],
  });
  if (result is Map && (result['ok'] == true || result['code'] == 0)) {
    return true;
  }
  throw Exception('操作未完成，请刷新设备状态后重试');
}

class MihomePage extends StatefulWidget {
  const MihomePage({super.key});
  @override
  State<MihomePage> createState() => _MihomePageState();
}

class _MihomePageState extends State<MihomePage> {
  List<Map<String, dynamic>> devices = [], scenes = [], homes = [];
  bool loading = true, refreshing = false, showOffline = true, polling = false;
  String error = '', query = '', area = '全部', category = '全部';
  String? runningScene;
  String homeId = '';
  List<Map<String, dynamic>> get homeScenes =>
      scenes.where((s) => s['home_id'] == homeId).toList();
  List<Map<String, dynamic>> get homeDevices =>
      devices.where((d) => homeId.isEmpty || d['home_id'] == homeId).toList();
  Timer? timer;
  final requested = <String>{};
  List<String> pending = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (refreshing) return;
    if (mounted) setState(() => refreshing = true);
    try {
      final result = await apiGet('/api/hub/mihome/ui');
      final all = ((result['devices'] ?? []) as List)
          .map((d) => Map<String, dynamic>.from(d))
          .toList();
      List<Map<String, dynamic>> sceneList = scenes;
      try {
        final response = await apiGet('/api/hub/mihome/scenes');
        sceneList = ((response['scenes'] ?? []) as List)
            .map((d) => Map<String, dynamic>.from(d))
            .toList();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        devices = all;
        homes = ((result['homes'] ?? []) as List)
            .map((h) => Map<String, dynamic>.from(h))
            .toList();
        if (!homes.any((h) => h['id'] == homeId)) {
          homeId = homes.isEmpty ? '' : '${homes.first['id']}';
        }
        scenes = sceneList;
        error = '';
        loading = false;
        refreshing = false;
      });
      await requestArt();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
          refreshing = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get shown {
    final values = homeDevices
        .where(
          (d) =>
              (showOffline || d['online'] == true) &&
              (area == '全部' ||
                  (area == '常用' ? d['favorite'] == true : d['room'] == area)) &&
              (category == '全部' || d['category_label'] == category) &&
              ('${d['name']} ${d['room']} ${d['category_label']}')
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return values;
  }

  Future<void> requestArt() async {
    final models = shown
        .where(
          (d) =>
              d['art']?['status'] != 'ready' && !requested.contains(d['model']),
        )
        .map((d) => '${d['model']}')
        .toSet()
        .take(8)
        .toList();
    if (models.isEmpty) return;
    requested.addAll(models);
    try {
      final response = await apiPost('/api/hub/mihome/icons/ensure', {
        'models': models,
      });
      final jobs = (response['jobs'] ?? []) as List;
      for (final model in models) {
        final art = jobs
            .cast<Map>()
            .where(
              (j) =>
                  j['key'] ==
                  devices.firstWhere((d) => d['model'] == model)['art']?['key'],
            )
            .firstOrNull;
        if (art != null) {
          for (final d in devices.where((d) => d['model'] == model)) {
            d['art'] = Map<String, dynamic>.from(art);
          }
        }
      }
      pending = devices
          .where((d) => ['queued', 'generating'].contains(d['art']?['status']))
          .map((d) => '${d['model']}')
          .toSet()
          .take(8)
          .toList();
      if (!mounted) return;
      setState(() {});
      if (pending.isNotEmpty) {
        timer ??= Timer.periodic(const Duration(seconds: 8), (_) => pollArt());
      }
    } catch (_) {}
  }

  Future<void> pollArt() async {
    if (polling || pending.isEmpty || !mounted) return;
    polling = true;
    try {
      final response = await apiGet(
        '/api/hub/mihome/icons/status?models=${Uri.encodeComponent(pending.join(','))}',
      );
      if (!mounted) return;
      for (final job in (response['jobs'] ?? []) as List) {
        for (final d in devices.where((d) => d['model'] == job['model'])) {
          d['art'] = Map<String, dynamic>.from(job);
        }
      }
      pending = devices
          .where((d) => ['queued', 'generating'].contains(d['art']?['status']))
          .map((d) => '${d['model']}')
          .toSet()
          .take(8)
          .toList();
      setState(() {});
      if (pending.isEmpty) {
        timer?.cancel();
        timer = null;
      }
    } catch (_) {
    } finally {
      polling = false;
    }
  }

  void selectArea(String value) {
    setState(() => area = value);
    requestArt();
  }

  Future<void> settings(Map<String, dynamic> device) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${device['name']}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.home_outlined),
              title: Text('${device['home'] ?? ''}'),
              subtitle: const Text('米家中的家庭'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.meeting_room_outlined),
              title: Text('${device['room']}'),
              subtitle: const Text('米家中的房间'),
            ),
            const SizedBox(height: 12),
            const Text('名称和房间与米家同步。修改后，下拉刷新即可更新。'),
          ],
        ),
      ),
    );
  }

  Future<void> runScene(Map scene) async {
    if (runningScene != null) return;
    setState(() => runningScene = '${scene['id']}');
    try {
      await sendHomeCommand({
        'kind': 'scene',
        'name': '${scene['name']}',
        'scene_id': '${scene['id']}',
      });
      if (mounted) notice(context, '已运行「${scene['name']}」');
    } catch (_) {
      if (mounted) notice(context, '场景暂时没有响应，请稍后重试');
    } finally {
      if (mounted) setState(() => runningScene = null);
    }
  }

  Future<void> allScenes() async {
    final selected = await showModalBottomSheet<Map>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '我的场景',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final scene in homeScenes)
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text('${scene['name']}'),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: () => Navigator.pop(context, scene),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) runScene(selected);
  }

  @override
  Widget build(BuildContext context) {
    final selectedHome = homes.where((h) => h['id'] == homeId).firstOrNull;
    final rooms = ((selectedHome?['rooms'] ?? []) as List)
        .map((r) => '${r['name']}')
        .toSet()
        .toList();
    final categories =
        homeDevices.map((d) => '${d['category_label']}').toSet().toList()
          ..sort();
    final visible = shown;
    return Scaffold(
      backgroundColor: _homePaper,
      appBar: AppBar(
        backgroundColor: _homePaper,
        title: homes.isEmpty
            ? const Text('我的家')
            : DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: homeId,
                  isExpanded: true,
                  items: homes
                      .map(
                        (h) => DropdownMenuItem(
                          value: '${h['id']}',
                          child: Text(
                            '${h['name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      homeId = value;
                      area = '全部';
                      category = '全部';
                    });
                    requestArt();
                  },
                ),
              ),
        actions: [
          IconButton(
            tooltip: '刷新设备',
            onPressed: refreshing ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty && devices.isEmpty
          ? errorState(context, error, load)
          : RefreshIndicator(
              onRefresh: load,
              child: LayoutBuilder(
                builder: (context, constraints) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    if (error.isNotEmpty) updateWarning(error, load),
                    Text(
                      '${homeDevices.where((d) => d['online'] == true).length} 台设备在线 · ${homeScenes.length} 个生活场景',
                      style: const TextStyle(
                        color: Color(0xFF77847A),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (homeScenes.isNotEmpty) ...[
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            '让家听懂你',
                            style: TextStyle(
                              color: _homeInk,
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton(
                            onPressed: allScenes,
                            child: const Text('全部场景'),
                          ),
                        ],
                      ),
                      SizedBox(
                        height:
                            112 *
                            MediaQuery.textScalerOf(
                              context,
                            ).scale(1).clamp(1.0, 2.5),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: homeScenes.take(5).length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final scene = homeScenes[index];
                            return SizedBox(
                              width:
                                  132 *
                                  MediaQuery.textScalerOf(
                                    context,
                                  ).scale(1).clamp(1.0, 1.8),
                              child: Material(
                                color: index.isEven
                                    ? const Color(0xFFE5ECDD)
                                    : const Color(0xFFEDE8DE),
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: runningScene == null
                                      ? () => runScene(scene)
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          runningScene == '${scene['id']}'
                                              ? Icons.hourglass_top_rounded
                                              : Icons.auto_awesome_outlined,
                                          color: _homeGreen,
                                          size: 24,
                                        ),
                                        const Spacer(),
                                        Text(
                                          '${scene['name']}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: _homeInk,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    TextField(
                      onChanged: (value) =>
                          setState(() => query = value.trim()),
                      decoration: InputDecoration(
                        hintText: '找找家里的设备',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final name in ['全部', '常用', ...rooms])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(name),
                                selected: area == name,
                                onSelected: (_) => selectArea(name),
                                selectedColor: const Color(0xFFDFE9DA),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            area == '全部' ? '家里的设备' : area,
                            style: const TextStyle(
                              color: _homeInk,
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: '按设备类型筛选',
                          initialValue: category,
                          onSelected: (value) {
                            setState(() => category = value);
                            requestArt();
                          },
                          itemBuilder: (_) => [
                            for (final value in ['全部', ...categories])
                              PopupMenuItem(
                                value: value,
                                child: Text(value == '全部' ? '所有类型' : value),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Text(
                                  category == '全部' ? '类型' : category,
                                  style: const TextStyle(color: _homeGreen),
                                ),
                                const Icon(
                                  Icons.expand_more,
                                  color: _homeGreen,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        PopupMenuButton<bool>(
                          tooltip: '显示离线设备',
                          onSelected: (v) => setState(() => showOffline = v),
                          itemBuilder: (_) => [
                            CheckedPopupMenuItem(
                              value: false,
                              checked: !showOffline,
                              child: const Text('只看在线'),
                            ),
                            CheckedPopupMenuItem(
                              value: true,
                              checked: showOffline,
                              child: const Text('包含离线'),
                            ),
                          ],
                          icon: const Icon(
                            Icons.tune_rounded,
                            color: _homeGreen,
                          ),
                        ),
                      ],
                    ),
                    if (rooms.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          '家庭、房间和常用设备均与米家同步。',
                          style: TextStyle(
                            color: Color(0xFF77847A),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (visible.isEmpty)
                      emptyState(
                        area == '常用' ? '还没有常用设备' : '这里暂时没有设备',
                        area == '常用' ? '在米家中添加常用设备后，下拉刷新。' : '换个房间、类型或搜索词试试。',
                      ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visible.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            constraints.maxWidth < 380 ||
                                MediaQuery.textScalerOf(context).scale(1) > 1.5
                            ? 1
                            : constraints.maxWidth > 900
                            ? 4
                            : constraints.maxWidth > 650
                            ? 3
                            : 2,
                        mainAxisExtent:
                            180 *
                            MediaQuery.textScalerOf(
                              context,
                            ).scale(1).clamp(1.0, 2.5),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemBuilder: (context, index) {
                        final device = visible[index];
                        return HomeDeviceCard(
                          key: ValueKey(device['did']),
                          device: device,
                          onSettings: () => settings(device),
                          onOpen: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HomeDevicePage(device: device),
                            ),
                          ),
                        );
                      },
                    ),
                    if (pending.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: Text(
                          '正在为设备补充插图，不影响正常控制。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF77847A),
                            fontSize: 12,
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

String devicePropertyName(Map property) {
  final raw = '${property['prop']}';
  final plain = raw.replaceAll(RegExp(r'-\d+(-\d+)?$'), '');
  final known = propertyLabel(plain);
  if (known != plain) return known;
  const names = {
    'mode': '运行模式',
    'fan-level': '风速',
    'speed-level': '档位',
    'target-temperature': '目标温度',
    'volume': '音量',
    'relative-humidity': '湿度',
    'temperature': '温度',
    'humidity': '湿度',
    'pm2.5-density': 'PM2.5',
    'battery': '电量',
    'battery-level': '电量',
    'filter-life-level': '滤芯余量',
    'status': '运行状态',
    'sleep-mode': '睡眠模式',
    'child-lock': '童锁',
    'led': '指示灯',
    'alarm': '提示音',
    'eco': '节能模式',
    'horizontal-swing': '左右扫风',
    'vertical-swing': '上下扫风',
    'off-delay-time': '定时关闭',
    'delay-off': '定时关闭',
    'heat-level': '加热档位',
    'target-humidity': '目标湿度',
    'water-level': '水位',
    'electric-current': '电流',
    'voltage': '电压',
    'power-consumption': '用电量',
    'illumination': '光照',
    'motion-state': '人体感应',
    'contact-state': '门窗状态',
    'fault': '设备提醒',
    'cleaning-mode': '清扫模式',
    'suction-state': '吸力',
    'wind-mode': '送风模式',
    'drying-level': '烘干档位',
  };
  if (names.containsKey(plain)) return names[plain]!;
  final description = '${property['description'] ?? ''}'.split('/').last.trim();
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(description)) return description;
  return '其他设置（$raw）';
}

String deviceValue(Map p) {
  if (p['error'] != null) return '暂时读不到';
  final value = p['value'];
  if (value == null) return '暂无数据';
  final choices = (p['choices'] is List ? p['choices'] : []) as List;
  for (final choice in choices) {
    if ('${choice['value']}' == '$value') {
      return choiceName(choice['description']);
    }
  }
  if (value is bool) return value ? '开启' : '关闭';
  if (value is String) {
    final plain = '${p['prop']}'.replaceAll(RegExp(r'-\d+(-\d+)?$'), '');
    const enums = {
      'mode',
      'status',
      'cleaning-mode',
      'wind-mode',
      'fan-level',
      'speed-level',
      'suction-state',
      'motion-state',
      'contact-state',
    };
    return enums.contains(plain) ? choiceName(value) : value;
  }
  final key = '${p['prop']}';
  final unit = key.contains('temperature')
      ? (key.contains('color') ? ' K' : ' °C')
      : key.contains('humidity') ||
            key.contains('brightness') ||
            key.contains('battery') ||
            key.contains('life-level')
      ? ' %'
      : key.contains('power-consumption')
      ? ' kWh'
      : key == 'volume'
      ? ' %'
      : '';
  return '${value is num && value == value.roundToDouble() ? value.toInt() : value}$unit';
}

class DeviceControlPanel extends StatefulWidget {
  const DeviceControlPanel({
    super.key,
    required this.property,
    required this.busy,
    required this.onWrite,
  });
  final Map property;
  final bool busy;
  final Future<bool> Function(dynamic) onWrite;
  @override
  State<DeviceControlPanel> createState() => _DeviceControlPanelState();
}

class _DeviceControlPanelState extends State<DeviceControlPanel> {
  double? preview;
  @override
  void didUpdateWidget(covariant DeviceControlPanel old) {
    super.didUpdateWidget(old);
    if (old.property['value'] != widget.property['value']) preview = null;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.property;
    final value = p['value'];
    final choices = p['choices'] is List ? p['choices'] as List : [];
    final range = p['range'] is List ? p['range'] as List : [];
    final slider =
        range.length >= 2 &&
        range[0] is num &&
        range[1] is num &&
        (range[1] as num) > (range[0] as num) &&
        value is num;
    final name = devicePropertyName(p);
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: _homeInk,
                    ),
                  ),
                ),
                if (value is bool || p['type'] == 'bool')
                  Switch(
                    value: value == true,
                    onChanged: widget.busy ? null : (v) => widget.onWrite(v),
                    activeThumbColor: _homeGreen,
                  )
                else
                  Text(
                    preview == null
                        ? deviceValue(p)
                        : deviceValue({...p, 'value': preview}),
                    style: const TextStyle(fontSize: 16, color: _homeGreen),
                  ),
              ],
            ),
            if (slider)
              Slider(
                activeColor: _homeGreen,
                min: (range[0] as num).toDouble(),
                max: (range[1] as num).toDouble(),
                value: (preview ?? value.toDouble()).clamp(
                  (range[0] as num).toDouble(),
                  (range[1] as num).toDouble(),
                ),
                divisions:
                    ((((range[1] as num) - (range[0] as num)) /
                                (range.length > 2 &&
                                        range[2] is num &&
                                        range[2] > 0
                                    ? range[2]
                                    : 1))
                            .round())
                        .clamp(1, 2000),
                label: deviceValue({...p, 'value': preview ?? value}),
                onChanged: widget.busy
                    ? null
                    : (v) => setState(() => preview = v),
                onChangeEnd: widget.busy
                    ? null
                    : (v) async {
                        final minimum = (range[0] as num).toDouble();
                        final step =
                            range.length > 2 && range[2] is num && range[2] > 0
                            ? (range[2] as num).toDouble()
                            : 1.0;
                        final adjusted =
                            (minimum + ((v - minimum) / step).round() * step)
                                .clamp(minimum, (range[1] as num).toDouble());
                        final ok = await widget.onWrite(
                          p['type'] == 'float' ? adjusted : adjusted.round(),
                        );
                        if (mounted && !ok) setState(() => preview = null);
                      },
              ),
            if (choices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final option in choices)
                      ChoiceChip(
                        label: Text(choiceName(option['description'])),
                        selected: '${option['value']}' == '$value',
                        onSelected: widget.busy
                            ? null
                            : (_) => widget.onWrite(option['value']),
                        selectedColor: const Color(0xFFDFE9DA),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HomeDevicePage extends StatefulWidget {
  const HomeDevicePage({super.key, required this.device});
  final Map device;
  @override
  State<HomeDevicePage> createState() => _HomeDevicePageState();
}

class _HomeDevicePageState extends State<HomeDevicePage> {
  List<Map> properties = [];
  bool loading = true, sending = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    if (widget.device['online'] == true) {
      load();
    } else {
      loading = false;
    }
  }

  Future<void> load() async {
    try {
      final response = await apiGet(
        '/api/hub/mihome/status?name=${Uri.encodeComponent('${widget.device['name']}')}&did=${Uri.encodeComponent('${widget.device['did']}')}',
      );
      if (response is! Map || response['props'] is! List) {
        throw Exception('暂时读不到设备状态，请稍后重试');
      }
      if (mounted) {
        setState(() {
          properties = (response['props'] as List).whereType<Map>().toList();
          loading = false;
          error = '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '暂时读不到设备状态，请检查设备连接后重试';
        });
      }
    }
  }

  bool actionable(Map p) =>
      p['rw'].toString().contains('w') &&
      p['value'] != null &&
      p['error'] == null &&
      !devicePropertyName(p).startsWith('其他设置（') &&
      (p['type'] == 'bool' ||
          p['value'] is bool ||
          (p['choices'] is List && p['choices'].isNotEmpty) ||
          (p['range'] is List && p['range'].length >= 2));
  Future<bool> write(Map p, dynamic value) async {
    if (sending) return false;
    setState(() => sending = true);
    try {
      await sendHomeCommand({
        'kind': 'set',
        'name': '${widget.device['name']}',
        'did': '${widget.device['did']}',
        'prop': '${p['prop']}',
        'value': value,
      });
      if (!mounted) return true;
      setState(
        () => properties = properties
            .map(
              (old) =>
                  old['prop'] == p['prop'] ? {...old, 'value': value} : old,
            )
            .toList(),
      );
      notice(context, '${devicePropertyName(p)}已调整');
      await load();
      return true;
    } catch (_) {
      if (mounted) notice(context, '设备暂时没有响应，请刷新后再试');
      return false;
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controls = properties.where(actionable).toList();
    final readings = properties
        .where(
          (p) =>
              !actionable(p) &&
              p['value'] != null &&
              !devicePropertyName(p).startsWith('其他设置（'),
        )
        .toList();
    return Scaffold(
      backgroundColor: _homePaper,
      appBar: AppBar(
        backgroundColor: _homePaper,
        title: Text('${widget.device['name']}'),
        actions: [
          IconButton(
            tooltip: '刷新状态',
            onPressed: loading || sending || widget.device['online'] != true
                ? null
                : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
          ? errorState(context, error, load)
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: DeviceArtwork(device: widget.device, size: 122),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${widget.device['name']}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: _homeInk,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.device['category_label']} · ${widget.device['room']}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF77847A)),
                  ),
                  const SizedBox(height: 28),
                  if (widget.device['online'] != true)
                    emptyState('设备暂时离线', '检查设备电源与家里的网络，恢复连接后再试。'),
                  for (final p in controls)
                    DeviceControlPanel(
                      key: ValueKey(p['prop']),
                      property: p,
                      busy: sending,
                      onWrite: (value) => write(p, value),
                    ),
                  if (readings.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '当前状态',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          color: _homeInk,
                        ),
                      ),
                    ),
                    for (final p in readings)
                      Card(
                        color: Colors.white,
                        elevation: 0,
                        child: ListTile(
                          title: Text(devicePropertyName(p)),
                          trailing: Text(
                            deviceValue(p),
                            style: const TextStyle(
                              color: _homeGreen,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                  if (controls.isEmpty &&
                      readings.isEmpty &&
                      widget.device['online'] == true)
                    emptyState('这台设备暂不支持直接控制', '可在米家 App 中使用；设备信息仍可在下方查看。'),
                  const SizedBox(height: 20),
                  ExpansionTile(
                    title: const Text('设备信息'),
                    children: [
                      ListTile(
                        title: const Text('设备型号'),
                        subtitle: SelectableText('${widget.device['model']}'),
                      ),
                      ListTile(
                        title: const Text('连接状态'),
                        subtitle: Text(
                          widget.device['online'] == true ? '在线' : '离线',
                        ),
                      ),
                      for (final p in properties.where(
                        (p) => devicePropertyName(p).startsWith('其他设置（'),
                      ))
                        ListTile(
                          title: Text(devicePropertyName(p)),
                          subtitle: Text(
                            p['error'] != null
                                ? '暂时无法读取'
                                : p['value'] == null
                                ? '暂无数据'
                                : deviceValue(p),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
