part of 'main.dart';

Map<String, dynamic> sceneMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> sceneList(dynamic value) =>
    value is List ? value.whereType<Map>().map(sceneMap).toList() : [];
double? sceneNumber(dynamic value) {
  if (value == null || value is bool) return null;
  final n = double.tryParse('$value');
  return n != null && n.isFinite ? n : null;
}

String sceneDecimal(num n) =>
    n.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
DateTime? sceneDate(dynamic value) {
  if (value == null || '$value'.isEmpty) return null;
  final n = sceneNumber(value);
  if (n != null) {
    if (n <= 0 || n > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (n < 100000000000 ? n * 1000 : n).round(),
      isUtc: true,
    );
  }
  final s = '$value';
  // The source's unzoned timestamps are Beijing local time, independent of device TZ.
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  return RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(s)
      ? parsed.toUtc()
      : DateTime.utc(
          parsed.year,
          parsed.month,
          parsed.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
        ).subtract(const Duration(hours: 8));
}

DateTime sceneBeijing(DateTime d) => d.toUtc().add(const Duration(hours: 8));
String sceneTime(dynamic value, {String missing = '来源时间未提供'}) {
  final parsed = sceneDate(value);
  if (parsed == null) return missing;
  final d = sceneBeijing(parsed);
  String two(int n) => '$n'.padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

class QuotaWindow {
  const QuotaWindow(
    this.period,
    this.value, {
    this.remaining,
    this.reset = '重置时间未提供',
  });
  final String period, value, reset;
  final double? remaining;
}

class QuotaAccount {
  QuotaAccount(
    this.platform,
    this.name,
    this.windows, {
    dynamic sourceTime,
    this.error = '',
    this.source = '',
  }) : observed = sceneTime(sourceTime),
       sourceDate = sceneDate(sourceTime);
  final String platform, name, observed, error, source;
  final DateTime? sourceDate;
  final List<QuotaWindow> windows;
  bool get stale =>
      sourceDate == null ||
      DateTime.now().toUtc().difference(sourceDate!).inMinutes > 90;
}

List<QuotaAccount> quotaAccounts(Map raw) {
  final result = <QuotaAccount>[];
  final accounts = sceneMap(raw['accounts']);
  final push = sceneMap(raw['push']);
  final observed = raw['collected_at'];
  const names = {
    'zhipu': 'GLM',
    'opencode': 'OpenCode',
    'deepseek': 'DeepSeek',
    'tencent': '腾讯云',
    'cursor': 'Cursor',
    'codex': 'Codex',
    'mimo': 'MiMo',
    'jev': 'JEV',
    'gha': 'GitHub Actions',
  };
  String period(Map w, String fallback) {
    final seconds = sceneNumber(w['window_seconds']);
    if (seconds == null) return fallback;
    if (seconds % 86400 == 0) return '${sceneDecimal(seconds / 86400)}天窗口';
    return '${sceneDecimal(seconds / 3600)}小时窗口';
  }

  QuotaWindow window(Map w, String label, dynamic ts) {
    final used = sceneNumber(w['percent'] ?? w['u']);
    final remain = used != null && used >= 0 && used <= 100 ? 100 - used : null;
    dynamic reset = w['reset_at'];
    if (reset == null && sceneNumber(w['s']) != null && sceneDate(ts) != null) {
      reset =
          sceneDate(ts)!.millisecondsSinceEpoch / 1000 + sceneNumber(w['s'])!;
    }
    final resetText = reset != null
        ? sceneTime(reset, missing: '未提供')
        : '${w['reset'] ?? '未提供'}';
    return QuotaWindow(
      period(w, label),
      remain == null ? '额度待更新' : '剩余 ${sceneDecimal(remain)}%',
      remaining: remain,
      reset: resetText == '未提供' ? '重置时间未提供' : '$resetText 重置（北京时间）',
    );
  }

  String quotaPercent(double n) =>
      n.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  QuotaWindow mimoQuota(Map q) {
    double? nonnegative(dynamic v) {
      final n = sceneNumber(v);
      return n != null && n >= 0 ? n : null;
    }

    final limit = nonnegative(q['limit']);
    final left = nonnegative(q['remaining']);
    final used =
        nonnegative(q['used']) ??
        (limit != null && left != null && limit >= left ? limit - left : null);
    final sourcePercent = nonnegative(q['remainingPercent']);
    final percent = sourcePercent != null && sourcePercent <= 100
        ? sourcePercent
        : limit != null && limit > 0 && left != null && left <= limit
        ? left / limit * 100
        : null;
    String amount(double n) {
      final parts = (n == n.truncateToDouble() ? n.toStringAsFixed(0) : '$n')
          .split('.');
      final whole = parts.first.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
      return parts.length == 1 ? whole : '$whole.${parts.last}';
    }

    final totalText = limit == null ? '总量未提供' : '总量 ${amount(limit)}';
    final usedText = used == null ? '已用未提供' : '已用 ${amount(used)}';
    final leftText = left == null ? '剩余额度未提供' : '剩余 ${amount(left)} credits';
    return QuotaWindow(
      q['name'] == 'month_total_token'
          ? '每月 Token 额度'
          : '${q['name'] ?? 'Token Plan'}',
      '$totalText · $usedText · $leftText${percent == null ? '' : '（${quotaPercent(percent)}%）'}',
      remaining: percent,
      reset: q['reset_at'] == null
          ? '重置时间未提供'
          : '${sceneTime(q['reset_at'])} 重置（北京时间）',
    );
  }

  QuotaWindow balance(Map a) {
    final amount = sceneNumber(a['amount'] ?? a['amt']);
    final currency = '${a['currency'] ?? a['cur'] ?? ''}';
    final symbol = {'CNY': '¥', 'USD': r'$'}[currency] ?? currency;
    return QuotaWindow(
      '账户余额',
      amount == null ? '余额待更新' : '余额 $symbol${sceneDecimal(amount)}',
      reset: '金额余额 · 不与订阅额度合计',
    );
  }

  for (final e in accounts.entries) {
    final a = sceneMap(e.value);
    final ts = a['collected_at'] ?? a['ts'] ?? observed;
    final windows = <QuotaWindow>[];
    switch (e.key) {
      case 'zhipu':
        for (final key in ['five_hour', 'weekly']) {
          final w = a[key] ?? (key == 'weekly' ? a['monthly'] : null);
          if (w is Map) {
            windows.add(window(w, key == 'weekly' ? '每周窗口' : '5小时窗口', ts));
          }
        }
        final m = sceneMap(a['mcp']);
        if (m.isNotEmpty) {
          final used = sceneNumber(m['used']), total = sceneNumber(m['total']);
          windows.add(
            QuotaWindow(
              'MCP 调用',
              used != null && total != null && total >= used
                  ? '剩余 ${sceneDecimal(total - used)} 次'
                  : used != null
                  ? '已用 ${sceneDecimal(used)} 次 · 总量未提供'
                  : '调用额度待更新',
              reset: '重置：${m['reset'] ?? '未提供'}',
            ),
          );
        }
      case 'opencode':
        for (final e in {
          'rolling': '滚动窗口',
          'weekly': '每周窗口',
          'monthly': '每月窗口',
        }.entries) {
          if (a[e.key] is Map) windows.add(window(a[e.key], e.value, ts));
        }
      case 'cursor':
        for (final e in {
          'total_percent': '总额度',
          'auto_percent': '自动模型',
          'api_percent': '指定模型',
        }.entries) {
          final value = sceneNumber(a[e.key]);
          final remaining = value != null && value >= 0 && value <= 100
              ? 100 - value
              : null;
          windows.add(
            QuotaWindow(
              e.value,
              remaining != null
                  ? '剩余 ${quotaPercent(remaining)}%'
                  : value == null
                  ? '额度待更新'
                  : '来源已用 ${sceneDecimal(value)}% · 超出有效百分比范围',
              remaining: remaining,
              reset: '账单周期结束：${sceneTime(a['cycle_end'], missing: '未提供')}',
            ),
          );
        }
      default:
        if (a.containsKey('amount') || a.containsKey('currency')) {
          windows.add(balance(a));
        } else {
          for (final w in a.entries) {
            if (w.value is Map &&
                (w.value.containsKey('percent') || w.value.containsKey('u'))) {
              windows.add(window(w.value, '${w.key} · 周期以来源为准', ts));
            }
          }
        }
    }
    result.add(
      QuotaAccount(
        names[e.key] ?? e.key,
        '${a['name'] ?? '平台账号'}',
        windows,
        sourceTime: ts,
        source: '直接采集',
        error: windows.isEmpty ? '该来源暂未提供可展示的额度字段' : '',
      ),
    );
  }
  for (final e in push.entries) {
    final group = sceneMap(e.value);
    if (e.key == 'gha') {
      for (final scope in ['personal', 'org']) {
        final a = sceneMap(group[scope]);
        if (a.isEmpty) continue;
        final left = sceneNumber(a['left']),
            included = sceneNumber(a['included']);
        final remaining =
            left != null &&
                included != null &&
                included > 0 &&
                left >= 0 &&
                left <= included
            ? left / included * 100
            : null;
        result.add(
          QuotaAccount(
            'GitHub Actions',
            scope == 'personal' ? '个人账号' : '组织账号',
            [
              QuotaWindow(
                '每月额度',
                left == null ? '额度待更新' : '剩余 ${sceneDecimal(left)} 分钟',
                remaining: remaining,
                reset: '${group['note'] ?? '重置时间未提供'}',
              ),
            ],
            sourceTime: group['updated'],
          ),
        );
      }
      continue;
    }
    var list = sceneList(group['accounts']);
    if (e.key == 'mimo' && list.isEmpty) {
      list = sceneList(group['items'])
          .map(
            (item) => <String, dynamic>{
              'n':
                  'MiMo-${group['plan'] ?? 'Token Plan'}-${item['name'] ?? '额度'}',
              'quota': item,
              'ts': group['observedAt'] ?? group['updated_at'],
            },
          )
          .toList();
    }
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      final ts = a['ts'] ?? group['updated_at'];
      final windows = <QuotaWindow>[];
      if (e.key == 'mimo' && a['quota'] is Map) {
        windows.add(
          mimoQuota({
            ...sceneMap(a['quota']),
            if (sceneMap(a['quota'])['name'] == null &&
                '${a['n']}'.endsWith('-month_total_token'))
              'name': 'month_total_token',
          }),
        );
      } else if (e.key == 'codex') {
        for (final key in ['fh', 'sd']) {
          if (a[key] is Map && (a[key] as Map).isNotEmpty) {
            windows.add(window(a[key], '周期待确认', ts));
          }
        }
        if ('${a['rem'] ?? ''}'.isNotEmpty) {
          windows.add(
            QuotaWindow('独立额度与积分', '${a['rem']}', reset: '按来源原始口径展示，不与周期百分比合计'),
          );
        }
        if (windows.isEmpty) windows.add(const QuotaWindow('周期待确认', '额度待更新'));
      } else if (e.key == 'cursor' &&
          RegExp(
            r'(?:total|auto|api)PercentUsed=[0-9.]+% used',
          ).hasMatch('${a['rem'] ?? ''}')) {
        final rem = '${a['rem']}';
        final reset = RegExp(r'(?:^|; )reset=([^;]+)').firstMatch(rem)?[1];
        for (final field in {
          'total': '总额度',
          'auto': '自动模型',
          'api': '指定模型',
        }.entries) {
          final match = RegExp(
            '${field.key}PercentUsed=([0-9.]+)% used',
          ).firstMatch(rem);
          if (match == null) continue;
          final used = sceneNumber(match[1]);
          final left = used != null && used >= 0 && used <= 100
              ? 100 - used
              : null;
          windows.add(
            QuotaWindow(
              field.value,
              left == null ? '额度待更新' : '剩余 ${quotaPercent(left)}%',
              remaining: left,
              reset: '账单周期结束：${sceneTime(reset, missing: '未提供')}',
            ),
          );
        }
      } else if (a['bal'] is Map) {
        windows.add(balance(a['bal']));
      } else {
        final rem = '${a['rem'] ?? ''}';
        final match = RegExp(r'[（(]([0-9.]+)%[）)]').firstMatch(rem);
        final p = match == null ? null : sceneNumber(match[1]);
        final remain = p != null && p >= 0 && p <= 100 ? p : null;
        windows.add(
          QuotaWindow(
            e.key == 'mimo' && '${a['n']}'.endsWith('-month_total_token')
                ? '每月 Token 额度'
                : '周期以来源为准',
            remain != null && e.key != 'mimo'
                ? '剩余 ${sceneDecimal(remain)}%'
                : rem.isEmpty
                ? '额度待更新'
                : rem,
            remaining: remain,
          ),
        );
      }
      result.add(
        QuotaAccount(
          names[e.key] ?? e.key,
          e.key == 'mimo' && '${a['n']}'.startsWith('MiMo-standard:year-')
              ? '标准套餐（年付）'
              : '${a['n'] ?? '账号 ${i + 1}'}',
          windows,
          sourceTime: ts,
          source: '推送采集',
        ),
      );
    }
    if (list.isEmpty) {
      // Keep unadapted platforms visible without exposing arbitrary source fields.
      result.add(
        QuotaAccount(
          names[e.key] ?? e.key,
          '平台账号',
          const [],
          sourceTime: group['updated_at'] ?? group['updated'],
          error: '此平台尚未提供统一额度字段，请查看来源状态',
        ),
      );
    }
  }
  for (final e in sceneMap(raw['errors']).entries) {
    final name = names[e.key] ?? e.key;
    final matches = result.where((a) => a.platform == name).toList();
    if (matches.isEmpty) {
      result.add(QuotaAccount(name, '平台账号', const [], error: '本次查询失败，额度未知'));
    } else {
      for (final a in matches) {
        final index = result.indexOf(a);
        result[index] = QuotaAccount(
          a.platform,
          a.name,
          a.windows,
          sourceTime: a.sourceDate?.toIso8601String(),
          error: '本次查询失败，显示上次观测',
        );
      }
    }
  }
  if (!result.any((a) => a.platform == 'Codex')) {
    result.add(
      QuotaAccount('Codex', 'GPT / Codex', const [], error: '本次未收到额度快照，额度未知'),
    );
  }
  return result;
}

