/// 搜索音源选择的自愈逻辑(纯函数,便于单测)。
///
/// 背景:`searchSourceProvider` 里存的是**平台名**,而平台名会随插件改名
/// (设置 → 音源管理 → 编辑)或卸载而失效。失效后若继续用它搜索,插件管理
/// 会抛 `plugin not installed`,用户看到的就是「自动/选源都用不了」。
library;

/// 实际生效的音源:
/// - 未选择 → null(自动)
/// - 选中的平台仍在已装列表里 → 原样使用
/// - 选中的平台已不存在(改名/卸载)→ 回落自动
///
/// 注意:已装列表为空时无法判断,保持用户选择不动(列表可能只是还没加载完)。
String? effectiveSearchSource({
  required String? selected,
  required Set<String> installedPlatforms,
}) {
  if (selected == null) return null;
  if (installedPlatforms.isEmpty) return selected;
  return installedPlatforms.contains(selected) ? selected : null;
}

/// 插件改名后迁移当前选择:选中的正是被改名的源时,跟随到新名字。
String? migrateSelectedSource({
  required String? selected,
  required String from,
  required String to,
}) {
  if (selected == from) return to;
  return selected;
}
