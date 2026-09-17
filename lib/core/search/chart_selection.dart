/// 排行榜选择的纯逻辑(便于单测)。
///
/// 背景:插件返回的榜单顺序由音源接口决定,并不稳定 —— 有的源第一个是
/// 「热歌榜」,有的第一个是「会员飙升榜」甚至「万物DJ榜」。此前首页盲取
/// 第一个(且把 6 个子榜全塞进芯片行),用户看到的可能根本不是热歌榜,
/// 而区块标题又固定写死为「热门推荐」,于是产生「热歌不是热歌、
/// 新歌不是新歌」的感受。
///
/// 这里按**名称关键词**优先挑选用户最可能想要的那类榜单,并限定芯片数量。
library;

/// 优先匹配合唱的关键词,按优先级从高到低。
///
/// 注意顺序:「热歌」优先于「飙升」,「新歌」次之 —— 首页默认展示热歌榜
/// 最符合直觉。匹配时要求榜单名**同时**含前缀限定(如无)与关键词;
/// 关键词本身足以区分,故直接按子串匹配。
const List<String> kPreferredChartKeywords = [
  '热歌榜',
  '热歌',
  '飙升榜',
  '新歌榜',
  '新歌',
];

/// 从榜单列表里挑出「首页默认展示」的那一个,返回其下标。
///
/// - [lists] 每项需含 `title` 字段(插件已展平,title 为具体榜单名)。
/// - 按 [kPreferredChartKeywords] 顺序找第一个命中的;都没命中则返回 0
///   (保持原有行为,不因匹配失败而空着)。
///
/// 纯函数,便于测试各种音源命名差异。
int pickDefaultChartIndex(
  List<Map<String, dynamic>> lists, {
  List<String> keywords = kPreferredChartKeywords,
}) {
  if (lists.isEmpty) return 0;
  for (final kw in keywords) {
    final idx = lists.indexWhere((e) {
      final title = '${e['title'] ?? ''}';
      return title.contains(kw);
    });
    if (idx >= 0) return idx;
  }
  return 0;
}

/// 首页芯片最多展示几个榜单(避免堆一排)。
const int kMaxChartChips = 6;

/// 选取要展示的榜单子集。
///
/// 关键:**把默认选中的那个榜放在第一个位置**,这样芯片行里它就是高亮的
/// 第一个,用户在视觉上能立刻对上「我在看哪个榜」。其余按原顺序补足到
/// [kMaxChartChips] 个。
List<Map<String, dynamic>> selectChartsForHome(
  List<Map<String, dynamic>> lists, {
  int max = kMaxChartChips,
  List<String> keywords = kPreferredChartKeywords,
}) {
  if (lists.isEmpty) return const [];
  final preferred = pickDefaultChartIndex(lists, keywords: keywords);
  final out = <Map<String, dynamic>>[lists[preferred]];
  for (var i = 0; i < lists.length && out.length < max; i++) {
    if (i == preferred) continue;
    out.add(lists[i]);
  }
  return out;
}
