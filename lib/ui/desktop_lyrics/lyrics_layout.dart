// lib/ui/desktop_lyrics/lyrics_layout.dart
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'package:musicx/core/settings/desktop_lyrics_settings.dart';

/// 自适应基准:浮窗默认高度,保证老用户观感不变。
const double kLyricsReferenceHeight = 190;

/// 字号缩放系数上下限。
const double kLyricsMinScale = 0.55;
const double kLyricsMaxScale = 2.2;

/// 窗口高度低于该值时只显示当前句。
const double kLyricsSingleLineHeight = 120;

/// 宽高比达到该值且两行都放得下时,当前句与下一句横向并排。
const double kLyricsHorizontalRatio = 6;

/// 布局解析结果:浮窗与设置页预览都以它为唯一布局事实来源。
class LyricsLayout {
  const LyricsLayout({
    required this.fontSize,
    required this.nextFontSize,
    required this.showNext,
    required this.direction,
    required this.padding,
    required this.accentBarWidth,
    required this.cardRadius,
  });

  final double fontSize;
  final double nextFontSize;
  final bool showNext;
  final Axis direction;
  final EdgeInsets padding;
  final double accentBarWidth;
  final double cardRadius;
}

/// 由窗口尺寸 + 设置解析出实际布局(纯函数,无 Widget 依赖)。
LyricsLayout resolveLyricsLayout({
  required Size windowSize,
  required DesktopLyricsSettings settings,
  required String current,
  required String next,
}) {
  final safeSize = Size(
    windowSize.width <= 0 ? 1 : windowSize.width,
    windowSize.height <= 0 ? 1 : windowSize.height,
  );

  final scale = settings.autoScale
      ? (safeSize.height / kLyricsReferenceHeight)
          .clamp(kLyricsMinScale, kLyricsMaxScale)
      : 1.0;

  // 派生内边距/竖条/圆角:按窗口缩放再夹取,避免极端尺寸下变形。
  final padding = EdgeInsets.symmetric(
    horizontal: (28 * scale).clamp(16.0, 48.0),
    vertical: (18 * scale).clamp(10.0, 34.0),
  );
  final accentBarWidth = (6 * scale).clamp(3.0, 12.0);
  final cardRadius = (settings.cornerRadius * scale).clamp(8.0, 60.0);

  var fontSize = (settings.fontSize * scale).clamp(
    DesktopLyricsSettings.minFontSize,
    DesktopLyricsSettings.maxFontSize,
  );
  final showNext = settings.showNext &&
      next.trim().isNotEmpty &&
      safeSize.height >= kLyricsSingleLineHeight;

  // 纵向可用宽度 = 窗口宽 - 内边距 - 竖条与间距。
  final reserved = padding.horizontal + accentBarWidth + 22 * scale;
  final availableWidth = math.max(1.0, safeSize.width - reserved);

  // 溢出保护:当前句放不下时逐档降字号到下限,仍放不下才交给 ellipsis。
  // 仅在窗口高度不超过基准高度时启用:高于基准高度时字号由高度缩放决定
  // (autoScale 放大语义优先),宽度放不下交给 ellipsis,避免窄高窗口被挤回小字。
  final canShrink = safeSize.height <= kLyricsReferenceHeight;
  while (canShrink && fontSize > DesktopLyricsSettings.minFontSize &&
      measureTextWidth(current, fontSize) > availableWidth) {
    fontSize -= 1;
  }
  fontSize = math.max(DesktopLyricsSettings.minFontSize, fontSize);

  // 排布方向:宽扁窗口且两行并排实测放得下才横向。
  // 不要求 showNext:矮窗口堆叠时只显示当前句,但宽扁窗口仍可并排展示下一句。
  var direction = Axis.vertical;
  if (safeSize.width / safeSize.height >= kLyricsHorizontalRatio) {
    final nextSize = (fontSize * 0.56).clamp(11.0, fontSize);
    final total = measureTextWidth(current, fontSize) +
        22 * scale +
        measureTextWidth(next, nextSize);
    if (total <= availableWidth) direction = Axis.horizontal;
  }

  return LyricsLayout(
    fontSize: fontSize,
    nextFontSize: (fontSize * 0.56).clamp(11.0, fontSize),
    showNext: showNext,
    direction: direction,
    padding: padding,
    accentBarWidth: accentBarWidth,
    cardRadius: cardRadius,
  );
}

/// 实测单行文本宽度(TextPainter),供溢出保护与横排判断使用。
double measureTextWidth(String text, double fontSize) {
  if (text.trim().isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.width;
}
