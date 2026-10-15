import 'package:flutter/widgets.dart';

/// 视觉 token:设置页先吃这套,第二版其余页面复用。
///
/// 为什么单独成文件:此前间距/圆角/字号散落各页(16、20、12… 混用),同一类元素
/// 在不同页面尺度不一 —— 用户说「不好看」,很大一部分来自这里。
/// 设计见 `docs/superpowers/specs/2026-10-09-ui-icon-system-design.md` §3.2。
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

abstract final class AppRadius {
  /// 卡片、分组容器。
  static const double card = 14;

  /// 芯片、标签。
  static const double chip = 10;

  /// 按钮、分段控件、开关这类小控件。
  static const double control = 10;
}

abstract final class AppSize {
  /// 设置行统一高度:此前各行随内容胖瘦不一(用户截图里一眼就能看出来)。
  static const double rowHeight = 56;

  /// 行内图标:统一尺寸,避免同页 18/20/22 混用。
  static const double icon = 20;

  /// 空态、大按钮、播放页主控。
  static const double iconLarge = 24;

  /// 芯片内的小图标(比行内图标再小一档)。
  static const double iconSmall = 16;

  /// 空态插画图标(播放页/曲库/下载页共用同一档)。
  static const double iconEmpty = 56;

  /// 迷你播放条高度:设置/列表页底部留白按它算,避免最后一行被压住。
  static const double miniPlayerHeight = 60;

  /// 芯片统一高度:此前 5 处芯片各写各的(52 行高 + 圆角 18/20 + emoji 前缀),
  /// 同屏并列时高低不齐。
  static const double chipHeight = 36;

  /// 分割线左内缩(与图标列对齐)。
  static const double dividerInset = 16;
}

abstract final class AppText {
  /// 分区标题(「音乐源」「外观」「通用」)。
  static const double sectionTitle = 13;
  static const double rowTitle = 15;
  static const double rowSubtitle = 12;
}

/// 浅色下的 NutUI 观感色板(深色仍走主题既有值)。
///
/// 关键点是**页面底色比卡片深一档**(0xFFF5F6F8 vs 纯白),白卡才有层次;
/// 此前两者几乎同色(0xFFFAFBFC vs 0xFFFFFFFF),卡片像「一块块裸白」。
abstract final class AppPalette {
  static const Color lightBackground = Color(0xFFF5F6F8);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightDivider = Color(0xFFEDEEF1);
  static const Color lightTitle = Color(0xFF8A8F99);
}
