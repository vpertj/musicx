import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/download/download_controller.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/theme/app_theme.dart';

/// 弹出音质选择器并下载歌曲。
Future<void> showDownloadPicker(
  BuildContext context,
  WidgetRef ref,
  MusicItem song,
) async {
  final messenger = ScaffoldMessenger.of(context);

  final quality = await showModalBottomSheet<String>(
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
                '下载音质',
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
            _QualityTile(
              label: '标准音质',
              sub: '128kbps · 体积小',
              value: 'standard',
            ),
            _QualityTile(label: '高品音质', sub: '320kbps · 推荐', value: 'high'),
            _QualityTile(label: '无损音质', sub: 'FLAC · 需要会员支持', value: 'super'),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (quality == null || !context.mounted) return;

  messenger.showSnackBar(SnackBar(content: Text('开始下载: ${song.title}…')));
  try {
    final path = await ref
        .read(downloadControllerProvider.notifier)
        .download(song, quality);
    messenger.showSnackBar(SnackBar(content: Text('✅ 已下载: $path')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('下载失败: $e')));
  }
}

class _QualityTile extends StatelessWidget {
  const _QualityTile({
    required this.label,
    required this.sub,
    required this.value,
  });

  final String label;
  final String sub;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          gradient: AppTheme.softGradient,
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(
          Icons.download_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
      title: Text(label),
      subtitle: Text(
        sub,
        style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      onTap: () => Navigator.pop(context, value),
    );
  }
}
