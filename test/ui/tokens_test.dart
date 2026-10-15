// test/ui/tokens_test.dart
//
// 视觉 token 契约(设计 §3.2)。这些值是"设置页看起来像 NutUI"的地基,
// 写死在这里是为了防止后续页面各写各的尺度(此前的乱正是这么来的)。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/ui/tokens.dart';

void main() {
  test('尺寸与圆角 token', () {
    expect(AppSize.rowHeight, 56, reason: '设置行统一高度');
    expect(AppSize.icon, 20, reason: '行内图标统一尺寸');
    expect(AppSize.iconLarge, 24);
    expect(AppSize.dividerInset, 16, reason: '分割线与图标列对齐');
    expect(AppSize.iconSmall, 16);
    expect(AppSize.chipHeight, 36);
    expect(AppRadius.card, 14);
    expect(AppRadius.control, 10);
  });

  test('间距与字号 token', () {
    expect([AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.lg, AppSpacing.xl],
        [4.0, 8.0, 12.0, 16.0, 24.0]);
    expect(AppText.sectionTitle, 13);
    expect(AppText.rowTitle, 15);
    expect(AppText.rowSubtitle, 12);
  });

  test('浅色色板', () {
    expect(AppPalette.lightBackground, const Color(0xFFF5F6F8));
    expect(AppPalette.lightCard, const Color(0xFFFFFFFF));
    expect(AppPalette.lightDivider, const Color(0xFFEDEEF1));
    expect(AppPalette.lightTitle, const Color(0xFF8A8F99));
  });
}
