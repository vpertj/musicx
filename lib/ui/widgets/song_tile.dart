import 'package:flutter/material.dart';
import 'package:musicx/core/utils/format.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/widgets/artwork_view.dart';

/// 搜索结果 / 播放队列通用的歌曲行。
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.trailing,
    this.highlighted = false,
    this.showPlatform = false,
    this.artworkSize = 52,
  });

  final MusicItem song;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool highlighted;
  final bool showPlatform;
  final double artworkSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final artist = song.artist ?? '';
    final album = song.album ?? '';

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: ArtworkView(url: song.artwork, size: artworkSize, radius: 12),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: highlighted ? scheme.primary : null,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            if (artist.isNotEmpty)
              Flexible(
                child: Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            if (artist.isNotEmpty && album.isNotEmpty)
              Flexible(
                child: Text(
                  ' · $album',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ),
            if (song.duration != null && song.duration! > 0) ...[
              const SizedBox(width: 8),
              Text(
                formatMilliseconds(song.duration),
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.outline,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: trailing ?? (showPlatform ? PlatformBadge(platform: song.platform) : null),
    );
  }
}

/// 平台来源小徽标,如 `demo` / `netease`。
class PlatformBadge extends StatelessWidget {
  const PlatformBadge({super.key, required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        platform,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
