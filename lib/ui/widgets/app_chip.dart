import 'package:flutter/material.dart';

import 'package:musicx/ui/tokens.dart';

/// 全局统一芯片(选择类)。
///
/// 为什么抽出来:此前 5 处各写各的 —— 圆角 18/20 混用、行高 52、还有的地方把
/// `♥ / ⬇ / ＋` 当图标塞进文案(emoji 的字体度量与正文字体不同,同屏并列时
/// 高低不齐,一眼就看出「乱」)。这里统一到 token:
/// 高度 [AppSize.chipHeight]、圆角 [AppRadius.chip]、内边距 [AppSpacing.md]、
/// 图标 [AppSize.iconSmall];选中态用品牌红实底,未选中用白卡 + 细描边。
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.selectedIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 未选中时显示的图标(可选)。
  final IconData? icon;

  /// 选中时显示的图标;不传则沿用 [icon]。
  final IconData? selectedIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final leading = selected ? (selectedIcon ?? icon) : icon;
    return Material(
      color: selected ? scheme.primary : scheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Container(
          height: AppSize.chipHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            // 未选中加一道极细描边:灰底 + 白卡上仍能看清边界。
            border: selected
                ? null
                : Border.all(color: scheme.outlineVariant, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                Icon(
                  leading,
                  size: AppSize.iconSmall,
                  color: selected ? Colors.white : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs + 2),
              ],
              Text(
                label,
                style: textTheme.labelMedium?.copyWith(
                  fontSize: AppText.rowSubtitle,
                  color: selected ? Colors.white : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
