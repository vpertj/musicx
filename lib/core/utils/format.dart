/// 展示层时间格式化工具。
library;

/// 毫秒 -> `mm:ss`;超过 1 小时为 `h:mm:ss`。
String formatDuration(Duration d) {
  if (d.isNegative) return '00:00';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// 毫秒数 -> `mm:ss`(空值/非正数按 00:00)。
String formatMilliseconds(int? ms) {
  if (ms == null || ms <= 0) return '00:00';
  return formatDuration(Duration(milliseconds: ms));
}
