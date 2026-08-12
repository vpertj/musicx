import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/models/music_item.dart';
import 'player_service.dart';

/// 播放循环模式:顺序 / 列表循环 / 单曲循环。
enum LoopMode { off, all, one }

class PlayerState {
  final List<MusicItem> queue;
  final int currentIndex;
  final bool isPlaying;
  final String? error;
  final Duration position;
  final Duration duration;
  final LoopMode repeatMode;
  final bool shuffle;

  const PlayerState({
    this.queue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.error,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.repeatMode = LoopMode.off,
    this.shuffle = false,
  });

  MusicItem? get current =>
      currentIndex >= 0 && currentIndex < queue.length
          ? queue[currentIndex]
          : null;

  PlayerState copyWith({
    List<MusicItem>? queue,
    int? currentIndex,
    bool? isPlaying,
    String? error,
    bool clearError = false,
    Duration? position,
    Duration? duration,
    LoopMode? repeatMode,
    bool? shuffle,
  }) {
    return PlayerState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      error: clearError ? null : (error ?? this.error),
      position: position ?? this.position,
      duration: duration ?? this.duration,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffle: shuffle ?? this.shuffle,
    );
  }
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
  final math.Random _rand = math.Random();
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  PlayerState build() {
    final service = ref.read(playerServiceProvider);
    _subs.add(service.positionStream.listen(
      (pos) => state = state.copyWith(position: pos),
    ));
    _subs.add(service.playingStream.listen((playing) {
      if (state.isPlaying != playing) {
        state = state.copyWith(isPlaying: playing);
      }
    }));
    _subs.add(service.durationStream.listen(
      (d) => state = state.copyWith(duration: d ?? Duration.zero),
    ));
    // 一首播完自动切下一首(遵循循环/随机模式)
    _subs.add(service.completedStream.listen((_) => next()));
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
    });
    return const PlayerState();
  }

  Future<void> playFromList(List<MusicItem> songs, int index) async {
    if (songs.isEmpty) return;
    state = state.copyWith(
      queue: List.of(songs),
      currentIndex: index,
      isPlaying: false,
      clearError: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    await _playCurrent();
  }

  /// 跳转到队列中的某一首。
  Future<void> playAt(int index) async {
    if (index < 0 || index >= state.queue.length || index == state.currentIndex) {
      return;
    }
    state = state.copyWith(
      currentIndex: index,
      isPlaying: false,
      clearError: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    await _playCurrent();
  }

  Future<void> togglePlay() async {
    if (state.current == null) return;
    final service = ref.read(playerServiceProvider);
    if (state.isPlaying) {
      await service.pause();
      state = state.copyWith(isPlaying: false);
    } else {
      await service.resume();
      state = state.copyWith(isPlaying: true);
    }
  }

  Future<void> next() async {
    final idx = _advance(forward: true);
    if (idx == null) return;
    state = state.copyWith(
      currentIndex: idx,
      isPlaying: false,
      clearError: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    await _playCurrent();
  }

  Future<void> previous() async {
    final idx = _advance(forward: false);
    if (idx == null) return;
    state = state.copyWith(
      currentIndex: idx,
      isPlaying: false,
      clearError: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    await _playCurrent();
  }

  Future<void> seek(Duration position) async {
    await ref.read(playerServiceProvider).seek(position);
    state = state.copyWith(position: position);
  }

  void toggleRepeat() {
    state = state.copyWith(
      repeatMode: switch (state.repeatMode) {
        LoopMode.off => LoopMode.all,
        LoopMode.all => LoopMode.one,
        LoopMode.one => LoopMode.off,
      },
    );
  }

  void toggleShuffle() => state = state.copyWith(shuffle: !state.shuffle);

  /// 计算下一首/上一首的下标;无可用下一首时返回 null(停在原处)。
  int? _advance({required bool forward}) {
    final n = state.queue.length;
    if (n == 0) return null;
    if (state.repeatMode == LoopMode.one) return state.currentIndex;
    if (state.shuffle && n > 1) {
      var idx = _rand.nextInt(n);
      while (idx == state.currentIndex) {
        idx = _rand.nextInt(n);
      }
      return idx;
    }
    final nextIdx = state.currentIndex + (forward ? 1 : -1);
    if (nextIdx < 0 || nextIdx >= n) {
      if (state.repeatMode == LoopMode.all) {
        return forward ? 0 : n - 1;
      }
      return null;
    }
    return nextIdx;
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
      state = state.copyWith(isPlaying: true, clearError: true);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}
