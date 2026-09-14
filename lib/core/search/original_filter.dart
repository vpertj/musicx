/// 翻唱/非原唱识别与排序(纯函数,便于单测)。
///
/// 用户诉求:内置音源里不要翻唱,尽量都是正版原唱。各音源(尤其网易云)
/// 搜索结果前排常混入用户上传的翻唱、伴奏、纯音乐、DJ 版,这些在标题/专辑/
/// 歌手名上通常有明显特征词,可以直接识别。
///
/// 设计取舍(用户明确要求「只要原版」):
/// - 翻唱/伴奏/纯音乐/混音(remix)/DJ/加速减速/Live 现场/女声男声版/片段…
///   一律视为「非原版」并隐藏;
/// - 过滤后若结果为空,则回退不过滤(否则用户会「搜不到任何东西」,
///   例如某首歌全网只有现场版)。
library;

import 'dart:math' as math;

/// 非原版特征词(小写匹配):翻唱、重制演绎、伴奏、以及各类改编版本。
///
/// 用户诉求「只要原版」,故 Live/remix/DJ 等也从「仅降权」改为隐藏。
const List<String> _nonOriginalMarkers = [
  // 翻唱/演绎
  '翻唱',
  'cover',
  'tribute',
  '改编',
  '清唱',
  // 真机实测漏过的:网易翻唱常用这些标注
  '深情版',
  'r&b版',
  'rnb版',
  '原唱',
  '钢琴曲',
  '吉他曲',
  'bgm',
  '抖音版',
  '快手版',
  // 伴奏/无人声
  '伴奏',
  '纯音乐',
  'instrumental',
  'karaoke',
  'ktv',
  // 混音/电子
  'remix',
  '混音',
  'dj',
  '慢摇',
  '8d',
  '环绕',
  // 变速
  '加速版',
  '加快版',
  '慢速版',
  '减速版',
  '变速',
  // 现场
  'live',
  '现场',
  '演唱会',
  // 人声/器乐改编
  '女声版',
  '男声版',
  '童声版',
  '钢琴版',
  '吉他版',
  '古筝版',
  '二胡版',
  '口琴版',
  '八音盒',
  '阿卡贝拉',
  // 片段类
  '片段',
  '试听',
  '铃声',
];

/// 简易条目视图(避免与 MusicItem 耦合,便于单测)。
typedef SongView = ({String title, String artist, String album});

bool _hasMarker(String text, List<String> markers) {
  final t = text.toLowerCase();
  return markers.any(t.contains);
}

/// 是否明显不是原版(翻唱/伴奏/混音/Live/变速/片段…)。
bool looksLikeNonOriginal({
  required String title,
  required String artist,
  String album = '',
}) {
  if (_hasMarker(title, _nonOriginalMarkers)) return true;
  if (album.isNotEmpty && _hasMarker(album, _nonOriginalMarkers)) return true;
  if (_hasMarker(artist, _nonOriginalMarkers)) return true;
  // 网易云的默认用户名(如「用户30223775」)基本都是用户上传的翻唱/搬运
  if (RegExp(r'^用户\d+$').hasMatch(artist.trim())) return true;
  return false;
}

/// 兼容旧名(语义已扩展为「非原版」)。
bool looksLikeCover({
  required String title,
  required String artist,
  String album = '',
}) =>
    looksLikeNonOriginal(title: title, artist: artist, album: album);

/// 排序得分:越高越像正版原唱。
int _originalScore(SongView song, String query) {
  var score = 0;
  final q = query.toLowerCase().trim();
  final artist = song.artist.toLowerCase();
  if (q.isNotEmpty && artist.isNotEmpty) {
    // 查询里的词命中歌手名(如「晴天 周杰伦」→ 周杰伦)
    for (final token in q.split(RegExp(r'\s+'))) {
      if (token.length >= 2 && artist.contains(token)) {
        score += 3;
        break;
      }
    }
  }
  if (song.album.trim().isNotEmpty) score += 1;
  if (looksLikeNonOriginal(
    title: song.title,
    artist: song.artist,
    album: song.album,
  )) {
    score -= 5;
  }
  return score;
}

/// 按「原唱优先」返回排序后的**下标顺序**(同分保持原有顺序)。
///
/// 返回下标而非条目本身,调用方可以直接把顺序套回原始列表,
/// 避免用「标题/歌手/专辑」拼 key 映射导致的丢条目问题。
List<int> rankSearchOrder(List<SongView> songs, {required String query}) {
  final indices = List<int>.generate(songs.length, (i) => i);
  indices.sort((a, b) {
    final sa = _originalScore(songs[a], query);
    final sb = _originalScore(songs[b], query);
    if (sa != sb) return sb.compareTo(sa);
    return a.compareTo(b); // 稳定:保持原顺序
  });
  return indices;
}

/// 过滤掉明显翻唱版本,返回保留下来的**下标**;
/// 若全被过滤则返回全集(不至于让用户搜不到任何东西)。
List<int> originalOnlyOrder(List<SongView> songs) {
  final kept = <int>[
    for (var i = 0; i < songs.length; i++)
      if (!looksLikeNonOriginal(
        title: songs[i].title,
        artist: songs[i].artist,
        album: songs[i].album,
      ))
        i,
  ];
  return kept.isEmpty ? List<int>.generate(songs.length, (i) => i) : kept;
}

