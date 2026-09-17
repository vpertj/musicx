import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/download/lyric_sidecar.dart';
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

  /// 正在解析/起播(切歌中的加载反馈,让用户知道已经响应了点击)。
  final bool isLoading;
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
    this.isLoading = false,
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
    bool? isLoading,
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
      isLoading: isLoading ?? this.isLoading,
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
      service.positionStream.listen((pos) {
        // 播完兜底:我们的音频都经第三方中转(如念心),这类流的
        // processingState 往往不会变成 completed → 控制器收不到「播完」事件,
        // 结果一首放完就停在原地(用户反馈)。这里用「播放位置到达时长」判定,
        // 逻辑上等价于播完;next() 自身遵守循环/随机模式。
        if (_maybeAutoAdvance(pos)) return;
        state = state.copyWith(position: pos);
      }),
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
    // 一首播完自动切下一首(遵循循环/随机模式)。
    // 用 _advanceAuto 而非 next():单曲循环下必须重播当前曲。
    _subs.add(service.completedStream.listen((_) => _advanceAuto()));
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
    });
    return const PlayerState();
  }

  /// 已判定「播完」并触发过自动切歌的播放令牌(避免同一次播放重复触发)。
  final Set<int> _autoAdvancedTokens = <int>{};

  /// 位置到达时长 → 视为播完并切下一首。返回 true 表示已处理(调用方别再用该位置)。
  bool _maybeAutoAdvance(Duration pos) {
    final total = state.duration;
    if (total <= Duration.zero) return false;
    // 留 900ms 余量:部分流的最后一段位置更新早于真正结束
    if (pos < total - const Duration(milliseconds: 900)) return false;
    final token = _playToken;
    if (!_autoAdvancedTokens.add(token)) return true;
    if (_autoAdvancedTokens.length > 32) {
      _autoAdvancedTokens.remove(_autoAdvancedTokens.first);
    }
    unawaited(_advanceAuto());
    return true;
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
    await _goTo(idx);
  }

  Future<void> previous() async {
    final idx = _advance(forward: false);
    if (idx == null) return;
    await _goTo(idx);
  }

  /// **自动**推进到下一首(当前曲播完时触发)。
  ///
  /// 与 [next] 的区别:单曲循环下应重播当前曲,而不是跳到队列下一首。
  /// 两条自动触发路径(completedStream 与位置兜底)都必须走这里。
  ///
  /// **失败兜底**:起播失败(解析失败/流地址失效/网络错误)时自动跳过失败
  /// 歌曲,继续尝试后续歌曲 —— 否则一首坏了整个队列就停住(用户实测:
  /// 「第一首播完,切下一首时播放失败」就再也不动了)。最多尝试整队一遍,
  /// 避免坏队列无限打源站;全部失败才真正停下并保留错误提示。
  Future<void> _advanceAuto() async {
    final n = state.queue.length;
    if (n == 0) return;
    var idx = _advance(forward: true, auto: true);
    var attempts = 0;
    while (idx != null && attempts < n) {
      attempts++;
      final ok = await _goTo(idx);
      if (ok) return;
      // 这一首失败:跳过它,试下一首(单曲循环重播失败时也顺延到下一首,
      // 避免无限重播同一首失败的歌)。
      idx = (idx + 1) % n;
    }
  }

  /// 切到指定下标并起播(手动切歌与自动推进共用)。
  ///
  /// 返回是否起播成功;失败时已把错误写入状态(手动操作展示给用户,
  /// 自动推进则据此跳过)。
  Future<bool> _goTo(int idx) async {
    state = state.copyWith(
      currentIndex: idx,
      isPlaying: false,
      clearError: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    return _playCurrent();
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
  ///
  /// [auto] 区分两种调用场景,二者语义不同:
  ///   - `auto: true`(一首**自动播完**):单曲循环应重播当前曲;
  ///   - `auto: false`(用户**手动**点上一首/下一首):单曲循环不该拦住换歌,
  ///     否则用户点下一首毫无反应(实测缺陷)。
  int? _advance({required bool forward, bool auto = false}) {
    final n = state.queue.length;
    if (n == 0) return null;
    // 仅"自动播完"时,单曲循环才重播同一首。
    if (auto && state.repeatMode == LoopMode.one) return state.currentIndex;
    if (state.shuffle && n > 1) {
      var idx = _rand.nextInt(n);
      while (idx == state.currentIndex) {
        idx = _rand.nextInt(n);
      }
      return idx;
    }
    final nextIdx = state.currentIndex + (forward ? 1 : -1);
    if (nextIdx < 0 || nextIdx >= n) {
      // 手动切歌时:单曲循环也视为"会循环"的模式,边界绕回另一端,
      // 与列表循环一致 —— 否则在首/尾点上一首/下一首会毫无反应。
      final loops = state.repeatMode == LoopMode.all ||
          (state.repeatMode == LoopMode.one && !auto);
      if (loops) {
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
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 与队列平行的本地文件路径;非 null 表示当前队列为本地播放模式。
  List<String>? _localPaths;

  Future<bool> _playCurrentLocal() async {
    final current = state.current;
    final paths = _localPaths;
    if (current == null || paths == null) return false;
    if (state.currentIndex >= paths.length) return false;
    // 本地(已下载)播放同样计入播放历史,否则只播下载歌曲的用户首页永远
    // 没有「最近播放」(实测缺口)。
    try {
      ref.read(playHistoryProvider.notifier).record(current.toJson());
    } catch (_) {}
    final service = ref.read(playerServiceProvider);
    final path = paths[state.currentIndex];
    await service.playUrl('file://$path');
    // 本地播放优先用**下载时存的旁挂歌词**(离线也有词);没有则不显示歌词,
    // 也不再联网找(本地播放应完全离线可用)。
    final sidecar = await readLyricSidecar(path);
    final lyric = sidecar == null ? const <LyricLine>[] : parseLrc(sidecar);
    debugPrint(
      'MusicX 本地歌词: ${lyric.isEmpty ? "无旁挂歌词" : "${lyric.length} 行"} ← $path',
    );
    state = state.copyWith(isPlaying: true, clearError: true, lyric: lyric);
    return true;
  }

  /// 播放请求序号:新的播放请求会使旧的请求失效(避免打断误报)。
  int _playToken = 0;

  /// 播放当前曲。
  ///
  /// 返回是否起播成功。**自动推进依赖这个结果做失败跳过**(见 [_advanceAuto]);
  /// 手动切歌失败时错误已写入状态展示给用户,由用户决定下一步。
  Future<bool> _playCurrent() async {
    // 本地队列:直接播文件,不走插件解析
    if (_localPaths != null) {
      return _playCurrentLocal();
    }
    final current = state.current;
    if (current == null) return false;
    // 记录播放历史:首页「猜你喜欢」按最常听的歌手做推荐(方案 C)
    try {
      ref.read(playHistoryProvider.notifier).record(current.toJson());
    } catch (_) {}
    final token = ++_playToken;
    // 点击即刻给出「加载中」反馈:否则用户点完列表到出声之间毫无反应,
    // 体感就是「切歌很慢」(实测取流+起播要 0.4~2s)。
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final manager = ref.read(pluginManagerProvider);
      final media = await manager.resolveMediaSource(current.toJson());
      // 播放令牌:请求期间若已被更新请求取代(快速连点 next/切歌),放弃本次播放,
      // 避免旧歌在解析完成后覆盖/打断当前曲目。
      if (token != _playToken) return false;
      final url = media['url'] as String;
      // 先发下一首预取(与播放器初始化并行),再起播 —— 缩短下一首的切换时间
      _prefetchNext();
      final service = ref.read(playerServiceProvider);
      await service.playUrl(url);
      if (token != _playToken) return false;
      // 关键:先切到「播放中」并把歌词清空,歌词在后台再取。
      // 此前这里 await 歌词解析后才置为播放中,而歌词解析包含重试与跨源兜底
      // (要再发搜索请求),于是列表点击切歌要等歌词才生效 —— 用户体感「非常慢」。
      state = state.copyWith(
        isPlaying: true,
        isLoading: false,
        clearError: true,
        lyric: const [],
      );
      // 歌词后台加载:完成后再校验 token,避免旧请求写入新请求的歌词。
      unawaited(_loadLyric(current, token));
      return true;
    } catch (e) {
      if (token != _playToken) return false;
      // 旧加载被新请求打断不算错误
      if (e.toString().contains('Loading interrupted')) return false;
      state = state.copyWith(error: e.toString(), isLoading: false);
      return false;
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
  ///
  /// 用 `auto: true`:这里预测的是**当前曲自动播完**后会播哪首,
  /// 因此单曲循环下预取的应是当前曲自己(而不是队列里的下一首)。
  void _prefetchNext() {
    final idx = _advance(forward: true, auto: true);
    if (idx == null) return;
    final upcoming = state.queue[idx];
    ref.read(pluginManagerProvider).prefetchMediaSource(upcoming.toJson());
  }
}
