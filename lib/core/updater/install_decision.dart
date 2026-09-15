/// 安装前的校验决策(纯函数,便于单测)。
///
/// 背景:用户多次遇到「提示有新版本 → 下载后系统却说已安装相同版本」。
/// 根因是此前校验是 **fail-open**(读不到 APK 版本就放行),且没有核对
/// 「下载到的安装包版本号是否就等于要更新的那个版本」。这里把决策固定下来:
/// 只有**确凿证明**安装包比已装版本新、且版本名与目标版本一致,才交给安装器;
/// 否则一律给出可读原因,绝不让系统用「已安装相同版本」这种含糊提示回应。
library;

enum InstallDecision {
  /// 可以交给系统安装器。
  install,

  /// 已装版本不低于安装包 → 其实已是最新,提示用户即可(不调起安装器)。
  alreadyLatest,

  /// 安装包版本名与目标版本不一致(下到了错的文件)→ 删掉重下一次。
  mismatchRetry,

  /// 校验失败(读不到版本号/文件不完整)→ 明确报错,不要交给安装器。
  invalid,
}

/// 决策:给出安装包与已装应用的信息,返回该怎么做。
///
/// - [apkVersionCode] / [apkVersionName]:下载到的 APK 自身信息(null 表示读取失败)
/// - [installedVersionCode]:系统里已安装的 versionCode(null 表示读取失败)
/// - [expectedVersion]:本次要更新到的版本号(如 1.7.29)
InstallDecision decideInstall({
  required int? apkVersionCode,
  required String? apkVersionName,
  required int? installedVersionCode,
  required String expectedVersion,
  String? apkPackageName,
  String expectedPackageName = '',
}) {
  // 包名必须是我们自己:下到别的应用(或构造的包)一律不装。
  if (apkPackageName != null &&
      expectedPackageName.isNotEmpty &&
      apkPackageName != expectedPackageName) {
    return InstallDecision.invalid;
  }
  // 读不到任何一方信息:不冒险交给安装器(fail-closed)
  if (apkVersionCode == null ||
      apkVersionCode <= 0 ||
      installedVersionCode == null ||
      installedVersionCode <= 0) {
    return InstallDecision.invalid;
  }
  // 下到了与目标版本不同的包(例如资产地址串到上一版)→ 重下一次
  final name = (apkVersionName ?? '').trim();
  if (name.isNotEmpty &&
      expectedVersion.isNotEmpty &&
      name != expectedVersion) {
    return InstallDecision.mismatchRetry;
  }
  // 安装包不高于已装版本:其实已是最新,别再调起系统安装器
  if (apkVersionCode <= installedVersionCode) {
    return InstallDecision.alreadyLatest;
  }
  return InstallDecision.install;
}
