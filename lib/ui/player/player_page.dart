import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/utils/format.dart';
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

class _PlayerBody extends StatelessWidget {
  const _PlayerBody({
    required this.state,
    required this.ctrl,
    required this.overlay,
  });

  final PlayerState state;
  final PlayerController ctrl;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final song = state.current!;

    return Column(
      children: [
        _TopBar(overlay: overlay),
        Expanded(
          flex: 5,
          child: Center(child: _Artwork(song: song)),
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
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            children: [
              SeekBar(
                position: state.position,
                duration: state.duration,
                onSeekEnd: ctrl.seek,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _TimeText(formatDuration(state.position)),
                    _TimeText(formatDuration(state.duration)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _Controls(state: state, ctrl: ctrl),
        const SizedBox(height: 2),
        TextButton.icon(
          onPressed: () => _showQueue(context),
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          ),
          icon: const Icon(Icons.queue_music_rounded, size: 18),
          label: Text('播放队列 (${state.queue.length})'),
        ),
        const SizedBox(height: 10),
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

/// 顶部栏:收起按钮(overlay 模式) + 队列入口。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.overlay});

  final bool overlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          if (overlay)
            IconButton(
              tooltip: '收起',
              iconSize: 30,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          const Spacer(),
          IconButton(
            tooltip: '播放队列',
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: () => _PlayerBody._showQueue(context),
          ),
        ],
      ),
    );
  }
}

/// 封面 + 背景光晕(Hero 动画标签与迷你播放条一致)。
class _Artwork extends StatelessWidget {
  const _Artwork({required this.song});

  final MusicItem song;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: 300,
        height: 300,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 360,
              height: 360,
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
            Hero(
              tag: 'player-artwork',
              child: ArtworkView(
                url: song.artwork,
                size: 280,
                radius: 30,
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
