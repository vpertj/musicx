import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/library/library_controller.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/theme/app_theme.dart';

/// 弹出「加入歌单」选择器:我喜欢的音乐 + 各歌单 + 新建歌单。
Future<void> showPlaylistPicker(
  BuildContext context,
  WidgetRef ref,
  MusicItem song,
) async {
  final notifier = ref.read(libraryControllerProvider.notifier);
  final state = ref.read(libraryControllerProvider);
  final messenger = ScaffoldMessenger.of(context);
  final isFav = notifier.isFavorite(song);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final textTheme = Theme.of(ctx).textTheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text(
                '加入歌单',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: AppTheme.pink,
              ),
              title: const Text('我喜欢的音乐'),
              trailing: isFav
                  ? Text(
                      '已加入',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                      ),
                    )
                  : null,
              onTap: () {
                notifier.toggleFavorite(song);
                Navigator.pop(ctx);
                messenger.showSnackBar(
                  SnackBar(content: Text(isFav ? '已取消喜欢' : '已加入「我喜欢的音乐」')),
                );
              },
            ),
            for (final p in state.playlists)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${p.songs.length} 首',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                onTap: () {
                  notifier.addSongToPlaylist(p.id, song);
                  Navigator.pop(ctx);
                  messenger.showSnackBar(
                    SnackBar(content: Text('已加入「${p.name}」')),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('新建歌单并加入'),
              onTap: () async {
                Navigator.pop(ctx);
                final controller = TextEditingController();
                final name = await showDialog<String>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: const Text('新建歌单'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: '歌单名称'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dctx),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(dctx, controller.text.trim()),
                        child: const Text('创建'),
                      ),
                    ],
                  ),
                );
                if (name == null || name.isEmpty) return;
                final p = notifier.createPlaylist(name);
                notifier.addSongToPlaylist(p.id, song);
                messenger.showSnackBar(
                  SnackBar(content: Text('已创建并加入「$name」')),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
