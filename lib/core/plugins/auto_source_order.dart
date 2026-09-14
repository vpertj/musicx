/// 自动模式(音源=自动)的音源分类、排序与去重(纯函数,便于单测)。
///
/// 为什么不能只看 platform:平台名是用户可改的。实际案例:网易云被改成
/// 「网yi」,关键词匹配就认不出来了,自动模式便无法把它排到最优位置。
/// 因此归类优先看**上游地址/文件名**(wy.js / tx.js / kw.js / kg.js),
/// 再看平台名关键词,最后才是未知。
///
/// 顺序依据实测(2026-09,每种源两条关键词):
///   网易云   搜索 336–367ms / 取流 187–241ms(官方 CDN)
///   腾讯音乐 搜索 435–450ms / 取流 1245–1626ms(经酷我 CDN 中转)
///   酷我念心 搜索 161–304ms / 取流 500–600ms
///   酷我独家 搜索 285–307ms / 取流 777–878ms
library;

/// 已知彻底失效、不参与自动搜索的音源(精确名)。
const Set<String> deadAutoSources = {
  '酷狗(独家音源)',
  '喜马拉雅(公开API)',
};

/// 音源类别。
enum SourceKind { netease, tencent, kuwo, kugou, other, dead }

/// 归类输入:平台名 + 上游地址 + 文件名(后两者可缺省)。
class SourceIdentity {
  const SourceIdentity({
    required this.platform,
    this.srcUrl = '',
    this.fileName = '',
  });

  final String platform;
  final String srcUrl;
  final String fileName;

  /// 归类用的合并文本(小写)。
  String get _haystack =>
      '$platform ${srcUrl.toLowerCase()} ${fileName.toLowerCase()}';
}

/// 归类:上游/文件名关键词优先,其次平台名关键词。
SourceKind classifySource(SourceIdentity id) {
  if (deadAutoSources.contains(id.platform)) return SourceKind.dead;
  final p = id.platform.toLowerCase();
  final hay = id._haystack;

  bool has(List<String> needles) => needles.any(hay.contains);

  if (p.contains('网易') || p.contains('netease') || has(['wy.js', 'netease'])) {
    return SourceKind.netease;
  }
  if (p.contains('腾讯') || p.contains('qq') || has(['tx.js', 'qqmusic'])) {
    return SourceKind.tencent;
  }
  if (p.contains('酷我') || p.contains('kuwo') || has(['kw.js', 'kuwo'])) {
    return SourceKind.kuwo;
  }
  if (p.contains('酷狗') || p.contains('kugou') || has(['kg.js', 'kugou'])) {
    return SourceKind.kugou;
  }
  if (p.contains('代理') || p.contains('proxy')) return SourceKind.other;
  return SourceKind.other;
}

/// 数值越小越优先;dead 恒排最后。
int autoSourcePriority(String platform) =>
    _kindPriority(classifySource(SourceIdentity(platform: platform)));

int _kindPriority(SourceKind kind) => switch (kind) {
      // 2026-09 实测(同一查询「晴天 周杰伦」,过滤后原版率/封面/歌词/取流):
      //   腾讯音乐   原版 22/30、封面 30/30、歌词 1388 字、取流 2021ms
      //   网易       原版  9/20(翻唱多)、封面 20/20、歌词 1076 字、取流 159ms
      //   酷我念心   原版 22/30、封面  3/30(几乎无封面)、歌词 1179 字、取流 28ms
      // 用户要求自动源「正版 + 有歌词 + 有封面」→ 腾讯排第一;
      // 搜不到/整页翻唱时由自动级联与质量校验继续试后面的源。
      SourceKind.tencent => 0,
      SourceKind.netease => 1,
      SourceKind.kuwo => 2,
      SourceKind.kugou => 3,
      SourceKind.other => 10,
      SourceKind.dead => 100,
    };

/// 代理型音源评分:同一主名下越高越优先保留。
int proxyScore(String platform) {
  final p = platform.toLowerCase();
  if (p.contains('念心') || p.contains('nxinxz') || p.contains('met')) {
    return 10;
  }
  if (p.contains('代理') || p.contains('proxy')) return 8;
  if (p == 'kuwo' || p.contains('酷我') || p.contains('kuwo')) return 3;
  return 0;
}

/// 自动搜索尝试顺序:过滤僵尸源 → 按类别排序 → 同主名去重(保留代理型)。
List<SourceIdentity> orderAutoSourceIdentities(List<SourceIdentity> sources) {
  final sorted = [
    for (final s in sources)
      if (classifySource(s) != SourceKind.dead) s,
  ]..sort(
      (a, b) => _kindPriority(classifySource(a))
          .compareTo(_kindPriority(classifySource(b))),
    );

  final result = <SourceIdentity>[];
  for (final source in sorted) {
    final base = source.platform.split('(').first.trim();
    if (base.isEmpty) {
      result.add(source);
      continue;
    }
    final idx = result.indexWhere(
      (e) => e.platform.split('(').first.trim() == base,
    );
    if (idx < 0) {
      result.add(source);
      continue;
    }
    if (proxyScore(source.platform) > proxyScore(result[idx].platform)) {
      result[idx] = source;
    }
  }
  return result;
}

/// 便捷版:只按平台名排序(无上游信息时使用)。
List<String> orderAutoSources(List<String> platforms) => orderAutoSourceIdentities([
      for (final p in platforms) SourceIdentity(platform: p),
    ]).map((e) => e.platform).toList();
