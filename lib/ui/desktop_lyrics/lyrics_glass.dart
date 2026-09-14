// lib/ui/desktop_lyrics/lyrics_glass.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:musicx/core/settings/desktop_lyrics_settings.dart';

/// 毛玻璃卡片:封面模糊层 + 压暗层 + 噪点层 + 高光描边层 + 内容层。
///
/// 浮窗与设置页预览共用,保证「所见即所得」。
/// 关键:模糊作用在**封面图自己的子树**上([ImageFiltered]),
/// 而不是像旧版那样用 [BackdropFilter] 去模糊一个空的窗口背景。
class LyricsGlassCard extends StatelessWidget {
  const LyricsGlassCard({
    super.key,
    required this.settings,
    required this.artworkUrl,
    required this.radius,
    this.child,
  });

  final DesktopLyricsSettings settings;

  /// 专辑封面 URL;null/空/加载失败时退化为柔光斑渐变。
  final String? artworkUrl;

  /// 圆角,由布局解析给出(随窗口缩放),不由设置直接决定。
  final double radius;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 34,
            spreadRadius: -4,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _CoverBackdrop(settings: settings, artworkUrl: artworkUrl),
            _TintLayer(settings: settings),
            const Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: _NoisePainter())),
            ),
            _HighlightLayer(radius: radius),
            ?child,
          ],
        ),
      ),
    );
  }
}

/// 第①层:封面模糊背景(或兜底柔光斑)。
class _CoverBackdrop extends StatelessWidget {
  const _CoverBackdrop({required this.settings, required this.artworkUrl});

  final DesktopLyricsSettings settings;
  final String? artworkUrl;

  @override
  Widget build(BuildContext context) {
    final tint = settings.textColor;

    Widget fallback() => DecoratedBox(
          key: const Key('lyrics_glass_fallback'),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.6, -0.4),
              radius: 1.4,
              colors: [
                tint.withValues(alpha: 0.55),
                tint.withValues(alpha: 0.16),
                Colors.black.withValues(alpha: 0.35),
              ],
            ),
          ),
        );

    final url = artworkUrl;
    if (!settings.showArtwork || url == null || url.isEmpty) return fallback();

    Widget image = Image.network(
      url,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback(),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback(),
    );

    // 提饱和,让模糊后的封面更「透亮」。
    image = ColorFiltered(colorFilter: ColorFilter.matrix(_saturation(1.25)), child: image);

    final sigma = settings.blurSigma;
    if (sigma <= 0.5) return image;

    // 放大 1.3 倍,避免模糊后在边缘露出透明区。
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: Transform.scale(scale: 1.3, child: image),
    );
  }

  /// 饱和度增强矩阵。
  List<double> _saturation(double s) => <double>[
        0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
        0, 0, 0, 1, 0,
      ];
}

/// 第②层:暗色渐变,浓度由 glassTint 控制,保证文字对比度。
class _TintLayer extends StatelessWidget {
  const _TintLayer({required this.settings});

  final DesktopLyricsSettings settings;

  @override
  Widget build(BuildContext context) {
    final a = settings.glassTint / 100;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.45, 1.0],
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.03),
            Colors.black.withValues(alpha: 0.18 + 0.50 * a),
          ],
        ),
      ),
    );
  }
}

/// 第④层:左上高光 + 1px 内描边,玻璃「折射感」来源。
class _HighlightLayer extends StatelessWidget {
  const _HighlightLayer({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.center,
            colors: [
              Colors.white.withValues(alpha: 0.10),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

/// 第③层:确定性噪点 —— 固定种子生成归一化坐标,绘制时才按尺寸缩放,
/// 因此窗口尺寸变化无需重新生成,painter 可保持 const 且不重绘。
class _NoisePainter extends CustomPainter {
  const _NoisePainter();

  static final Float32List _points = _buildPoints();

  static Float32List _buildPoints() {
    final rng = math.Random(20260911);
    const count = 2600;
    final values = Float32List(count * 2);
    for (var i = 0; i < count; i++) {
      values[i * 2] = rng.nextDouble();
      values[i * 2 + 1] = rng.nextDouble();
    }
    return values;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scaled = List<Offset>.generate(
      _points.length ~/ 2,
      (i) => Offset(_points[i * 2] * size.width, _points[i * 2 + 1] * size.height),
    );
    canvas.drawPoints(
      ui.PointMode.points,
      scaled,
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
