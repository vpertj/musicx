import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/download/download_controller.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/ui/widgets/song_tile.dart';

/// 下载音乐列表页:显示已下载歌曲,点击播放本地文件。
class DownloadPage extends ConsumerWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载音乐'),
        actions: [
          if (downloads.isNotEmpty)
            IconButton(
              tooltip: '打开下载文件夹',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: () async {
                final dir = DownloadController.downloadDir();
                // 在 Finder 中显示
                await Process.run('open', [dir.path]);
              },
            ),
        ],
      ),
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
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
              itemCount: downloads.length,
              itemBuilder: (context, i) {
                final d = downloads[i];
                final qualityLabel = switch (d.quality) {
                  'high' => '320k',
                  'super' => '无损',
                  _ => '128k',
                };
                return SongTile(
                  song: d.song,
                  showPlatform: true,
                  onTap: () => ref
                      .read(playerControllerProvider.notifier)
                      .playLocal(d.song, d.filePath),
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
    );
  }
}
