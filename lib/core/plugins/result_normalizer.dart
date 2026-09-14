/// 插件结果归一化(纯函数,便于单测)。
///
/// MusicFree 协议约定 `duration` 为**毫秒**,但实际生态里并非所有插件都遵守:
/// 例如腾讯音乐 `tx.js` 返回 `269`(269 秒)。宿主若按毫秒处理,会把这些歌
/// 当成「不足 60 秒的试听片段」在搜索页被过滤掉,表现就是「这个源搜不到歌」。
/// 真实歌曲时长集中在 30–900 秒,因此 `0 < v < 1000` 的数值几乎必然是秒。
library;

/// 把可能的「秒」换算成毫秒;已是毫秒、缺失或非法值原样返回。
/// 数字字符串会被解析为数值返回(顺带统一类型)。
Object? normalizeDurationMs(Object? raw) {
  num? value;
  if (raw is num) {
    value = raw;
  } else if (raw is String) {
    value = num.tryParse(raw);
  }
  if (value == null) return raw;
  if (value <= 0) return value;
  if (value >= 1000) return value;
  return (value * 1000).round();
}

/// 归一化单条搜索结果:
/// - 始终用当前插件名覆盖 `platform`(插件内硬编码的旧名不参与路由)
/// - 补全宿主约定的 `songId`(MusicFree 由宿主填充)
/// - 修正 `duration` 量纲
void normalizeResultItem(
  Map<dynamic, dynamic> item, {
  required String platform,
}) {
  // 先把插件原始字段整体存进 extra:MusicItem 只保留固定字段,
  // 插件专属字段(如腾讯音乐的 songmid/strMediaMid、酷我的 albumId)在
  // 往返后会丢失,导致 getLyric/getMediaSource 拿到 undefined 而失败。
  // 实测:腾讯音乐歌词接口依赖 songmid,丢失后歌词页显示「暂无歌词」。
  if (item['extra'] is! Map || (item['extra'] as Map).isEmpty) {
    item['extra'] = Map<String, dynamic>.from(item);
  }
  item['platform'] = platform;
  final songId = item['songId'];
  if (songId is! String || songId.isEmpty) {
    item['songId'] = item['id'];
  }
  item['duration'] = normalizeDurationMs(item['duration']);
}

/// 调用插件前把 extra 里保存的原始字段还原到条目上。
///
/// 条目自身的字段优先(宿主补全/修正过的值不能被旧值覆盖),
/// extra 只补空缺。没有 extra 时原样返回(不复制,避免无谓开销)。
Map<String, dynamic> pluginItem(Map<String, dynamic> item) {
  final extra = item['extra'];
  if (extra is! Map || extra.isEmpty) return item;
  return {
    for (final e in extra.entries) '${e.key}': e.value,
    ...item,
  };
}
