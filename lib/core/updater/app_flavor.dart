/// 发行版本(flavor):同一套代码产出两个互相独立的安装包。
///
/// - [blessing]「吴玫静版」:tag 形如 `v1.7.46`,设置页底部带寄语卡片;
/// - [standard]「标准版」:tag 形如 `std-1.7.46`,设置页无该卡片。
///
/// **为什么必须靠 tag 前缀隔离**:GitHub 的 `/releases/latest` 返回的是
/// 全仓库最新的 release,不区分变体。若两个版本都查 `/releases/latest`,
/// 标准版会升级到吴玫静版(或反之)——即「串版」,用户会莫名多出/丢失卡片,
/// 甚至被系统以签名/包名不一致拒绝安装。因此每个变体都要: 
///   ① 只认自己前缀的 tag;
///   ② 在全部 release 里筛出自己那条线的最新版,而不是取 /releases/latest。
library;

/// 发行变体。
enum AppFlavor {
  /// 吴玫静版(带寄语卡片)。
  blessing,

  /// 标准版(无寄语卡片)。
  standard;

  /// 该变体的 tag 前缀(不含版本号)。
  ///
  /// 吴玫静版沿用历史 tag 形式(`v1.7.46`),保证老用户能平滑升级 ——
  /// 若改成带前缀的形式,现有已安装的版本将再也查不到新版本。
  String get tagPrefix => switch (this) {
    AppFlavor.blessing => 'v',
    AppFlavor.standard => 'std-v',
  };

  /// 展示名(用于界面/错误信息)。
  String get displayName => switch (this) {
    AppFlavor.blessing => '吴玫静版',
    AppFlavor.standard => '标准版',
  };

  /// 是否展示设置页底部的寄语卡片。
  bool get showsBlessingCard => this == AppFlavor.blessing;
}

/// 本次构建的变体。
///
/// 用编译期常量注入,默认 [AppFlavor.blessing](保持现有行为不变):
///   flutter build apk --release --dart-define=FLAVOR=standard
const String kFlavorName = String.fromEnvironment('FLAVOR', defaultValue: '');

/// 解析编译期传入的变体名;无法识别时回落吴玫静版。
AppFlavor parseFlavor(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'standard':
    case 'std':
      return AppFlavor.standard;
    case 'blessing':
    case 'wumeijing':
    case '':
      return AppFlavor.blessing;
    default:
      return AppFlavor.blessing;
  }
}

/// 当前构建对应的变体。
final AppFlavor currentFlavor = parseFlavor(kFlavorName);

/// 从 tag 中剥离本变体的前缀,得到纯版本号;不属于本变体则返回 null。
///
/// 例(blessing, prefix='v'):  `v1.7.46`   → `1.7.46`
/// 例(standard, prefix='std-v'):`std-v1.7.46` → `1.7.46`
///
/// 注意顺序:标准版前缀 `std-v` 也以 `v` 结尾,必须先匹配长前缀,
/// 否则 `std-v1.7.46` 会被误判成吴玫静版的 `1.7.46` 而串版。
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
