import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:musicx/core/utils/app_paths.dart';

/// 播放历史(本地,用于「猜你喜欢」)。
///
/// 只记歌名/歌手/平台等最小信息,按最近播放排序并去重,上限 [maxEntries]。
class PlayHistoryController extends Notifier<List<Map<String, dynamic>>> {
  static const int maxEntries = 300;

  @override
  List<Map<String, dynamic>> build() {
    try {
      final f = AppPaths.file('play_history.json');
      if (!f.existsSync()) return const [];
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 记录一次播放(同一首歌去重并置顶)。
  void record(Map<String, dynamic> song) {
    final key = _keyOf(song);
    if (key.isEmpty) return;
    final next = [
      song,
      for (final s in state)
        if (_keyOf(s) != key) s,
    ];
    state = next.length > maxEntries ? next.sublist(0, maxEntries) : next;
    _persist();
  }

  void clear() {
    state = const [];
    _persist();
  }

  void _persist() {
    try {
      AppPaths.file('play_history.json')
          .writeAsStringSync(jsonEncode(state), flush: true);
    } catch (_) {}
  }

  static String _keyOf(Map<String, dynamic> song) =>
      '${song['platform'] ?? ''}|${song['songId'] ?? song['id'] ?? ''}|'
      '${song['title'] ?? ''}';
}

final playHistoryProvider =
    NotifierProvider<PlayHistoryController, List<Map<String, dynamic>>>(
      PlayHistoryController.new,
    );

/// 从播放历史里取最常听的歌手(按次数排序)。
///
/// 纯函数,便于单测:过滤空歌手、按次数降序、同次数按首次出现顺序稳定。
List<String> topArtistsFromHistory(
  List<Map<String, dynamic>> history, {
  int limit = 3,
}) {
  final counts = <String, int>{};
  final firstSeen = <String, int>{};
  for (var i = 0; i < history.length; i++) {
    final artist = '${history[i]['artist'] ?? ''}'.trim();
    if (artist.isEmpty) continue;
    // 多歌手只取第一位,避免「A&B」被当成独立歌手
    final primary = artist.split(RegExp(r'[&、,，/]')).first.trim();
    if (primary.isEmpty) continue;
    counts[primary] = (counts[primary] ?? 0) + 1;
    firstSeen.putIfAbsent(primary, () => i);
  }
  final names = counts.keys.toList()
    ..sort((a, b) {
      final c = counts[b]!.compareTo(counts[a]!);
      return c != 0 ? c : firstSeen[a]!.compareTo(firstSeen[b]!);
    });
  return names.take(limit).toList();
}

/// 合并多个来源的推荐结果:按标题+歌手去重,保持先后顺序。
List<Map<String, dynamic>> mergeRecommendations(
  List<List<Map<String, dynamic>>> groups, {
  int limit = 12,
}) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final group in groups) {
    for (final song in group) {
      final key =
          '${song['title'] ?? ''}|${song['artist'] ?? ''}'.toLowerCase();
      if (key == '|' || !seen.add(key)) continue;
      out.add(song);
      if (out.length >= limit) return out;
    }
  }
  return out;
}

/// 首页推荐数据:热歌榜 + 猜你喜欢。
class RecommendService {
  RecommendService(this._load);

  /// 注入式取数(便于单测):kind → 结果。
  final Future<List<Map<String, dynamic>>> Function(String kind, String? seed)
      _load;

  Future<List<Map<String, dynamic>>> hot({int limit = 12}) async =>
      _load('hot', null);

  Future<List<Map<String, dynamic>>> guess({
    required List<String> artists,
    int limit = 12,
  }) async {
    if (artists.isEmpty) return const [];
    final groups = <List<Map<String, dynamic>>>[];
    for (final artist in artists) {
      groups.add(await _load('artist', artist));
    }
    return mergeRecommendations(groups, limit: limit);
  }
}

/// 首页推荐结果缓存(内存,TTL 内不重复请求源站)。
class RecommendCache {
  RecommendCache({this.ttl = const Duration(minutes: 10)});

  final Duration ttl;
  final Map<String, (DateTime, List<Map<String, dynamic>>)> _store = {};

  List<Map<String, dynamic>>? get(String key) {
    final hit = _store[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.$1) > ttl) {
      _store.remove(key);
      return null;
    }
    return hit.$2;
  }

  void put(String key, List<Map<String, dynamic>> value) {
    _store[key] = (DateTime.now(), value);
  }

  /// 清空缓存(音源变化等需要强制重载时使用)。
  void clear() => _store.clear();
}
