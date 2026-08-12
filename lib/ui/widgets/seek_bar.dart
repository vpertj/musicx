import 'package:flutter/material.dart';
import 'package:musicx/theme/app_theme.dart';

/// 渐变进度条,支持点击 / 拖动 seek。
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    this.onSeekEnd,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration>? onSeekEnd;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragFraction;

  double get _fraction {
    if (_dragFraction != null) return _dragFraction!;
    if (widget.duration.inMilliseconds <= 0) return 0;
    return (widget.position.inMilliseconds / widget.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  void _updateFromDx(double dx, double width) {
    setState(() => _dragFraction = (dx / width).clamp(0.0, 1.0));
  }

  void _commit() {
    final f = _dragFraction ?? 0.0;
    _dragFraction = null;
    final target = Duration(
      milliseconds: (widget.duration.inMilliseconds * f).round(),
    );
    widget.onSeekEnd?.call(target);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _updateFromDx(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _updateFromDx(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _commit(),
          onTapDown: (d) {
            final f = (d.localPosition.dx / width).clamp(0.0, 1.0);
            widget.onSeekEnd?.call(
              Duration(milliseconds: (widget.duration.inMilliseconds * f).round()),
            );
          },
          child: SizedBox(
            height: 32,
            child: CustomPaint(
              painter: _SeekBarPainter(
                fraction: _fraction,
                dragging: _dragFraction != null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekBarPainter extends CustomPainter {
  _SeekBarPainter({required this.fraction, required this.dragging});

  final double fraction;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    const trackH = 5.0;
    final trackRect = Rect.fromLTWH(
      0,
      (size.height - trackH) / 2,
      size.width,
      trackH,
    );
    final radius = Radius.circular(trackH / 2);

    // 底轨
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = const Color(0xFF2E2747),
    );

    // 已播放:渐变
    if (fraction > 0) {
      final activeRect = Rect.fromLTWH(
        0,
        trackRect.top,
        size.width * fraction,
        trackH,
      );
      final paint = Paint()
        ..shader = AppTheme.accentGradient.createShader(activeRect);
      canvas.drawRRect(RRect.fromRectAndRadius(activeRect, radius), paint);
    }

    // 拖拽时轨道上加亮
    if (dragging && fraction > 0) {
      final activeRect = Rect.fromLTWH(
        0,
        trackRect.top,
        size.width * fraction,
        trackH,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        Paint()..color = Colors.white.withValues(alpha: .18),
      );
    }

    // 拇指
    final thumbR = dragging ? 9.0 : 6.5;
    final cx = size.width * fraction;
    final cy = size.height / 2;
    if (fraction > 0) {
      canvas.drawCircle(
        Offset(cx, cy),
        thumbR + 7,
        Paint()..color = AppTheme.pink.withValues(alpha: .35),
      );
    }
    canvas.drawCircle(
      Offset(cx, cy),
      thumbR,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SeekBarPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.dragging != dragging;
}
