/// 搜索失败原因汇总(纯函数,便于单测)。
///
/// 自动模式会依次尝试所有音源,全失败时必须告诉用户/开发者**每个源的原因**,
/// 否则真机上的问题(例如 Android 9+ 禁止明文 http)只能靠猜。
library;

import 'package:flutter/foundation.dart';

/// 单个音源的失败记录。
class SearchFailure {
  const SearchFailure({required this.platform, required this.error});

  final String platform;
  final Object error;
}

/// 详细失败原因(含各音源名,供日志/排查使用,**不要直接展示给用户**)。
String describeSearchFailuresDetailed(List<SearchFailure> failures) {
  if (failures.isEmpty) return '没有可用音源';
  final parts = failures.map((f) {
    var msg = f.error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (msg.length > 60) msg = '${msg.substring(0, 60)}…';
    return '${f.platform}($msg)';
  });
  return '所有音源均失败:${parts.join('、')}';
}

/// 用户可见的失败文案:**不出现任何音源名称**(用户要求 App 内不出现
/// 具体音源字样);详细原因写日志,便于真机排查。
String describeSearchFailures(List<SearchFailure> failures) {
  if (failures.isEmpty) return '没有可用音源';
  debugPrint('MusicX 搜索失败详情: ${describeSearchFailuresDetailed(failures)}');
  return '搜索失败,请稍后重试或检查网络';
}
