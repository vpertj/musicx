// test/ui/desktop_lyrics/lyrics_resize_test.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_resize.dart';

void main() {
  const base = Rect.fromLTWH(100, 200, 880, 190);

  Rect drag(ResizeEdge edge, double dx, double dy, {Size? maxSize}) {
    return resizeRect(
      current: base,
      edge: edge,
      delta: Offset(dx, dy),
      maxSize: maxSize,
    );
  }

  test('拖右边缘:宽度增加、左边界不动', () {
    final r = drag(ResizeEdge.right, 50, 0);
    expect(r.left, 100);
    expect(r.width, 930);
  });

  test('拖左边缘向左:左边界左移、宽度增加', () {
    final r = drag(ResizeEdge.left, -30, 0);
    expect(r.left, 70);
    expect(r.right, 980);
    expect(r.width, 910);
  });

  test('拖左边缘越过最小宽度:宽度被夹到最小且不翻转', () {
    final r = drag(ResizeEdge.left, 900, 0);
    expect(r.width, 320);
    expect(r.left, 980 - 320);
  });

  test('拖顶边向上:高度增加、底边不动;越过最小高度被夹住', () {
    expect(drag(ResizeEdge.top, 0, -40).bottom, 390);
    expect(drag(ResizeEdge.top, 0, 500).height, 90);
  });

  test('拖左上角同时改变左边与顶边', () {
    final r = drag(ResizeEdge.topLeft, -10, -10);
    expect(r.left, 90);
    expect(r.top, 190);
  });

  test('maxSize 限制最大尺寸', () {
    final r = drag(ResizeEdge.right, 5000, 0, maxSize: const Size(1200, 800));
    expect(r.width, 1200);
  });

  test('clampRectToWorkArea 把跑出屏幕的窗口拉回来', () {
    final work = const Rect.fromLTWH(0, 0, 1440, 900);
    final r = clampRectToWorkArea(const Rect.fromLTWH(1400, 850, 880, 190), work);
    expect(r.right <= work.right, isTrue);
    expect(r.bottom <= work.bottom, isTrue);
    expect(r.width, 880);
  });

  test('clampRectToWorkArea 把大于工作区的窗口压到工作区大小', () {
    final work = const Rect.fromLTWH(0, 0, 1000, 600);
    final r = clampRectToWorkArea(const Rect.fromLTWH(-50, -50, 2000, 1200), work);
    expect(r, work);
  });
}
