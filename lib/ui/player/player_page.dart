import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/utils/format.dart';
import 'package:musicx/models/lyric_line.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/widgets/artwork_view.dart';
import 'package:musicx/ui/widgets/seek_bar.dart';
import 'package:musicx/ui/widgets/song_tile.dart';

/// 全屏播放器。
/// [overlay] 为 true 时表示从迷你播放条以路由形式进入,顶部显示收起按钮。
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key, this.overlay = false});

  final bool overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final ctrl = ref.read(playerControllerProvider.notifier);
    final song = state.current;

    return Scaffold(
      extendBody: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF241B4A), Color(0xFF0D0A16)],
          ),
        ),
        child: SafeArea(
          child: song == null
              ? _EmptyPlayer(overlay: overlay)
              : _PlayerBody(state: state, ctrl: ctrl, overlay: overlay),
        ),
      ),
    );
  }
}

class _PlayerBody extends StatefulWidget {
  const _PlayerBody({
    required this.state,
    required this.ctrl,
    required this.overlay,
  });

  final PlayerState state;
  final PlayerController ctrl;
  final bool overlay;

  @override
  State<_PlayerBody> createState() => _PlayerBodyState();
}

class _PlayerBodyState extends State<_PlayerBody> {
  bool _showLyric = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final song = widget.state.current!;

    return Column(
      children: [
        _TopBar(overlay: widget.overlay),
        // 唱片 / 歌词 切换
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ViewToggle(
                icon: Icons.album_rounded,
                label: '唱片',
                selected: !_showLyric,
                onTap: () => setState(() => _showLyric = false),
              ),
              const SizedBox(width: 8),
              _ViewToggle(
                icon: Icons.lyrics_rounded,
                label: '歌词',
                selected: _showLyric,
                onTap: () => setState(() => _showLyric = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: _showLyric
              ? _LyricView(
                  lyric: widget.state.lyric,
                  position: widget.state.position,
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _Artwork(
                        song: song,
                        playing: widget.state.isPlaying,
                        compact: true,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 36),
                        child: Column(
                          children: [
                            Text(
                              song.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              [song.artist, song.album]
                                  .whereType<String>()
                                  .where((s) => s.isNotEmpty)
                                  .join(' · '),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (widget.state.error != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .error
                                      .withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '播放失败:${widget.state.error}',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: Column(
                          children: [
                            SeekBar(
                              position: widget.state.position,
                              duration: widget.state.duration,
                              onSeekEnd: widget.ctrl.seek,
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _TimeText(
                                      formatDuration(widget.state.position)),
                                  _TimeText(
                                      formatDuration(widget.state.duration)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      _Controls(
                        state: widget.state,
                        ctrl: widget.ctrl,
                      ),
                      const SizedBox(height: 2),
                      TextButton.icon(
                        onPressed: () => _showQueue(context),
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                        ),
                        icon: const Icon(Icons.queue_music_rounded, size: 18),
                        label:
                            Text('播放队列 (${widget.state.queue.length})'),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  static void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _QueueSheet(),
    );
  }
}

/// 唱片 / 歌词 视图切换按钮。
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? AppTheme.violet : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16,
                  color: selected ? Colors.white : scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected
                          ? Colors.white
                          : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 歌词视图:滚动高亮当前行。
class _LyricView extends StatefulWidget {
  const _LyricView({required this.lyric, required this.position});

  final List<LyricLine> lyric;
  final Duration position;

  @override
  State<_LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<_LyricView> {
  final ScrollController _scroll = ScrollController();

  int get _currentIndex {
    var idx = -1;
    for (var i = 0; i < widget.lyric.length; i++) {
      if (widget.lyric[i].time <= widget.position) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  @override
  void didUpdateWidget(covariant _LyricView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final idx = _currentIndex;
    if (idx >= 0 && _scroll.hasClients) {
      final target = (idx * 44.0) - 100;
      if (target >= 0) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (widget.lyric.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lyrics_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 14),
            Text(
              '暂无歌词',
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    final idx = _currentIndex;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 100),
      itemCount: widget.lyric.length,
      itemBuilder: (context, i) {
        final current = i == idx;
        return AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: textTheme.bodyLarge!.copyWith(
            fontSize: current ? 18 : 15,
            fontWeight: current ? FontWeight.w700 : FontWeight.w400,
            color: current ? scheme.primary : scheme.onSurfaceVariant,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 40),
            child: Text(
              widget.lyric[i].text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }
}

/// 顶部栏:overlay 模式显示收起按钮,标题“正在播放”居中/居左。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.overlay});

  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = Text(
      '正在播放',
      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SizedBox(
        height: 48,
        child: overlay
            ? Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: '收起',
                      iconSize: 30,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  Center(child: title),
                  // 右侧占位,保持标题视觉居中
                  const Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(width: 48),
                  ),
                ],
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: title,
                ),
              ),
      ),
    );
  }
}

/// 网易云式旋转唱片:圆形封面 + 播放旋转 / 暂停停转 + 背景光晕。
class _Artwork extends StatefulWidget {
  const _Artwork({
    required this.song,
    required this.playing,
    this.compact = false,
  });

  final MusicItem song;
  final bool playing;

  /// 紧凑模式:缩小唱片尺寸,适配矮窗口。
  final bool compact;

  @override
  State<_Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<_Artwork> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    if (widget.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _Artwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.playing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.compact ? 240.0 : 300.0;
    final halo = widget.compact ? 280.0 : 360.0;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: box,
        height: box,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 背景光晕
            Container(
              width: halo,
              height: halo,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.violet.withValues(alpha: .40),
                    AppTheme.pink.withValues(alpha: .14),
                    Colors.transparent,
                  ],
                  stops: const [0, .55, 1],
                ),
              ),
            ),
            // 旋转唱片
            RotationTransition(
              turns: _spin,
              child: _Disc(song: widget.song, size: widget.compact ? 230 : 280),
            ),
          ],
        ),
      ),
    );
  }
}

/// 唱片本体:圆形封面 + CD 外圈 + 轴心孔。
class _Disc extends StatelessWidget {
  const _Disc({required this.song, this.size = 280});

  final MusicItem song;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .45),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'player-artwork',
              child: ArtworkView(url: song.artwork, size: size, radius: 0),
            ),
            // CD 外圈高光环
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .18),
                  width: 6,
                ),
              ),
            ),
            // 唱片内圈细环
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black.withValues(alpha: .25),
                  width: 28,
                ),
              ),
            ),
            // 轴心孔(播放时高亮)
            Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surfaceDarkHi,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .5),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF3E3557),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 控制区:随机 / 上一首 / 播放暂停 / 下一首 / 循环。
