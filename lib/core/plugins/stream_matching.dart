/// 跨源取流时的「同一首歌」严格校验(纯函数,便于单测)。
///
/// 背景:腾讯音乐的搜索/元数据质量最好,但取流慢(实测约 2s,经第三方中转);
/// 网易/酷我念心的取流快得多(约 0.03~0.16s)。于是想用腾讯拿到正版曲目后,
/// 去快源取同曲的播放地址。
///
/// 风险是**串歌**(取到别的歌的地址),所以这里坚持三条硬条件:
///   ① 歌名规范化后必须相等;
///   ② 主歌手必须一致(去掉 & / 、 等分隔后取第一位);
///   ③ 双方时长都已知时,差值 ≤ 3 秒(可挡住试听片段与错版)。
library;

/// 规范化歌名:去掉括号内容、空白与常见装饰符,转小写。
String normalizeTitle(String raw) {
  var t = raw.toLowerCase();
  // 去掉括号/书名号内容:(Live)、(翻唱版)、[remix]、【伴奏】
  t = t.replaceAll(RegExp(r'[\(（\[【][^\)）\]】]*[\)）\]】]'), '');
  // 去掉常见装饰与标点
  t = t.replaceAll(RegExp(r"[\s\-_·、,，.。!！?？~～“”'’]"), '');
  return t;
}

/// 主歌手:去掉 & / 、 , 等分隔后的第一位(如「周杰伦&温岚」→「周杰伦」)。
String primaryArtist(String raw) {
  final first = raw.split(RegExp(r'[&、,，/|]')).first.trim().toLowerCase();
  return first.replaceAll(RegExp(r'\s+'), '');
}

/// 时长是否吻合(单位毫秒);任一方未知时不做判断(返回 true)。
bool durationMatches(num? a, num? b, {int toleranceMs = 3000}) {
  if (a == null || b == null) return true;
  final da = a.toInt();
  final db = b.toInt();
  if (da <= 0 || db <= 0) return true;
  return (da - db).abs() <= toleranceMs;
}

/// 严格判定两个条目是否为同一首歌(用于跨源取流)。
///
/// [title]/[artist]/[durationMs] 为原始曲目,[other*] 为候选源上的条目。
bool isSameSongStrict({
  required String title,
  required String artist,
  num? durationMs,
  required String otherTitle,
  required String otherArtist,
  num? otherDurationMs,
  int toleranceMs = 3000,
}) {
  final t1 = normalizeTitle(title);
  final t2 = normalizeTitle(otherTitle);
  if (t1.isEmpty || t2.isEmpty || t1 != t2) return false;

  final a1 = primaryArtist(artist);
  final a2 = primaryArtist(otherArtist);
  if (a1.isEmpty || a2.isEmpty) return false;
  if (a1 != a2 && !a1.contains(a2) && !a2.contains(a1)) return false;

  return durationMatches(durationMs, otherDurationMs, toleranceMs: toleranceMs);
}

/// 是否可信的快速中转源(实测返回完整音频、且取流极快)。
///
/// 这类源可以跳过「体积探测」以节省 0.5~2s:探测的目的是识别官方源的
/// VIP 试听片段,而念心等中转源返回的是完整音频(真机验证过完整播放)。
bool isTrustedFastRelay(String? platform) {
  if (platform == null) return false;
  final p = platform.toLowerCase();
  return p.contains('念心') || p.contains('nxinxz') || p.contains('met音源');
}

/// 快源优先顺序:取流实测最快的排前面(纯函数,便于单测)。
int streamSpeedScore(String platform) {
  final p = platform.toLowerCase();
  if (p.contains('念心') || p.contains('nxinxz')) return 0; // 实测 ~28ms
  if (p.contains('网易') || p.contains('netease') || p == '网yi') return 1;
  if (p.contains('酷我') || p.contains('kuwo')) return 2;
  return 10;
}
