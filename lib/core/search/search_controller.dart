import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/models/music_item.dart';

export 'package:musicx/core/player/player_controller.dart'
    show pluginManagerProvider;
export 'package:musicx/core/plugins/plugin_manager.dart' show PluginManager;

class SearchState {
  final String query;
  final bool loading;
  final List<MusicItem> results;
  final String? error;
  const SearchState({
    this.query = '',
    this.loading = false,
    this.results = const [],
    this.error,
  });
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

class SearchController extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  Future<void> search(String keyword) async {
    state = SearchState(query: keyword, loading: true);
    try {
      final manager = ref.read(pluginManagerProvider);
      final result = await manager.search(keyword);
      final data = (result['data'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final items = data.map(MusicItem.fromJson).toList();
      state = SearchState(query: keyword, results: items);
    } catch (e) {
      state = SearchState(query: keyword, error: e.toString());
    }
  }
}
