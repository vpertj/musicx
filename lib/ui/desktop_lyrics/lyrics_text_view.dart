import 'package:flutter/material.dart';

import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'lyrics_layout.dart';

/// 极简纯文字歌词渲染:左侧律动竖条 + 当前句(+ 下一句)。
///
/// 刻意**不画任何卡片**:没有背景、没有描边、没有投影、没有模糊。
/// 可读性完全交给文字自身的描边阴影 —— 这样歌词像是直接浮在桌面上,
/// 而不是被装进一个框里。浮窗与设置页预览共用,保证所见即所得。
class LyricsTextView extends StatelessWidget {
  const LyricsTextView({
    super.key,
    required this.layout,
    required this.settings,
    required this.current,
    required this.next,
    this.showAccentBar = true,
  });

  final LyricsLayout layout;
  final DesktopLyricsSettings settings;
  final String current;
  final String next;

  /// 左侧竖条开关。
  final bool showAccentBar;

  @override
  Widget build(BuildContext context) {
    final color = settings.textColor;
    final bar = Container(
      width: layout.accentBarWidth,
      height: layout.fontSize * 1.6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(layout.accentBarWidth / 2),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withValues(alpha: 0.2)],
        ),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 14),
        ],
      ),
    );
    final gap = 22 * (layout.padding.horizontal / 56);

    // 纯文字没有背景兜底,靠「深色描边 + 同色光晕」保证亮/暗壁纸上都可读。
    final currentText = Text(
      current,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: layout.fontSize,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: 0.5,
        shadows: [
          Shadow(color: color.withValues(alpha: 0.45), blurRadius: 18),
          const Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
          const Shadow(color: Color(0x99000000), blurRadius: 2),
        ],
      ),
    );
    final nextText = Text(
      next,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: settings.nextColor,
        fontSize: layout.nextFontSize,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: 0.3,
        shadows: const [
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
          Shadow(color: Color(0x99000000), blurRadius: 2),
        ],
      ),
    );

    if (layout.direction == Axis.horizontal) {
      return Row(
        children: [
          if (showAccentBar) ...[bar, SizedBox(width: gap)],
          Flexible(child: currentText),
          SizedBox(width: gap * 0.8),
          Flexible(child: nextText),
        ],
      );
    }

    return Row(
      children: [
        if (showAccentBar) ...[bar, SizedBox(width: gap)],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              currentText,
              if (layout.showNext) ...[
                const SizedBox(height: 8),
                nextText,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
