/// 发行版本(flavor)。
///
/// 当前只发布**标准版**:tag 形如 `std-v1.7.47`,CI 构建时注入
/// `--dart-define=FLAVOR=standard`。
///
/// 历史说明:早期还有「吴玫静版」(tag `v*`,设置页带寄语卡片)升级线,
/// 两条线靠 tag 前缀隔离避免串版。现已合并为标准版单一发布线,
/// 本文件保留 [AppFlavor.standard] 与 tag 前缀解析逻辑供更新检查使用。
library;

/// 发行变体。
enum AppFlavor {
  /// 标准版:tag 前缀 `std-v`,更新检查只认该前缀的 release。
  standard;

  /// 该变体的 tag 前缀(不含版本号)。
  String get tagPrefix => switch (this) {
        AppFlavor.standard => 'std-v',
      };

  /// 展示名(用于界面/错误信息)。
  String get displayName => switch (this) {
        AppFlavor.standard => '标准版',
      };

  /// 是否展示设置页底部的寄语卡片。
  ///
  /// 历史遗留开关:吴玫静版专属卡片已随该版本线停发,恒为 false。
  bool get showsBlessingCard => false;
}

/// 本次构建的变体。
///
/// 用编译期常量注入,默认 [AppFlavor.standard]:
///   flutter build apk --release --dart-define=FLAVOR=standard
const String kFlavorName =
    String.fromEnvironment('FLAVOR', defaultValue: 'standard');

/// 解析编译期传入的变体名;无法识别时回落标准版。
AppFlavor parseFlavor(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'standard':
    case 'std':
      return AppFlavor.standard;
    case 'blessing':
    case 'wumeijing':
    case '':
      // 历史值:旧吴玫静版构建不再发布,一律归入标准版,
      // 保证这些客户端的更新检查走 std-v 升级线。
      return AppFlavor.standard;
    default:
      return AppFlavor.standard;
  }
}

/// 当前构建对应的变体。
final AppFlavor currentFlavor = parseFlavor(kFlavorName);

/// 从 tag 中剥离本变体的前缀,得到纯版本号;不属于本变体则返回 null。
///
/// 例(standard, prefix='std-v'):`std-v1.7.46` → `1.7.46`
String? versionFromTag(String tag, AppFlavor flavor) {
  final t = tag.trim();
  if (t.isEmpty) return null;
  final prefix = flavor.tagPrefix;
  if (!t.startsWith(prefix)) return null;
  final rest = t.substring(prefix.length);
  if (rest.isEmpty) return null;
  // 版本号必须以数字开头,避免把无关 tag 误收
  if (!RegExp(r'^\d').hasMatch(rest)) return null;
  return rest;
}

/// 判断某个 tag 是否属于指定变体。
bool tagBelongsTo(String tag, AppFlavor flavor) =>
    versionFromTag(tag, flavor) != null;
