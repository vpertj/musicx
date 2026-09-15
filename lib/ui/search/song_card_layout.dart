/// 歌曲卡片网格的布局计算(纯函数,便于单测)。
///
/// 为什么需要它:卡片封面是 `AspectRatio(1)`,高度跟随单元格宽度。此前网格写死
/// 「3 列 + 行高 158」,手机宽度下没问题,但桌面全屏时单元格宽达 200+,
/// 方图高度超出固定行高 → 溢出并把下方「猜你喜欢」「最近播放」整块盖住
/// (桌面版实测现象)。这里让列数与行高都由可用宽度推导,任何窗口宽度都不溢出。
library;

/// 布局结果:列数 + 行高(逻辑像素)。
class SongCardLayout {
  const SongCardLayout({required this.columns, required this.extent});

  final int columns;

  /// 单个网格单元的高度 = 封面边长 + 文案高度。
  final double extent;

  /// 封面边长(即单元格宽度)。
  double get cellWidth => extent - captionHeight;

  static const double captionHeight = 48;
}

/// 右侧留白(与列表 padding 一致)。
const double songCardTrailingPadding = 20;
const double songCardSpacing = 12;

/// 期望的单个卡片宽度;用它推导列数。
const double _preferredCellWidth = 120;

/// 根据可用宽度算出行列布局。
///
/// - 手机(约 360~430):3 列(用户要求「一排三个」)
/// - 平板/桌面(更宽):列数自适应增加(最多 6),卡片不会被撑大
SongCardLayout songCardLayoutFor(
  double maxWidth, {
  int minColumns = 3,
  int maxColumns = 6,
}) {
  final usable = maxWidth - songCardTrailingPadding;
  if (usable <= 0) {
    return const SongCardLayout(
      columns: 3,
      extent: _preferredCellWidth + SongCardLayout.captionHeight,
    );
  }
  var columns = (usable / _preferredCellWidth).round();
  if (columns < minColumns) columns = minColumns;
  if (columns > maxColumns) columns = maxColumns;
  final cell =
      (usable - songCardSpacing * (columns - 1)) / columns;
  // 行高严格 = 单元格宽度 + 文案高度 → 方图绝不会超出上行,也不会压住下一行
  return SongCardLayout(
    columns: columns,
    extent: cell + SongCardLayout.captionHeight,
  );
}