class VehicleStatus {
  VehicleStatus(this.raw);
  final Map<String, dynamic> raw;
  String get name => '${raw['name'] ?? raw['brand'] ?? '车辆'}';
  String get brand => '${raw['brand'] ?? ''}';
  double? get battery {
    final n = sceneNumber(raw['battery']);
    return n != null && n >= 0 && n <= 100 ? n : null;
  }

  String get charging {
    final v = raw['charging'];
    if (v == true || v == 1 || v == '1') return '充电中';
    if (v == false || v == 0 || v == '0') return '未充电';
    return '充电状态未知';
  }

  String get address =>
      '${raw['address'] ?? ''}'.trim().isEmpty ? '位置暂未提供' : '${raw['address']}';
  String get reportTime => sceneTime(raw['report_ms'], missing: '上报时间未提供');
  String get locationTime => sceneTime(raw['location_ms'], missing: '定位时间未提供');
  bool get stale =>
      raw['fresh'] != true ||
      sceneDate(raw['report_ms']) == null ||
      DateTime.now()
              .toUtc()
              .difference(sceneDate(raw['report_ms'])!)
              .inMinutes >
          10;
  String get serviceName => '${raw['service_name'] ?? '车辆服务'}';
  DateTime? get expiry => sceneDate(raw['service_expires_at']);
  int? daysToExpiry(DateTime now) {
    if (expiry == null) {
      return sceneNumber(raw['service_remaining_days'])?.floor();
    }
    final a = sceneBeijing(expiry!), b = sceneBeijing(now);
    return DateTime.utc(
      a.year,
      a.month,
      a.day,
    ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
  }

  String renewalSummary(DateTime now) {
    final days = daysToExpiry(now);
    if (days == null) return '到期状态待确认';
    if (expiry == null) return days < 0 ? '到期状态待确认' : '平台剩余 $days 天';
    if (days < 0) return '已到期 ${-days} 天';
    return days == 0 ? '今天到期' : '还有 $days 天';
  }

  String get expiryText => expiry == null
      ? '到期时间未提供'
      : '$serviceName到期：${sceneTime(raw['service_expires_at']).split(' ').first}';
  String get state => '${raw['state'] ?? '状态未知'}';
}
