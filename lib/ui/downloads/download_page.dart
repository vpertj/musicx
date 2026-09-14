import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/download/download_controller.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/utils/open_external.dart';
import 'package:musicx/ui/widgets/song_tile.dart';

/// 下载音乐列表页:显示已下载歌曲,点击播放本地文件;
/// 支持「全部播放」整表连播(本地文件零解析,切歌近瞬时)。
class DownloadPage extends ConsumerWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadControllerProvider);
    final player = ref.watch(playerControllerProvider);
    final ctrl = ref.read(playerControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final currentSong = player.current;
    final currentPath = downloads
        .where((d) => d.song.id == currentSong?.id)
        .map((d) => d.filePath)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('下载音乐')),
      body: downloads.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.download_for_offline_outlined,
                    size: 56,
                    color: scheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有下载的歌曲',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '在搜索结果点「⬇」选择音质下载',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已下载 ${downloads.length} 首',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          // 整表作为本地队列连播:下一首/上一首都在下载列表内,秒切
                          ctrl.playLocal(
                            downloads.first.song,
                            downloads.first.filePath,
                            songs: [for (final d in downloads) d.song],
                            paths: [for (final d in downloads) d.filePath],
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(
                          Icons.playlist_play_rounded,
                          size: 18,
                        ),
                        label: const Text('全部播放'),
                      ),
                      IconButton(
                        tooltip: '打开下载文件夹',
                        icon: const Icon(Icons.folder_open_rounded, size: 20),
                        onPressed: () async {
                          final dir = DownloadController.downloadDir();
                          await openPath(dir.path);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                    itemCount: downloads.length,
                    itemBuilder: (context, i) {
                      final d = downloads[i];
                      final qualityLabel = switch (d.quality) {
                        'high' => '320k',
                        'super' => '无损',
                        _ => '128k',
                      };
                      final isCurrent =
                          currentSong != null &&
                          currentSong.id == d.song.id &&
                          currentPath != null;
                      return SongTile(
                        song: d.song,
                        showPlatform: true,
                        highlighted: isCurrent,
                        onTap: () {
                          // 从点击处开始整表连播
                          ctrl.playLocal(
                            d.song,
                            d.filePath,
                            songs: [for (final x in downloads) x.song],
                            paths: [for (final x in downloads) x.filePath],
                          );
                        },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                qualityLabel,
                                style: textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '删除下载',
                              iconSize: 20,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: scheme.onSurfaceVariant,
                              ),
                              onPressed: () => ref
                                  .read(downloadControllerProvider.notifier)
                                  .remove(d),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
