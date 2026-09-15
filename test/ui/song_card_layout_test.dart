// test/ui/song_card_layout_test.dart
//
// 桌面版首页「卡片溢出盖住下方内容」的回归用例。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/ui/search/song_card_layout.dart';

void main() {
  test('手机宽度:一排三个', () {
    final l = songCardLayoutFor(400);
    expect(l.columns, 3);
  });

  test('桌面宽度(页面限宽 720):列数增加,卡片不被撑大', () {
    final l = songCardLayoutFor(720);
    expect(l.columns, greaterThan(3), reason: '宽屏应排更多列而不是把卡片撑大');
    expect(l.cellWidth, lessThanOrEqualTo(140),
        reason: '单元格宽度必须有上限,否则方图会超出固定行高');
  });

  test('任何宽度下行高都容得下方形封面 + 文案(不溢出)', () {
    for (final w in [320.0, 360.0, 400.0, 430.0, 600.0, 720.0, 1024.0, 1440.0]) {
      final l = songCardLayoutFor(w);
      expect(
        l.extent,
        greaterThanOrEqualTo(l.cellWidth + SongCardLayout.captionHeight - 0.01),
        reason: '宽度 $w 时行高必须 ≥ 封面边长 + 文案高度',
      );
      expect(l.columns, greaterThanOrEqualTo(3));
      expect(l.columns, lessThanOrEqualTo(6));
    }
  });

  test('极窄/异常宽度不崩溃', () {
    final l = songCardLayoutFor(0);
    expect(l.columns, 3);
    expect(l.extent, greaterThan(0));
  });
}
