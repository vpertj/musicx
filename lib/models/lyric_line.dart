class LyricLine {
  final Duration time;
  final String text;
  const LyricLine({required this.time, required this.text});

  /// 解析单行 LRC,如 `[01:23.45]歌词`;无时间戳的元信息行返回 text 为空的实例。
  factory LyricLine.fromLrc(String rawLine) {
    final match = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\](.*)').firstMatch(rawLine);
    if (match == null) {
      return const LyricLine(time: Duration.zero, text: '');
    }
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final millisRaw = match.group(3);
    var millis = 0;
    if (millisRaw != null) {
      millis = millisRaw.length == 2
          ? int.parse(millisRaw) * 10
          : int.parse(millisRaw.padRight(3, '0').substring(0, 3));
    }
    return LyricLine(
      time: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
      text: match.group(4) ?? '',
    );
  }
}
