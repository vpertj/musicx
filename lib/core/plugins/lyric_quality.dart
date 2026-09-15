/// 歌词可用性判定(纯函数,便于单测)。
///
/// 用户诉求:「播放时应该检测这首歌有没有歌词,没有就主动去找」。
/// 实测坑:不少音源在无歌词时会返回**占位文本**(如 `[00:00.00]暂无歌词`、
/// `纯音乐,请欣赏`),这类内容非空,若直接当成歌词返回,跨源兜底就永远不会
/// 触发,用户看到的就是「暂无歌词」。
library;

/// 判定歌词文本是否**真的可用**:非空、不是占位文案、且至少有一行带时间戳。
bool hasUsableLyric(String? text) {
  if (text == null) return false;
  final t = text.trim();
  if (t.isEmpty) return false;
  for (final marker in _placeholders) {
    if (t.contains(marker)) return false;
  }
  // 必须至少有一行形如 [mm:ss] 或 [ss.xx] 的歌词行
  return _timestampRe.hasMatch(t);
}

/// 常见占位文案(小写匹配)。
const List<String> _placeholders = [
  '暂无歌词',
  '没有歌词',
  '歌词获取失败',
  '纯音乐,请欣赏',
  '纯音乐，请欣赏',
  '此歌曲为没有填词的纯音乐',
  '没有填词',
  '该歌曲暂无歌词',
  'no lyric',
  'lyric not found',
];

final RegExp _timestampRe = RegExp(r'\[\d{1,3}(:\d{1,2})?(\.\d{1,3})?\]');
