part of 'main.dart';

/// Only presentation of protocol enums is translated; user/device names stay raw.
String choiceName(dynamic value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty) return '暂无数据';
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) return text;
  final key = text.toLowerCase().replaceAll(RegExp(r'[ _]+'), '-');
  return const {
        'auto': '自动',
        'automatic': '自动',
        'silent': '静音',
        'sleep': '睡眠',
        'normal': '标准',
        'standard': '标准',
        'high': '强劲',
        'turbo': '强劲',
        'strong': '强劲',
        'low': '轻柔',
        'medium': '中档',
        'on': '开启',
        'off': '关闭',
        'favorite': '自定义',
        'manual': '手动',
        'custom': '自定义',
        'cool': '制冷',
        'cooling': '制冷',
        'heat': '制热',
        'heating': '制热',
        'dry': '除湿',
        'fan': '送风',
        'reading': '阅读',
        'night': '夜间',
        'day': '日间',
        'tv': '观影',
        'color': '彩光',
        'eco': '节能',
        'energy-saving': '节能',
        'comfort': '舒适',
        'idle': '空闲',
        'standby': '待机',
        'running': '运行中',
        'paused': '已暂停',
        'stopped': '已停止',
        'charging': '充电中',
        'cleaning': '清扫中',
        'docking': '返回充电座',
        'open': '打开',
        'closed': '关闭',
        'locked': '已锁定',
        'unlocked': '已解锁',
        'unknown': '状态未知',
        'error': '设备异常',
        'fault': '设备异常',
        'none': '无',
        'enabled': '已启用',
        'disabled': '已停用',
      }[key] ??
      '设备模式（$text）';
}

String serviceStatusLabel(dynamic value) {
  final raw = '${value ?? ''}'.trim();
  return const {
        'active': '运行中',
        'inactive': '未运行',
        'failed': '运行失败',
        'activating': '启动中',
        'deactivating': '停止中',
        'reloading': '重新加载中',
        'maintenance': '维护中',
        'refreshing': '刷新中',
        'unknown': '状态未知',
        'not-found': '服务不存在',
        'masked': '已禁用',
      }[raw.toLowerCase()] ??
      (raw.isEmpty ? '状态未知' : '状态未知（$raw）');
}

String friendlyError(Object error) {
  if (error is TimeoutException) return '连接超时，请检查网络后重试';
  final text = error
      .toString()
      .replaceFirst(RegExp(r'^Exception: '), '')
      .trim();
  final key = text.toLowerCase();
  if (key.contains('timeoutexception') ||
      key.contains('etimedout') ||
      key == 'timeout' ||
      key == 'timeout_error') {
    return '连接超时，请检查网络后重试';
  }
  if (key.contains('socketexception') ||
      key.contains('clientexception') ||
      key.contains('handshakeexception') ||
      key.contains('econnreset') ||
      key.contains('enotfound') ||
      key == 'network_error' ||
      key == 'fetch failed') {
    return '网络连接失败，请检查网络后重试';
  }
  const errors = {
    'econnrefused': '服务暂时无法连接，请稍后重试',
    'service_unavailable': '服务暂时无法连接，请稍后重试',
    'bad_gateway': '服务暂时无法连接，请稍后重试',
    'unauthorized': '登录已过期，请重新登录后继续',
    'token_expired': '登录已过期，请重新登录后继续',
    'invalid_token': '登录已过期，请重新登录后继续',
    'forbidden': '暂无操作权限，请检查授权',
    'permission_denied': '暂无操作权限，请检查授权',
    'not_found': '请求的内容不存在或已移除',
    'rate_limited': '请求过于频繁，请稍后重试',
    'too_many_requests': '请求过于频繁，请稍后重试',
    'internal_server_error': '服务处理异常，请稍后重试',
    'invalid_request': '请求内容有误，请检查后重试',
  };
  if (errors.containsKey(key)) return errors[key]!;
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) return text;
  return text.isEmpty ? '操作未完成，请稍后重试' : '操作未完成，请稍后重试（$text）';
}
