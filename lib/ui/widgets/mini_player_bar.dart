import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/widgets/artwork_view.dart';

/// 底部常驻迷你播放条:封面 + 歌名/歌手 + 播放暂停 + 播放进度条。
/// 点击封面/歌名区域展开全屏播放器。
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final song = state.current;
    if (song == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final progress = state.duration.inMilliseconds > 0
        ? (state.position.inMilliseconds / state.duration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    return Material(
      color: scheme.surfaceContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条(顶部细线,点击/拖动可跳转)
          // 用 LayoutBuilder 取迷你条实际宽度,避免桌面端(侧边栏旁)seek 偏差
          LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _seekTo(
                  context,
                  ref,
                  d.localPosition.dx,
                  constraints.maxWidth,
                ),
                onHorizontalDragUpdate: (d) => _seekTo(
                  context,
                  ref,
                  d.localPosition.dx,
                  constraints.maxWidth,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: .5,
                      ),
                    ),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: AppTheme.accentGradient,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onOpen,
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Hero(
                    tag: 'player-artwork',
                    child: ArtworkView(url: song.artwork, size: 44, radius: 10),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _fmt(state.position),
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: state.isPlaying ? '暂停' : '播放',
                    iconSize: 28,
                    icon: Icon(
                      state.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    onPressed: () => ref
                        .read(playerControllerProvider.notifier)
                        .togglePlay(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 按点击横向位置跳转播放进度。
  /// [width] 为迷你条实际宽度(桌面端侧边栏旁会小于屏幕宽)。
  static void _seekTo(
    BuildContext context,
    WidgetRef ref,
    double dx,
    double width,
  ) {
    final state = ref.read(playerControllerProvider);
    if (width <= 0 || state.duration.inMilliseconds <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    ref
        .read(playerControllerProvider.notifier)
        .seek(
          Duration(
            milliseconds: (state.duration.inMilliseconds * fraction).round(),
          ),
        );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
