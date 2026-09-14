import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/core/search/recommend.dart';
import 'package:musicx/models/lyric_line.dart';
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

  /// 当前歌曲歌词(解析后的时间行)。
  final List<LyricLine> lyric;

  const PlayerState({
    this.queue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.error,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.repeatMode = LoopMode.off,
    this.shuffle = false,
    this.lyric = const [],
  });

  MusicItem? get current => currentIndex >= 0 && currentIndex < queue.length
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
    List<LyricLine>? lyric,
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
      lyric: lyric ?? this.lyric,
    );
  }
}

final playerServiceProvider = Provider<PlayerService>((ref) {
  final service = PlayerService();
  ref.onDispose(service.dispose);
  return service;
});

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

class PlayerController extends Notifier<PlayerState> {
  final math.Random _rand = math.Random();
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  PlayerState build() {
    final service = ref.read(playerServiceProvider);
    _subs.add(
      service.positionStream.listen(
        (pos) => state = state.copyWith(position: pos),
      ),
    );
    _subs.add(
      service.playingStream.listen((playing) {
        if (state.isPlaying != playing) {
          state = state.copyWith(isPlaying: playing);
        }
      }),
    );
    _subs.add(
      service.durationStream.listen(
        (d) => state = state.copyWith(duration: d ?? Duration.zero),
      ),
    );
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
    _localPaths = null; // 切回在线队列
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
    if (index < 0 ||
        index >= state.queue.length ||
        index == state.currentIndex) {
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

  /// 播放本地下载的音频文件(不经过插件解析)。
  /// [paths] 与 [songs] 一一对应时整表作为队列连播(下一首/上一首在本表内循环);
  /// 不传则单曲队列。本地播放零网络解析,切歌近瞬时。
  Future<void> playLocal(
    MusicItem song,
    String filePath, {
    List<MusicItem>? songs,
    List<String>? paths,
  }) async {
    final queue = songs ?? [song];
    final pathList = paths ?? [filePath];
    final index = songs == null ? 0 : songs.indexOf(song);
    state = state.copyWith(
      queue: List.of(queue),
      currentIndex: index < 0 ? 0 : index,
      isPlaying: false,
      clearError: true,
      position: Duration.zero,
      duration: Duration.zero,
      lyric: const [],
    );
    _localPaths = pathList;
    try {
      await _playCurrentLocal();
    } catch (e) {
      if (e.toString().contains('Loading interrupted')) return;
      state = state.copyWith(error: e.toString());
    }
  }

  /// 与队列平行的本地文件路径;非 null 表示当前队列为本地播放模式。
  List<String>? _localPaths;

  Future<void> _playCurrentLocal() async {
    final current = state.current;
    final paths = _localPaths;
    if (current == null || paths == null) return;
    if (state.currentIndex >= paths.length) return;
    final service = ref.read(playerServiceProvider);
    await service.playUrl('file://${paths[state.currentIndex]}');
    state = state.copyWith(isPlaying: true, clearError: true);
  }

  /// 播放请求序号:新的播放请求会使旧的请求失效(避免打断误报)。
  int _playToken = 0;

  Future<void> _playCurrent() async {
    // 本地队列:直接播文件,不走插件解析
    if (_localPaths != null) {
      await _playCurrentLocal();
      return;
    }
    final current = state.current;
    if (current == null) return;
    // 记录播放历史:首页「猜你喜欢」按最常听的歌手做推荐(方案 C)
    try {
      ref.read(playHistoryProvider.notifier).record(current.toJson());
    } catch (_) {}
    final token = ++_playToken;
    try {
      final manager = ref.read(pluginManagerProvider);
      final media = await manager.resolveMediaSource(current.toJson());
      // 播放令牌:请求期间若已被更新请求取代(快速连点 next/切歌),放弃本次播放,
      // 避免旧歌在解析完成后覆盖/打断当前曲目。
      if (token != _playToken) return;
      final url = media['url'] as String;
      final service = ref.read(playerServiceProvider);
      await service.playUrl(url);
      if (token != _playToken) return;
      // 关键:先切到「播放中」并把歌词清空,歌词在后台再取。
      // 此前这里 await 歌词解析后才置为播放中,而歌词解析包含重试与跨源兜底
      // (要再发搜索请求),于是列表点击切歌要等歌词才生效 —— 用户体感「非常慢」。
      state = state.copyWith(
        isPlaying: true,
        clearError: true,
        lyric: const [],
      );
      // 后台预取下一首的播放地址:真正切歌时命中缓存,接近瞬时。
      _prefetchNext();
      // 歌词后台加载:完成后再校验 token,避免旧请求写入新请求的歌词。
      unawaited(_loadLyric(current, token));
    } catch (e) {
      if (token != _playToken) return;
      // 旧加载被新请求打断不算错误
      if (e.toString().contains('Loading interrupted')) return;
      state = state.copyWith(error: e.toString());
    }
  }

  /// 后台加载歌词:不阻塞切歌(播放状态已先行更新)。
  Future<void> _loadLyric(MusicItem song, int token) async {
    try {
      final manager = ref.read(pluginManagerProvider);
      final text = await manager.resolveLyric(song.toJson());
      if (token != _playToken) return; // 已切到别的歌,丢弃
      state = state.copyWith(lyric: parseLrc(text));
    } catch (_) {
      // 歌词失败不影响播放
    }
  }


  /// 预取下一首播放地址(配合 PluginManager 的媒体缓存,切歌零等待)。
  void _prefetchNext() {
    final idx = _advance(forward: true);
    if (idx == null) return;
    final upcoming = state.queue[idx];
    ref.read(pluginManagerProvider).prefetchMediaSource(upcoming.toJson());
  }
}
