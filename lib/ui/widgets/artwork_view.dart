import 'package:flutter/material.dart';

/// 歌曲封面:网络图 + 渐变占位兜底,统一圆角。
class ArtworkView extends StatelessWidget {
  const ArtworkView({
    super.key,
    this.url,
    required this.size,
    this.radius = 12,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final double size;
  final double radius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: .55),
            scheme.primary.withValues(alpha: .18),
          ],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * .4,
        color: Colors.white.withValues(alpha: .7),
      ),
    );

    final url = this.url;
    if (url == null || url.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => placeholder,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return placeholder;
          },
        ),
      ),
    );
  }
}
