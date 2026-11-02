import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  test(
    'MiMo structured quota preserves total used remaining without mixing periods',
    () {
      final a = quotaAccounts({
        'push': {
          'mimo': {
            'accounts': [
              {
                'n': 'MiMo',
                'quota': {
                  'limit': 132000000000,
                  'used': 40167631752,
                  'remaining': 91832368248,
                  'remainingPercent': 69.57,
                  'reset_at': '2026-11-27T15:59:59Z',
                },
              },
            ],
          },
        },
      }).first;
      expect(
        a.windows.single.value,
        '总量 132000000000 · 已用 40167631752 · 剩余 91832368248 credits（69.57%）',
      );
      expect(a.windows.single.reset, contains('2026-11-27'));
    },
  );
  test('MiMo actual cache items derive used from limit minus remaining', () {
    final a = quotaAccounts({
      'push': {
        'mimo': {
          'plan': 'standard:year',
          'observedAt': 1793589575,
          'items': [
            {
              'name': 'month_total_token',
              'remaining': 91832368248,
              'limit': 132000000000,
              'remainingPercent': 69.57,
            },
          ],
        },
      },
    }).first;
    expect(a.windows.single.value, contains('已用 40167631752'));
    expect(a.windows.single.remaining, 69.57);
    expect(a.windows.single.reset, '重置时间未提供');
  });
  test('MiMo missing structured used and total stays unknown', () {
    final a = quotaAccounts({
      'push': {
        'mimo': {
          'accounts': [
            {
              'n': 'MiMo',
              'quota': {'remaining': 12},
            },
          ],
        },
      },
    }).first;
    expect(a.windows.single.value, '总量未提供 · 已用未提供 · 剩余 12 credits');
    expect(a.windows.single.remaining, isNull);
  });
  test(
    'MiMo preserves actual absolute credits instead of percentage alone',
    () {
      final a = quotaAccounts({
        'push': {
          'mimo': {
            'accounts': [
              {
                'n': 'MiMo-standard:year-month_total_token',
                'rem': '剩余 91,832,368,248 credits（69.57%）',
                'ts': 1793589575,
              },
            ],
          },
        },
      }).firstWhere((a) => a.platform == 'MiMo');
      expect(a.windows.single.value, '剩余 91,832,368,248 credits（69.57%）');
      expect(a.windows.single.remaining, 69.57);
    },
  );
  test('Cursor used fields become labeled remaining windows', () {
    final a = quotaAccounts({
      'push': {
        'cursor': {
          'accounts': [
            {
              'n': 'Cursor(pro)',
              'rem':
                  'autoPercentUsed=32.21% used; apiPercentUsed=0.0% used; totalPercentUsed=29.28% used; reset=2026-11-20T06:15:11.000Z; on-demand=disabled',
            },
          ],
        },
      },
    }).firstWhere((a) => a.platform == 'Cursor');
    expect(a.windows.map((w) => w.period), ['总额度', '自动模型', '指定模型']);
    expect(a.windows.map((w) => w.value), [
      '剩余 70.72%',
      '剩余 67.79%',
      '剩余 100%',
    ]);
    expect(a.windows.first.reset, contains('2026-11-20'));
  });
  test('Cursor direct source preserves two decimal precision', () {
    final a = quotaAccounts({
      'accounts': {
        'cursor': {'total_percent': 29.28},
      },
    }).first;
    expect(a.windows.first.value, '剩余 70.72%');
  });
  test('Codex missing source remains an explicit unavailable card', () {
    final a = quotaAccounts({}).first;
    expect(a.platform, 'Codex');
    expect(a.error, isNotEmpty);
    expect(a.windows, isEmpty);
  });
  test(
    'Cursor valid used percentages become remaining and invalid stays explicit',
    () {
      final a = quotaAccounts({
        'accounts': {
          'cursor': {
            'total_percent': 25,
            'auto_percent': 0,
            'api_percent': 100,
            'cycle_end': '2026-11-01T00:00:00Z',
          },
        },
      }).first;
      expect(a.windows.map((w) => w.remaining), [75, 100, 0]);
      expect(a.windows.first.value, '剩余 75%');
      final invalid = quotaAccounts({
        'accounts': {
          'cursor': {
            'total_percent': 125,
            'auto_percent': -1,
            'api_percent': 'NaN',
          },
        },
      }).first;
      expect(invalid.windows.map((w) => w.remaining), [null, null, null]);
      expect(invalid.windows.first.value, contains('125%'));
      expect(invalid.windows.last.value, '额度待更新');
    },
  );
  test(
    'all platforms accounts and separate periods retain their semantics',
    () {
      final rows = quotaAccounts({
        'collected_at': '2026-10-26T12:00:00+08:00',
        'accounts': {
          'zhipu': {
            'five_hour': {'percent': 88},
            'weekly': {'percent': 26},
            'mcp': {'used': 0, 'total': 120},
          },
          'opencode': {
            'rolling': {'percent': 0},
            'weekly': {'percent': 30},
            'monthly': {'percent': 40},
          },
          'tencent': {'amount': 0, 'currency': 'CNY'},
        },
        'push': {
          'codex': {
            'accounts': [
              {
                'n': 'Codex-A',
                'ts': 1792987200,
                'fh': {'u': 32, 'window_seconds': 604800, 's': 3600},
              },
              {
                'n': 'Codex-B',
                'fh': {'u': 58},
              },
            ],
          },
          'mimo': {
            'accounts': [
              {'n': 'mimo-A', 'rem': '剩余（82%）'},
              {'n': 'mimo-B', 'rem': '待更新'},
            ],
          },
        },
      });
      expect(rows.where((a) => a.platform == 'Codex').length, 2);
      expect(rows.where((a) => a.platform == 'MiMo').length, 2);
      final glm = rows.firstWhere((a) => a.platform == 'GLM');
      expect(glm.windows.length, 3);
      expect(glm.windows.first.remaining, 12);
      expect(glm.windows.last.value, '剩余 120 次');
      expect(
        rows.firstWhere((a) => a.platform == 'OpenCode').windows.length,
        3,
      );
      expect(
        rows.firstWhere((a) => a.platform == '腾讯云').windows.single.value,
        '余额 ¥0',
      );
      final codex = rows.where((a) => a.platform == 'Codex').toList();
      expect(codex.first.windows.single.period, '7天窗口');
      expect(codex.last.windows.single.period, '周期待确认');
      expect(codex.first.windows.single.reset, isNot(contains('待更新')));
    },
  );
  test('GitHub personal and organization minutes remain separate', () {
    final a = quotaAccounts({
      'push': {
        'gha': {
          'personal': {'included': 2000, 'used': 1968, 'left': 32},
          'org': {'included': 2000, 'used': 794, 'left': 1206},
          'note': '每月1日重置',
        },
      },
    });
    expect(a.where((a) => a.platform == 'GitHub Actions').length, 2);
    expect(a.first.name, '个人账号');
    expect(a[1].name, '组织账号');
    expect(a.first.windows.single.value, '剩余 32 分钟');
    expect(a[1].windows.single.value, '剩余 1206 分钟');
  });
  test('Codex independent allowance and credits are not dropped', () {
    final a = quotaAccounts({
      'push': {
        'codex': {
          'accounts': [
            {'n': 'credits-only', 'rem': '独立额度剩余 12；积分 9'},
          ],
        },
      },
    });
    expect(a.first.windows.single.value, contains('独立额度剩余 12'));
    expect(a.first.windows.single.value, contains('积分 9'));
  });
  test(
    'unknown percent does not become zero and observed time stays unknown',
    () {
      final rows = quotaAccounts({
        'accounts': {
          'zhipu': {
            'weekly': {'percent': 'NaN'},
          },
        },
        'errors': {'deepseek': 'Timeout'},
      });
      expect(rows.first.windows.single.remaining, isNull);
      expect(rows.first.observed, '来源时间未提供');
      expect(
        rows.firstWhere((a) => a.platform == 'DeepSeek').error,
        isNotEmpty,
      );
      expect(rows.last.windows, isEmpty);
    },
  );
  test(
    'vehicle unknown charging differs from not charging, zero battery remains zero',
    () {
      final v = VehicleStatus({'name': '通勤车', 'battery': 0, 'fresh': false});
      expect(v.battery, 0);
      expect(v.charging, '充电状态未知');
      expect(v.reportTime, '上报时间未提供');
      expect(v.expiryText, '到期时间未提供');
      expect(VehicleStatus({'charging': false}).charging, '未充电');
      expect(VehicleStatus({'charging': 1}).charging, '充电中');
      expect(VehicleStatus({'charging': 9}).charging, '充电状态未知');
      expect(VehicleStatus({'battery': 110}).battery, isNull);
    },
  );
  test('zero service days without expiry is not assumed to expire today', () {
    final v = VehicleStatus({'service_remaining_days': 0});
    expect(v.renewalSummary(DateTime.now()), '平台剩余 0 天');
    expect(
      VehicleStatus({
        'service_remaining_days': -1,
      }).renewalSummary(DateTime.now()),
      '到期状态待确认',
    );
  });
  test(
    'renewal is based on Shanghai calendar dates and scoped service label',
    () {
      final v = VehicleStatus({
        'service_name': '联网服务',
        'service_expires_at': '2026-10-29',
      });
      expect(v.daysToExpiry(DateTime.parse('2026-10-26T23:59:00+08:00')), 3);
      expect(v.expiryText, contains('联网服务'));
      expect(v.daysToExpiry(DateTime.parse('2026-10-30T00:00:00+08:00')), -1);
    },
  );
}
