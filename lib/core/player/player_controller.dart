import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/models/music_item.dart';
import 'player_service.dart';

class PlayerState {
  final List<MusicItem> queue;
  final int currentIndex;
  final bool isPlaying;
  final String? error;
  const PlayerState({
    this.queue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.error,
  });

  MusicItem? get current =>
      currentIndex >= 0 && currentIndex < queue.length
          ? queue[currentIndex]
          : null;
}

final playerServiceProvider = Provider<PlayerService>((ref) {
  final service = PlayerService();
  ref.onDispose(service.dispose);
  return service;
});

final pluginManagerProvider = Provider<PluginManager>((ref) {
  final dir = PluginManager.pluginsDir();
  return PluginManager(dir);
});

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

class PlayerController extends Notifier<PlayerState> {
  @override
  PlayerState build() => const PlayerState();

  Future<void> playFromList(List<MusicItem> songs, int index) async {
    state = PlayerState(queue: List.of(songs), currentIndex: index);
    await _playCurrent();
  }

  Future<void> togglePlay() async {
    final service = ref.read(playerServiceProvider);
    if (state.isPlaying) {
      await service.pause();
      state = PlayerState(
          queue: state.queue, currentIndex: state.currentIndex, isPlaying: false);
    } else {
      await service.resume();
      state = PlayerState(
          queue: state.queue, currentIndex: state.currentIndex, isPlaying: true);
    }
  }

  Future<void> next() async {
    if (state.currentIndex >= state.queue.length - 1) return;
    state = PlayerState(
        queue: state.queue, currentIndex: state.currentIndex + 1);
    await _playCurrent();
  }

  Future<void> previous() async {
    if (state.currentIndex <= 0) return;
    state = PlayerState(
        queue: state.queue, currentIndex: state.currentIndex - 1);
    await _playCurrent();
  }

  Future<void> seek(Duration position) async {
    await ref.read(playerServiceProvider).seek(position);
  }

  Future<void> _playCurrent() async {
    final current = state.current;
    if (current == null) return;
    try {
      final manager = ref.read(pluginManagerProvider);
      final media =
          await manager.resolveMediaSource(current.toJson());
      final url = media['url'] as String;
      final service = ref.read(playerServiceProvider);
      await service.playUrl(url);
      state = PlayerState(
          queue: state.queue,
          currentIndex: state.currentIndex,
          isPlaying: true);
    } catch (e) {
      state = PlayerState(
          queue: state.queue,
          currentIndex: state.currentIndex,
          error: e.toString());
    }
  }
}
