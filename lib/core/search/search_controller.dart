import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/models/music_item.dart';

export 'package:musicx/core/player/player_controller.dart'
    show pluginManagerProvider, pluginListProvider;
export 'package:musicx/core/plugins/plugin_manager.dart' show PluginManager;

class SearchState {
  final String query;
  final bool loading;
  final List<MusicItem> results;
  final String? error;

  /// 结果来自哪个音源;null 表示自动(任意插件)。
  final String? source;

  /// 当前已加载页数(分页加载)。
  final int page;
  const SearchState({
    this.query = '',
    this.loading = false,
    this.results = const [],
    this.error,
    this.source,
    this.page = 0,
  });

  SearchState copyWith({
    bool? loading,
    List<MusicItem>? results,
    String? error,
    int? page,
  }) {
    return SearchState(
      query: query,
      loading: loading ?? this.loading,
      results: results ?? this.results,
      error: error ?? this.error,
      source: source,
      page: page ?? this.page,
    );
  }
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

class SearchController extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  Future<void> search(String keyword, {String? source}) async {
    state = SearchState(query: keyword, loading: true, source: source);
    try {
      final manager = ref.read(pluginManagerProvider);
      final result = source == null
          ? await manager.search(keyword, page: 1)
          : await manager.search(keyword, platform: source, page: 1);
      final items = _parse(result);
      state = SearchState(
        query: keyword,
        results: items,
        source: source,
        page: 1,
      );
    } catch (e) {
      state = SearchState(query: keyword, error: e.toString(), source: source);
    }
  }

  /// 加载下一页(滚动到底部触发)。
  Future<void> loadMore() async {
    final s = state;
    if (s.loading || s.query.isEmpty) return;
    final nextPage = s.page + 1;
    state = s.copyWith(loading: true);
    try {
      final manager = ref.read(pluginManagerProvider);
      final result = s.source == null
          ? await manager.search(s.query, page: nextPage)
          : await manager.search(s.query, platform: s.source, page: nextPage);
      final items = _parse(result);
      state = s.copyWith(results: [...s.results, ...items], page: nextPage);
    } catch (_) {
      // 分页失败不打扰用户(已有结果),回到非加载态
      state = s.copyWith(loading: false);
    }
  }

  /// 过滤掉过短歌曲(试听/片段),避免搜索结果出现 30 秒试听等片段。
  /// 阈值 60s;时长缺失(<=0)的歌曲保留,避免误杀不返回时长字段的音源。
  static const int _minSongDurationMs = 60 * 1000;

  List<MusicItem> _parse(Map<String, dynamic> result) {
    final data = (result['data'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return data.map(MusicItem.fromJson).where((m) {
      final d = m.duration;
      if (d == null || d <= 0) return true; // 未知时长保留
      return d >= _minSongDurationMs;
    }).toList();
  }

  /// 清空搜索状态,回到空闲页。
  void reset() => state = const SearchState();
}