/// 便捷封装:按「原唱优先」返回排好序的条目。
List<SongView> rankSearchResults(List<SongView> songs, {required String query}) =>
    [for (final i in rankSearchOrder(songs, query: query)) songs[i]];

/// 从查询里识别「歌手词」。
///
/// 候选词只可能来自用户输入的查询,因此判定门槛可以放低:命中歌手字段 ≥2 次
/// 即可视为歌手词(取命中最多的一组)。
/// 实测教训:网易云首屏 20 条里正版周杰伦只有 3~4 条(20%),若按「≥25% 比例」
/// 判定会识别不出歌手词,结果是翻唱全部漏过 —— 歌名与正版完全一样、只有歌手
/// 不同,除了歌手一致性没有别的信号可用。
Set<String> detectArtistTokens(List<SongView> songs, String query) {
  final tokens = _queryTokens(query);
  if (tokens.isEmpty || songs.length < 2) return const {};

  final hits = <String, int>{
    for (final t in tokens)
      t: songs.where((s) => s.artist.toLowerCase().contains(t)).length,
  };
  final maxHits = hits.values.reduce(math.max);
  if (maxHits < 2) return const {};
  // 保留命中最多的一组(通常是唯一歌手;多歌手查询会保留并列的多个)
  final threshold = math.max(2, (maxHits * 0.6).ceil());
  return {
    for (final e in hits.entries)
      if (e.value >= threshold) e.key,
  };
}

/// 歌手命中查询词的条目数(用于结果质量校验)。
int artistMatchCount(List<SongView> songs, String query) {
  final tokens = _queryTokens(query);
  if (tokens.isEmpty || songs.isEmpty) return songs.length;
  return songs
      .where((s) => tokens.any((t) => s.artist.toLowerCase().contains(t)))
      .length;
}

/// 结果里是否**至少有 1 条**歌手命中查询词。
///
/// 用于自动模式的结果质量校验:实测网易云搜「晴天 周杰伦」首屏 20 条全是翻唱号
/// (没有一条周杰伦),此时任何词/歌手过滤都无信号可用 —— 正确做法是换源
/// (腾讯音乐同一查询是干净的正版列表)。
bool anyArtistMatchesQuery(List<SongView> songs, String query) =>
    artistMatchCount(songs, query) > 0;

/// 结果质量是否合格:歌手命中占比 ≥ 25% 且至少 2 条。
///
/// 为什么不能只要求「1 条命中」:实测网易云搜「晴天 周杰伦」20 条里只有 1 条
/// 周杰伦(其余全是翻唱号),只判 1 条就会把整页翻唱当成合格结果返回。
bool isArtistMatchedResults(List<SongView> songs, String query) {
  final tokens = _queryTokens(query);
  if (tokens.isEmpty || songs.isEmpty) return true; // 无法判定时不拦
  final hits = artistMatchCount(songs, query);
  // 一条都不命中:无法判定(查询可能只是歌名,该词自然不出现在歌手字段)
  if (hits == 0) return true;
  // 有命中但占比过低(实测网易 20 条里只有 1 条):整页翻唱,换源
  return hits >= 2 && hits / songs.length >= 0.25;
}

List<String> _queryTokens(String query) => [
      for (final t in query.toLowerCase().split(RegExp(r'[\s,，、/|]+')))
        if (t.trim().length >= 2) t.trim(),
    ];

/// 只保留歌手与查询歌手一致的条目(返回下标)。
///
/// 仅在能识别出歌手词时生效;全部被排除或识别不出歌手词时不过滤,
/// 避免把「只搜歌名」这类查询误杀到空。
List<int> artistConsistentOrder(List<SongView> songs, String query) {
  final tokens = detectArtistTokens(songs, query);
  if (tokens.isEmpty) return List<int>.generate(songs.length, (i) => i);
  final kept = <int>[
    for (var i = 0; i < songs.length; i++)
      if (tokens.any((t) => songs[i].artist.toLowerCase().contains(t))) i,
  ];
  return kept.isEmpty ? List<int>.generate(songs.length, (i) => i) : kept;
}

/// 过滤后的**下标**(调用方按下标取回原始条目,避免拼 key 丢数据)。
///
/// [query] 非空时同时应用「歌手一致性」:歌名与正版完全相同、只有歌手不同的
/// 翻唱(实测网易首屏大量如此)只能靠查询里的歌手词识别。
List<int> filterOriginalIndices(List<SongView> songs, {String query = ''}) {
  final byMarker = originalOnlyOrder(songs);
  if (query.isEmpty) return byMarker;
  final subset = [for (final i in byMarker) songs[i]];
  return [for (final i in artistConsistentOrder(subset, query)) byMarker[i]];
}

/// 便捷封装:返回过滤翻唱后的条目。
List<SongView> filterOriginals(List<SongView> songs, {String query = ''}) =>
    [for (final i in filterOriginalIndices(songs, query: query)) songs[i]];
