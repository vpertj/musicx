/// 翻唱/非原唱识别与排序(纯函数,便于单测)。
///
/// 用户诉求:内置音源里不要翻唱,尽量都是正版原唱。各音源(尤其网易云)
/// 搜索结果前排常混入用户上传的翻唱、伴奏、纯音乐、DJ 版,这些在标题/专辑/
/// 歌手名上通常有明显特征词,可以直接识别。
///
/// 设计取舍:
/// - 只把**强特征**(翻唱/cover/伴奏/纯音乐/女声版/DJ版/片段…)判为翻唱并隐藏;
/// - `Live`/`remix`/`合唱` 属于正常发行形式,只降权不隐藏;
/// - 过滤后若结果为空,则回退不过滤(否则用户会「搜不到任何东西」)。
library;

/// 判定为翻唱的强特征词(小写匹配)。
const List<String> _coverMarkers = [
  '翻唱',
  'cover',
  '伴奏',
  '纯音乐',
  'instrumental',
  'karaoke',
  '女声版',
  '男声版',
  '童声版',
  '钢琴版',
  '吉他版',
  '古筝版',
  '二胡版',
  '口琴版',
  '八音盒',
  '抖音版',
  '快手版',
  'dj版',
  '加速版',
  '慢速版',
  '改编版',
  '清唱',
  '片段',
  'tribute',
];

/// 非原版但不算翻唱,仅降权。
const List<String> _nonOriginalMarkers = ['live', 'remix', '现场', '演唱会'];

/// 简易条目视图(避免与 MusicItem 耦合,便于单测)。
typedef SongView = ({String title, String artist, String album});

bool _hasMarker(String text, List<String> markers) {
  final t = text.toLowerCase();
  return markers.any(t.contains);
}

/// 是否明显是翻唱/非原唱版本。
bool looksLikeCover({
  required String title,
  required String artist,
  String album = '',
}) {
  if (_hasMarker(title, _coverMarkers)) return true;
  if (album.isNotEmpty && _hasMarker(album, _coverMarkers)) return true;
  if (_hasMarker(artist, _coverMarkers)) return true;
  return false;
}

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
  if (_hasMarker('${song.title}${song.album}', _nonOriginalMarkers)) score -= 2;
  if (looksLikeCover(title: song.title, artist: song.artist, album: song.album)) {
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
      if (!looksLikeCover(
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

/// 便捷封装:返回过滤翻唱后的条目。
List<SongView> filterOriginals(List<SongView> songs) =>
    [for (final i in originalOnlyOrder(songs)) songs[i]];
