/// 解析单个 LRC 时间戳标签内容(不含方括号)。
///
/// 支持两种实际生态里都存在的写法:
/// - `mm:ss` / `mm:ss.xx` / `mm:ss:xx`(标准 LRC)
/// - `ss` / `ss.xx`(纯秒,酷我念心等音源在用,例如 `[2.25]` = 2.25 秒)
///
/// 元信息(`ti:`/`ar:`/`offset:` 等)或无法识别的内容返回 null。
Duration? parseLrcTimestamp(String inner) {
  final text = inner.trim();
  if (text.isEmpty) return null;

  if (text.contains(':')) {
    final m = RegExp(r'^(\d+):(\d+)(?:[.:](\d+))?$').firstMatch(text);
    if (m == null) return null;
    return Duration(
      minutes: int.parse(m.group(1)!),
      seconds: int.parse(m.group(2)!),
      milliseconds: _fractionToMillis(m.group(3)),
    );
  }

  // 纯秒:允许小数,整数也接受(如 [123] = 123 秒)
  final m = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(text);
  if (m == null) return null;
  final seconds = int.parse(m.group(1)!);
  final fraction = m.group(2);
  if (fraction == null) return Duration(seconds: seconds);
  return Duration(
    seconds: seconds,
    milliseconds: _fractionToMillis(fraction),
  );
}

/// 小数部分换算为毫秒:两位按 1/100 秒,其余按 1/1000 秒(与 LRC 习惯一致)。
int _fractionToMillis(String? fraction) {
  if (fraction == null || fraction.isEmpty) return 0;
  if (fraction.length == 2) return int.parse(fraction) * 10;
  return int.parse(fraction.padRight(3, '0').substring(0, 3));
}

class LyricLine {
  final Duration time;
  final String text;
  const LyricLine({required this.time, required this.text});

  /// 解析单行 LRC,如 `[01:23.45]歌词` 或 `[83.45]歌词`;
  /// 无时间戳的元信息行返回 text 为空的实例。
  factory LyricLine.fromLrc(String rawLine) {
    final match = RegExp(r'\[([^\]]*)\]').firstMatch(rawLine);
    if (match == null) {
      return const LyricLine(time: Duration.zero, text: '');
    }
    final time = parseLrcTimestamp(match.group(1)!);
    if (time == null) {
      return const LyricLine(time: Duration.zero, text: '');
    }
    final text = rawLine.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
    return LyricLine(time: time, text: text);
  }
}

/// 解析整段 LRC 文本,返回带时间戳的歌词行(跳过元信息行)。
List<LyricLine> parseLrc(String lrc) {
  final lines = <LyricLine>[];
  for (final raw in lrc.split('\n')) {
    // 多时间戳行 `[00:01][01:02]歌词` 展开为多行
    final stamps = RegExp(r'\[([^\]]*)\]')
        .allMatches(raw)
        .map((m) => parseLrcTimestamp(m.group(1)!))
        .whereType<Duration>()
        .toList();
    if (stamps.isEmpty) continue;
    final text = raw.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
    if (text.isEmpty) continue;
    for (final time in stamps) {
      lines.add(LyricLine(time: time, text: text));
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}
