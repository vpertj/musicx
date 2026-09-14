// lib/ui/desktop_lyrics/lyrics_resize.dart
import 'dart:math' as math;
import 'dart:ui';

/// 缩放热区:四条边 + 四个角。
enum ResizeEdge {
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// 浮窗最小尺寸(逻辑像素)。
const Size kLyricsMinWindowSize = Size(320, 90);

/// 根据拖拽增量计算缩放后的窗口几何(纯函数,便于单测)。
///
/// 拖左/上边时同步移动原点;结果被 [minSize] 与 [maxSize] 双向夹取,
/// 保证尺寸永不小于最小值、永不大于最大值,也不会左右/上下翻转。
Rect resizeRect({
  required Rect current,
  required ResizeEdge edge,
  required Offset delta,
  Size minSize = kLyricsMinWindowSize,
  Size? maxSize,
}) {
  var left = current.left;
  var top = current.top;
  var right = current.right;
  var bottom = current.bottom;

  final growsRight = edge == ResizeEdge.right ||
      edge == ResizeEdge.topRight ||
      edge == ResizeEdge.bottomRight;
  final growsLeft = edge == ResizeEdge.left ||
      edge == ResizeEdge.topLeft ||
      edge == ResizeEdge.bottomLeft;
  final growsBottom = edge == ResizeEdge.bottom ||
      edge == ResizeEdge.bottomLeft ||
      edge == ResizeEdge.bottomRight;
  final growsTop = edge == ResizeEdge.top ||
      edge == ResizeEdge.topLeft ||
      edge == ResizeEdge.topRight;

  if (growsRight) right += delta.dx;
  if (growsBottom) bottom += delta.dy;
  if (growsLeft) left += delta.dx;
  if (growsTop) top += delta.dy;

  void clampWidth(double maxW) {
    final w = right - left;
    if (w < minSize.width) {
      if (growsLeft) left = right - minSize.width;
      if (growsRight) right = left + minSize.width;
    } else if (w > maxW) {
      if (growsLeft) left = right - maxW;
      if (growsRight) right = left + maxW;
    }
  }

  void clampHeight(double maxH) {
    final h = bottom - top;
    if (h < minSize.height) {
      if (growsTop) top = bottom - minSize.height;
      if (growsBottom) bottom = top + minSize.height;
    } else if (h > maxH) {
      if (growsTop) top = bottom - maxH;
      if (growsBottom) bottom = top + maxH;
    }
  }

  clampWidth(maxSize == null ? double.infinity : math.max(minSize.width, maxSize.width));
  clampHeight(maxSize == null ? double.infinity : math.max(minSize.height, maxSize.height));

  return Rect.fromLTRB(left, top, right, bottom);
}

/// 把窗口几何夹回 [workArea] 内,保证窗口完整可见可操作。
Rect clampRectToWorkArea(Rect rect, Rect workArea) {
  final width = math.min(rect.width, workArea.width);
  final height = math.min(rect.height, workArea.height);
  final left = (rect.left).clamp(workArea.left, workArea.right - width);
  final top = (rect.top).clamp(workArea.top, workArea.bottom - height);
  return Rect.fromLTWH(left, top, width, height);
}
