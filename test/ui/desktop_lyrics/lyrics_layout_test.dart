// test/ui/desktop_lyrics/lyrics_layout_test.dart
import 'dart:ui';

import 'package:flutter/rendering.dart' show Axis;

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const settings = DesktopLyricsSettings();

  LyricsLayout resolve(Size size, {DesktopLyricsSettings s = settings}) {
    return resolveLyricsLayout(
      windowSize: size,
      settings: s,
      current: '等到树叶都泛了黄',
      next: '等到眼里全是伤',
    );
  }

  test('基准高度 190 时不缩放', () {
    final l = resolve(const Size(880, 190));
    expect(l.fontSize, 34);
    expect(l.showNext, isTrue);
    expect(l.direction, Axis.vertical);
    expect(l.cardRadius, 26);
  });

  test('autoScale 关闭时字号恒为基准值', () {
    final l = resolve(const Size(400, 600),
        s: const DesktopLyricsSettings(autoScale: false));
    expect(l.fontSize, 34);
  });

  test('过高窗口字号放大并夹到 2.2 倍', () {
    final l = resolve(const Size(400, 900));
    expect(l.fontSize, closeTo(34 * 2.2, 0.01));
  });

  test('过矮窗口字号夹到 0.55 倍且不低于 12', () {
    final l = resolve(const Size(400, 60));
    expect(l.fontSize, closeTo(34 * 0.55, 0.01));
    expect(l.fontSize, greaterThanOrEqualTo(12));
  });

  test('高度低于 120 时隐藏下一句', () {
    final l = resolve(const Size(880, 100));
    expect(l.showNext, isFalse);
  });

  test('showNext 关掉时即使窗口够高也不显示', () {
    final l = resolve(const Size(880, 300),
        s: const DesktopLyricsSettings(showNext: false));
    expect(l.showNext, isFalse);
    expect(l.direction, Axis.vertical);
  });

  test('宽扁窗口且放得下时横向并排', () {
    final l = resolve(const Size(1600, 110));
    expect(l.direction, Axis.horizontal);
  });

  test('超长当前句逐档降字号到下限 12', () {
    final l = resolveLyricsLayout(
      windowSize: const Size(400, 190),
      settings: settings,
      current: '长' * 200,
      next: '短',
    );
    expect(l.fontSize, 12);
  });

  test('内边距随窗口等比缩放且被夹取', () {
    expect(resolve(const Size(880, 190)).padding.horizontal, 56);
    expect(resolve(const Size(880, 900)).padding.horizontal, lessThanOrEqualTo(96));
    expect(resolve(const Size(400, 60)).padding.horizontal, greaterThanOrEqualTo(32));
  });
}