class _Controls extends StatelessWidget {
  const _Controls({required this.state, required this.ctrl});

  final PlayerState state;
  final PlayerController ctrl;

  @override
  Widget build(BuildContext context) {
    final canPrev = state.currentIndex > 0 ||
        state.repeatMode != LoopMode.off ||
        state.shuffle;
    final canNext = state.currentIndex < state.queue.length - 1 ||
        state.repeatMode != LoopMode.off ||
        state.shuffle;
    final repeatLabel = switch (state.repeatMode) {
      LoopMode.off => '顺序播放',
      LoopMode.all => '列表循环',
      LoopMode.one => '单曲循环',
    };
    final repeatIcon = switch (state.repeatMode) {
      LoopMode.one => Icons.repeat_one_rounded,
      _ => Icons.repeat_rounded,
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundToggle(
          tooltip: '随机播放',
          icon: Icons.shuffle_rounded,
          active: state.shuffle,
          onPressed: ctrl.toggleShuffle,
        ),
        const SizedBox(width: 18),
        IconButton(
          tooltip: '上一首',
          iconSize: 42,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: canPrev ? ctrl.previous : null,
        ),
        const SizedBox(width: 12),
        _PlayButton(playing: state.isPlaying, onPressed: ctrl.togglePlay),
        const SizedBox(width: 12),
        IconButton(
          tooltip: '下一首',
          iconSize: 42,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: canNext ? ctrl.next : null,
        ),
        const SizedBox(width: 18),
        _RoundToggle(
          tooltip: repeatLabel,
          icon: repeatIcon,
          active: state.repeatMode != LoopMode.off,
          onPressed: ctrl.toggleRepeat,
        ),
      ],
    );
  }
}

class _RoundToggle extends StatelessWidget {
  const _RoundToggle({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(
        icon,
        size: 22,
        color: active ? AppTheme.pink : scheme.onSurfaceVariant,
      ),
      onPressed: onPressed,
    );
  }
}

/// 大号渐变播放 / 暂停键。
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.violet.withValues(alpha: .55),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Ink(
          width: 74,
          height: 74,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppTheme.accentGradient,
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 42,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeText extends StatelessWidget {
  const _TimeText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 播放队列底部弹层:跟随播放状态实时高亮当前曲目。
class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final ctrl = ref.read(playerControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: Row(
              children: [
                Text(
                  '播放队列',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${state.queue.length} 首',
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Flexible(
            child: state.queue.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        '队列为空,去搜索页添加歌曲吧',
                        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: state.queue.length,
                    itemBuilder: (context, i) {
                      final s = state.queue[i];
                      final isCurrent = i == state.currentIndex;
                      return SongTile(
                        song: s,
                        highlighted: isCurrent,
                        onTap: () => ctrl.playAt(i),
                        trailing: isCurrent
                            ? Icon(Icons.volume_up_rounded,
                                size: 20, color: scheme.primary)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 空态:尚未播放任何歌曲。
class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer({required this.overlay});

  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (overlay)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: '收起',
              iconSize: 30,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.violet.withValues(alpha: .45),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    size: 48,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '暂无播放内容',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  '去搜索页发现好音乐吧',
                  style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
