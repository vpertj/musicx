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

  /// 签名与已装应用不一致 → 系统必然拒绝安装,必须重新下载官方包。
  ///
  /// 这是**独立于版本号**的一类失败:版本号再新,签名不同也装不上。
  /// 此前没有这一项,签名问题被系统含糊的失败提示吞掉,用户只能看到
  /// 「更新失败」而无法得知真正原因。
  signatureMismatch,
}

/// 安装前校验的完整证据(用于生成可读、可排查的失败原因)。
///
/// 抽成数据类是因为**报错必须能自证**:用户截图里的几个数字
/// (已装 code / 包内 code / 签名是否一致)就是定位问题所需要的一切。
class InstallFacts {
  /// 下载到的 APK 自身的信息。
  final int? apkVersionCode;
  final String? apkVersionName;
  final String? apkPackageName;
  final String? apkSignatureSha256;

  /// 系统里已安装应用的信息。
  final int? installedVersionCode;
  final String? installedSignatureSha256;

  /// 本次要更新到的版本名(如 1.7.40)。
  final String expectedVersion;

  const InstallFacts({
    required this.apkVersionCode,
    required this.apkVersionName,
    required this.apkPackageName,
    required this.apkSignatureSha256,
    required this.installedVersionCode,
    required this.installedSignatureSha256,
    required this.expectedVersion,
  });

  /// 比较用的短指纹(前 8 位即可区分,完整值太长不适合展示)。
  static String? shortSha(String? sha) {
    if (sha == null || sha.isEmpty) return null;
    return sha.length <= 8 ? sha : sha.substring(0, 8);
  }

  /// 签名是否一致。任一方读不到时返回 null(未知),而不是 false ——
  /// 「读不到」与「确实不一致」是两种不同的处置。
  bool? get signatureMatches {
    final a = apkSignatureSha256;
    final b = installedSignatureSha256;
    if (a == null || a.isEmpty || b == null || b.isEmpty) return null;
    return a.toLowerCase() == b.toLowerCase();
  }

  /// 一行式诊断信息:直接展示给用户,便于截图反馈。
  String describe() {
    final apkSig = shortSha(apkSignatureSha256) ?? '读不到';
    final insSig = shortSha(installedSignatureSha256) ?? '读不到';
    final match = signatureMatches;
    final sigText = match == null
        ? '签名无法比对(包内=$apkSig 已装=$insSig)'
        : (match ? '签名一致($apkSig)' : '签名不一致(包内=$apkSig 已装=$insSig)');
    return '安装包:${apkPackageName ?? "?"} '
        'v${apkVersionName ?? "?"}(code ${apkVersionCode ?? -1}) · '
        '已安装:code ${installedVersionCode ?? -1} · $sigText';
  }
}

/// 决策:给出安装包与已装应用的信息,返回该怎么做。
///
/// - [apkVersionCode] / [apkVersionName]:下载到的 APK 自身信息(null 表示读取失败)
/// - [installedVersionCode]:系统里已安装的 versionCode(null 表示读取失败)
/// - [expectedVersion]:本次要更新到的版本号(如 1.7.29)
/// - [apkSignatureSha256] / [installedSignatureSha256]:签名指纹;
///   两边都读到且不一致时直接判 [InstallDecision.signatureMismatch],
///   因为这种情况系统安装器必然拒绝,再往下比版本号没有意义。
InstallDecision decideInstall({
  required int? apkVersionCode,
  required String? apkVersionName,
  required int? installedVersionCode,
  required String expectedVersion,
  String? apkPackageName,
  String expectedPackageName = '',
  String? apkSignatureSha256,
  String? installedSignatureSha256,
}) {
  // 包名必须是我们自己:下到别的应用(或构造的包)一律不装。
  if (apkPackageName != null &&
      expectedPackageName.isNotEmpty &&
      apkPackageName != expectedPackageName) {
    return InstallDecision.invalid;
  }
  // 签名必须先查:签名不同时,版本号再新系统也不会装。
  // 只有**两边都读到且确实不同**才判签名不符;读不到时继续往下走,
  // 由 fail-closed 的版本校验兜底,避免因 ROM 读不到签名而误拦正常升级。
  if (apkSignatureSha256 != null &&
      apkSignatureSha256.isNotEmpty &&
      installedSignatureSha256 != null &&
      installedSignatureSha256.isNotEmpty &&
      apkSignatureSha256.toLowerCase() !=
          installedSignatureSha256.toLowerCase()) {
    return InstallDecision.signatureMismatch;
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
  // 安装包不高于已装版本:其实已是最新,别再调起系统安装器。
  // 注意这**正是系统 INSTALL_FAILED_VERSION_DOWNGRADE 的本地等价判断** ——
  // 提前拦下并给出数字,好过让系统安装器回一句含糊的「已安装最新版本」。
  if (apkVersionCode <= installedVersionCode) {
    return InstallDecision.alreadyLatest;
  }
  return InstallDecision.install;
}

/// 从资产直链里提取版本号(如 `.../download/v1.7.35/MusicX-1.7.35.apk` → 1.7.35)。
///
/// 用途:下载**之前**先核对直链里的版本,避免「更新检查给到旧版本直链 →
/// 白下载 60MB → 被系统以『已安装更高版本』拒绝」。
String? versionFromAssetUrl(String url) {
  if (url.isEmpty) return null;
  final m = RegExp(r'/v?(\d+\.\d+\.\d+)/').firstMatch(url);
  if (m != null) return m.group(1);
  final m2 = RegExp(r'MusicX-(\d+\.\d+\.\d+)').firstMatch(url);
  return m2?.group(1);
}

/// 下载前决策:直链版本是否值得下载。
enum PreDownloadDecision {
  /// 可以下载。
  proceed,

  /// 直链里的版本不高于已装版本 —— 更新检查结果过期/串版本,重新检查即可。
  staleCheck,
}

PreDownloadDecision decidePreDownload({
  required String assetUrl,
  required String installedVersion,
  required String expectedLatest,
}) {
  final urlVersion = versionFromAssetUrl(assetUrl);
  // 直链里没有版本号(非常规命名)时不拦,交给下载后的严格校验
  if (urlVersion == null) return PreDownloadDecision.proceed;
  // 直链版本与「最新版本」不一致 → 检查结果不可信
  if (expectedLatest.isNotEmpty && urlVersion != expectedLatest) {
    return PreDownloadDecision.staleCheck;
  }
  // 直链版本不高于已装版本 → 装了也白装(系统会以「已安装更高版本」拒绝)
  if (installedVersion.isNotEmpty &&
      _compare(urlVersion, installedVersion) <= 0) {
    return PreDownloadDecision.staleCheck;
  }
  return PreDownloadDecision.proceed;
}

int _compare(String a, String b) {
  final as = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final bs = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final len = as.length > bs.length ? as.length : bs.length;
  for (var i = 0; i < len; i++) {
    final x = i < as.length ? as[i] : 0;
    final y = i < bs.length ? bs[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
