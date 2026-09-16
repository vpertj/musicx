import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:musicx/core/updater/install_decision.dart';
import 'package:musicx/core/updater/package_magic.dart';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:musicx/core/updater/apk_installer.dart';
import 'package:musicx/core/updater/app_flavor.dart';
import 'package:musicx/core/updater/download_source.dart';

/// GitHub 仓库信息:更新检查与下载均基于此仓库的 Releases。
const kGitHubRepo = 'vpertj/musicx';

/// 更新流程中**不可换源重试**的失败(内容被篡改 / 文件校验不过)。
///
/// 为什么需要单独的类型:多源回退遇到普通错误(超时、5xx)应当换下一个源;
/// 但遇到 SHA256 不匹配这类**安全性失败**,继续换源就会拿 60MB 反复重下,
/// 既浪费流量又掩盖了真正的问题。用类型把两者区分开。
class FatalUpdateException implements Exception {
  final String message;
  const FatalUpdateException(this.message);

  @override
  String toString() => message;
}

/// 安卓安装包 MIME 类型(交给系统安装器时必须带)。
const kApkMimeType = 'application/vnd.android.package-archive';

/// 下载过程中「多久没收到任何数据」就判为本源卡死并换源(秒)。
///
/// 免费公共代理实测会出现连上后传输停滞的情况(30 秒 0 字节)。
/// 按「停滞时长」而非「总时长」判断:国内慢速下载 60MB 可能要几分钟,
/// 按总时长杀会误伤正常下载;但只要持续有数据就不该中断。
const kDownloadStallTimeoutSeconds = 45;

/// 是否支持「下载后应用内安装」:macOS 用 DMG 替换,Android 调系统安装器。
/// Windows/Linux 仍走打开 Release 页手动下载。
bool canAutoInstallFor({
  required bool isMacOS,
  required bool isAndroid,
  bool isWindows = false,
}) => isMacOS || isAndroid || isWindows;

/// 各平台对应的安装包后缀(用于在 Release 资产里挑包)。
String updateAssetSuffixFor({
  required bool isMacOS,
  required bool isWindows,
  required bool isAndroid,
}) {
  if (isMacOS) return '.dmg';
  if (isWindows) return '.exe';
  if (isAndroid) return '.apk';
  return '.tar.gz';
}

/// 下载后的本地文件名(按平台)。Windows 用的是 setup.exe,
/// 此前非安卓一律命名 .dmg,Windows 上会拿着 .dmg 去执行(错)。
///
/// [version] 传入目标版本时,文件名会带上版本号(如
/// `musicx_update_v1.7.38.apk`)—— 用户/文件管理器里一眼能分辨文件身份,
/// 避免把残留的旧包当成新包安装(实测踩过「安装界面显示旧版本号」)。
String updateDownloadFileNameFor({
  required bool isAndroid,
  bool isWindows = false,
  bool isMacOS = false,
  String? version,
}) {
  final tag = (version == null || version.isEmpty) ? '' : '_v$version';
  if (isAndroid) return 'musicx_update$tag.apk';
  if (isWindows) return 'musicx_update$tag.exe';
  if (isMacOS) return 'musicx_update$tag.dmg';
  return 'musicx_update$tag.pkg';
}

/// 从 GitHub `releases/expanded_assets/<tag>` 页面解析资产直链。
///
/// 注意:后缀必须用 [RegExp.escape],早期实现手写 `replaceAll('.', r'\.')`
/// 又叠加了字符串转义,最终正则要求 href 里含字面反斜杠,永远匹配不到 ——
/// 这正是「检查更新失败:没有找到 DMG 安装包」的根因(GitHub API 403 限流时
/// 必然走这条降级路径)。
String? parseAssetUrlFromExpandedAssets(String html, String suffix) {
  if (html.isEmpty) return null;
  final re = RegExp('href="([^"]*${RegExp.escape(suffix)})"');
  final m = re.firstMatch(html);
  if (m == null) return null;
  return 'https://github.com${m.group(1)}';
}

/// 按 CI 的资产命名约定直接拼下载直链(不依赖抓页面)。
/// 约定:`MusicX-<version><suffix>`,例如 MusicX-1.7.3.dmg / MusicX-1.7.3.apk。
String conventionalAssetUrl({
  required String repo,
  required String tag,
  required String version,
  required String suffix,
}) => 'https://github.com/$repo/releases/download/$tag/MusicX-$version$suffix';

/// 从 macOS Info.plist 文本中取 CFBundleShortVersionString;取不到返回空串。
String parseMacVersionFromPlist(String plistText) {
  final m = RegExp(
    '<key>CFBundleShortVersionString</key>\\s*<string>([^<]+)</string>',
  ).firstMatch(plistText);
  return m == null ? '' : m.group(1)!.trim();
}

/// 解析 GitHub `releases/latest` 的 JSON 响应(纯函数,便于单测)。
///
/// 抽出来是因为**直连与被代理的 API 响应结构完全相同**:国内直连失败时
/// 我们改走代理拿同一份 JSON,从而保住 SHA256 digest 这个关键字段 ——
/// 少了它,第三方下载代理就等于在无校验的情况下过境。
///
/// [flavor] 决定如何从 tag 里剥离前缀(吴玫静版 `v1.7.46`,
/// 标准版 `std-v1.7.46`)。**不属于本变体时返回 null**,由调用方跳过 ——
/// 这是防止「串版」的关键:标准版绝不能把吴玫静版的 release 当成自己的更新。
UpdateInfo? parseReleaseJson(
  String body, {
  required String assetSuffix,
  String releaseUrlFallback = '',
  AppFlavor? flavor,
}) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  return parseReleaseEntry(
    json,
    assetSuffix: assetSuffix,
    releaseUrlFallback: releaseUrlFallback,
    flavor: flavor ?? currentFlavor,
  );
}

/// 解析单条 release JSON;不属于指定变体时返回 null。
UpdateInfo? parseReleaseEntry(
  Map<String, dynamic> json, {
  required String assetSuffix,
  String releaseUrlFallback = '',
  required AppFlavor flavor,
}) {
  final tag = (json['tag_name'] as String?) ?? '';
  // 只认自己的 tag 前缀 —— 不匹配说明这条 release 属于另一个版本。
  final version = versionFromTag(tag, flavor);
  if (version == null) return null;
  // 草稿/预发布不作为更新来源
  if (json['draft'] == true || json['prerelease'] == true) return null;
  final assets = (json['assets'] as List?) ?? const [];
  String assetUrl = '';
  String? assetSha256;
  for (final a in assets) {
    if (a is! Map) continue;
    final name = a['name'] as String? ?? '';
    if (name.endsWith(assetSuffix)) {
      assetUrl = a['browser_download_url'] as String? ?? '';
      // GitHub asset digest 形如 "sha256:<64位hex>";提取 hex 部分。
      final digest = a['digest'] as String? ?? '';
      assetSha256 = digest.startsWith('sha256:')
          ? digest.substring('sha256:'.length).trim()
          : null;
      break;
    }
  }
  return UpdateInfo(
    latestVersion: version,
    currentVersion: '',
    dmgUrl: assetUrl,
    releaseUrl: (json['html_url'] as String?) ?? releaseUrlFallback,
    releaseNotes: json['body'] as String?,
    dmgSha256: assetSha256,
  );
}

/// 从 release 列表里挑出**本变体**的最新一条(纯函数,便于单测)。
///
/// 为什么不用 `/releases/latest`:它返回全仓库最新的 release,不区分变体。
/// 两个版本并存时,标准版的用户会收到吴玫静版的更新提示(串版)。
/// 因此改为拉取列表后按 tag 前缀筛选,再取版本号最大的一条。
UpdateInfo? pickLatestForFlavor(
  List<Map<String, dynamic>> releases, {
  required String assetSuffix,
  required AppFlavor flavor,
  String releaseUrlFallback = '',
}) {
  UpdateInfo? best;
  for (final r in releases) {
    final info = parseReleaseEntry(
      r,
      assetSuffix: assetSuffix,
      releaseUrlFallback: releaseUrlFallback,
      flavor: flavor,
    );
    if (info == null) continue;
    if (best == null ||
        compareVersions(info.latestVersion, best.latestVersion) > 0) {
      best = info;
    }
  }
  return best;
}

/// 更新检查结果。
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String dmgUrl;
  final String releaseUrl;
  final String? releaseNotes;

  /// DMG 的 SHA256 摘要(十六进制,不含 "sha256:" 前缀)。
  /// 来自 GitHub Release asset 的 digest 字段;用于下载后完整性校验。
  /// 若来源未提供(如降级解析网页),为 null 时跳过校验。
  final String? dmgSha256;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.dmgUrl,
    required this.releaseUrl,
    this.releaseNotes,
    this.dmgSha256,
  });

  bool get hasUpdate => compareVersions(latestVersion, currentVersion) > 0;
}

/// 数字版本比较:a > b 返回正数,a < b 返回负数,相等返回 0。
/// 支持 '1.0.0' / '1.2' 等常见格式,忽略非数字段。
int compareVersions(String a, String b) {
  final as = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final bs = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final len = as.length > bs.length ? as.length : bs.length;
  for (var i = 0; i < len; i++) {
    final av = i < as.length ? as[i] : 0;
    final bv = i < bs.length ? bs[i] : 0;
    if (av != bv) return av > bv ? 1 : -1;
  }
  return 0;
}

/// 应用自动更新服务:检查 GitHub Release → 下载 DMG → 替换安装 → 重启。
///
/// 重启机制:先写一个带延迟的 shell 脚本,脚本等待本进程退出后
/// 用 `open` 重新启动新版本,从而避免替换中的 .app 被占用。
class UpdateService {
  UpdateService({http.Client? client, Directory? downloadDir})
      : _client = client ?? http.Client(),
        _downloadDirOverride = downloadDir;

  final http.Client _client;

  /// 测试注入的下载目录;为 null 时按平台选择。
  final Directory? _downloadDirOverride;

  /// 当前应用版本:读取运行时 bundle 的 CFBundleShortVersionString。
  ///
  /// 不依赖外部 PlistBuddy(跨平台):直接解析 Info.plist 中的
  /// `CFBundleShortVersionString` 字符串值;失败时返回 '0.0.0'。
  static String currentVersion() {
    try {
      final exe = Platform.resolvedExecutable;
      // exe = .../musicx.app/Contents/MacOS/musicx
      final contentsDir = File(exe).parent.parent; // .../musicx.app/Contents
      final plist = File('${contentsDir.path}/Info.plist');
      if (plist.existsSync()) {
        final parsed = parseMacVersionFromPlist(plist.readAsStringSync());
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (_) {}
    return '0.0.0';
  }

  /// 当前平台是否支持"下载后应用内安装"。
  /// 支持应用内自动安装的平台:macOS(DMG 挂载替换)、Android(系统安装器)、
  /// Windows(Inno Setup 静默安装)。其余平台打开 Release 页手动下载。
  static bool get canAutoInstall => canAutoInstallFor(
    isMacOS: Platform.isMacOS,
    isAndroid: Platform.isAndroid,
    isWindows: Platform.isWindows,
  );

  /// 当前平台期望的安装包后缀(用于在 Release 资产中挑选)。
  static String get _assetSuffix => updateAssetSuffixFor(
        isMacOS: Platform.isMacOS,
        isWindows: Platform.isWindows,
        isAndroid: Platform.isAndroid,
      );

  /// 清空版本号缓存(应用内安装完成后必须调用)。
  ///
  /// 实测问题:旧进程在启动时把「1.7.11」缓存住了,应用内装上 1.7.13 后仍按
  /// 缓存判断「有新版本」,再点更新就会拿同版本 APK 去装,被系统安装器以
  /// 「已安装了更高版本」拒绝。清缓存后重读 PackageManager 即为新版本。
  static void invalidateVersionCache() {
    _cachedVersion = null;
    _cachedVersionCode = null;
  }

  /// 已知的当前版本号(同步):优先返回解析缓存;安卓未解析过时返回 null,
  /// 避免把 macOS 专用的 0.0.0 当作真实版本显示出来。
  static String? knownVersion() {
    if (_cachedVersion != null) return _cachedVersion;
    final v = currentVersion();
    return v == '0.0.0' ? null : v;
  }

  /// 当前版本号(异步):安卓走平台通道读 versionName;
  /// 其它平台沿用 Info.plist 解析。读取结果缓存,避免重复过通道。
  static String? _cachedVersion;

  /// 缓存对应的 versionCode(仅安卓)。用于识别「应用已被新版本替换」:
  /// versionName 可能没变(比如只改了 versionCode),只比字符串会漏判。
  static int? _cachedVersionCode;

  /// 读取当前版本号。
  ///
  /// 安卓上**每次都用 versionCode 校验缓存是否仍然有效**:用户中途取消安装、
  /// 或安装完成后旧进程没退出时,进程内缓存会一直停留在旧版本号,导致
  /// 「明明装过了还一直提示有新版本」→ 再点更新就被系统以
  /// 「已安装更高版本」拒绝。这里发现 versionCode 变了就自动作废缓存,
  /// 不依赖调用方记得手动清。
  Future<String> resolveCurrentVersion() async {
    if (Platform.isAndroid) {
      try {
        final code = await ApkInstaller.versionCode();
        if (_cachedVersion != null &&
            (code == null || code == _cachedVersionCode)) {
          return _cachedVersion!;
        }
        final v = await ApkInstaller.versionName();
        if (v != null && v.isNotEmpty) {
          _cachedVersion = v;
          _cachedVersionCode = code;
          return v;
        }
      } catch (_) {}
    }
    if (_cachedVersion != null) return _cachedVersion!;
    final v = currentVersion();
    // macOS 之外读不到 bundle 版本时不要缓存 '0.0.0',否则永远提示有新版本。
    if (v != '0.0.0') _cachedVersion = v;
    return v;
  }

  /// 检查最新版本。失败时抛出异常。
  ///
  /// 三级取数,逐级降级(**顺序体现可靠性优先级**):
  ///   ① 直连 api.github.com(信息最全,含 SHA256 digest);
  ///   ② 经免费加速代理访问 api.github.com(国内直连被污染时的出路,
  ///      同样能拿到 digest → 仍可做完整性校验);
  ///   ③ 抓 releases 网页(最后的兜底,拿不到 digest)。
  ///
  /// ②③ 的存在是因为国内访问 api.github.com 经常超时/被污染。
  /// ② 优先于 ③,因为它能保留 **SHA256 完整性校验能力** ——
  /// 少了它,引入第三方下载代理就等于让安装包在无校验的情况下过境。
  Future<UpdateInfo> checkForUpdate() async {
    try {
      return await _checkViaApi();
    } on HttpException {
      // ③ 之前先试代理版 API:能拿到 digest 就不要退到无校验的网页路径。
      // 只使用**实测能透传 api.github.com** 的代理(另一些对 API 返回 403)。
      for (final prefix in kApiCapableProxyPrefixes) {
        try {
          return await _checkViaApi(
            apiBase: proxyWrap(prefix, 'https://api.github.com'),
          );
        } on HttpException {
          continue;
        }
      }
      return await _checkViaWebPage();
    }
  }

  /// 读取 releases/latest 的 JSON 并解析成 [UpdateInfo]。
  ///
  /// [apiBase] 允许把请求指向加速代理(代理会把 `/<path>` 透传给
  /// api.github.com)。默认直连。
  Future<UpdateInfo> _checkViaApi({String? apiBase}) async {
    final base = apiBase ?? 'https://api.github.com';
    // 用 /releases(列表)而非 /releases/latest:后者不区分变体,
    // 会让标准版收到吴玫静版的更新(串版)。筛选靠 tag 前缀完成。
    final uri = Uri.parse('$base/repos/$kGitHubRepo/releases?per_page=100');
    final resp = await _client
        .get(uri, headers: const {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw HttpException('检查更新失败 (HTTP ${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) {
      throw const HttpException('检查更新失败:返回格式异常');
    }
    final releases = [
      for (final e in decoded)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    final info = pickLatestForFlavor(
      releases,
      assetSuffix: _assetSuffix,
      flavor: currentFlavor,
      releaseUrlFallback: 'https://github.com/$kGitHubRepo/releases',
    );
    if (info == null) {
      throw HttpException(
        '没有找到「${currentFlavor.displayName}」的发布版本'
        '(tag 前缀应为 ${currentFlavor.tagPrefix})',
      );
    }
    if (info.dmgUrl.isEmpty && canAutoInstall) {
      throw HttpException('最新 Release 中没有找到可自动安装的更新包');
    }
    return UpdateInfo(
      latestVersion: info.latestVersion,
      currentVersion: await resolveCurrentVersion(),
      dmgUrl: info.dmgUrl,
      releaseUrl: info.releaseUrl,
      releaseNotes: info.releaseNotes,
      dmgSha256: info.dmgSha256,
    );
  }

  /// 降级方案:抓取 releases 页面解析版本号,
  /// 再请求 expanded_assets 端点(HTML 片段)解析安装包直链。
  ///
  /// 同样必须按变体筛选:直接抓 `/releases/latest` 会把另一个版本的
  /// tag 当成自己的更新(串版)。这里改为抓 `/releases` 列表页,
  /// 用本变体的 tag 前缀在所有 tag 中挑版本号最大的一个。
  Future<UpdateInfo> _checkViaWebPage() async {
    final url = 'https://github.com/$kGitHubRepo/releases';
    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw HttpException('检查更新失败 (HTTP ${resp.statusCode})');
    }
    // 页面里会出现形如 releases/tag/<tag> 的链接;收集全部再去重。
    final tagRe = RegExp(r'releases/tag/([^"\s?#]+)');
    final seen = <String>{};
    String? bestTag;
    String? bestVersion;
    for (final m in tagRe.allMatches(resp.body)) {
      final tag = Uri.decodeComponent(m.group(1)!);
      if (!seen.add(tag)) continue;
      final v = versionFromTag(tag, currentFlavor);
      if (v == null) continue;
      if (bestVersion == null || compareVersions(v, bestVersion) > 0) {
        bestVersion = v;
        bestTag = tag;
      }
    }
    if (bestTag == null || bestVersion == null) {
      throw HttpException(
        '没有找到「${currentFlavor.displayName}」的发布版本'
        '(tag 前缀应为 ${currentFlavor.tagPrefix})',
      );
    }
    final tag = bestTag;
    final latest = bestVersion;

    // 请求资产列表端点(返回 HTML 片段,含下载链接)
    final assetsUrl =
        'https://github.com/$kGitHubRepo/releases/expanded_assets/$tag';
    final assetsResp = await _client.get(Uri.parse(assetsUrl));
    if (assetsResp.statusCode != 200) {
      throw HttpException('无法获取更新包列表 (HTTP ${assetsResp.statusCode})');
    }
    // 按当前平台后缀在资产页面中挑选安装包。
    final suffix = _assetSuffix;
    var assetUrl =
        parseAssetUrlFromExpandedAssets(assetsResp.body, suffix) ?? '';
    // 抓页面失败时按 CI 命名约定直接拼直链(不依赖 GitHub HTML 结构)。
    if (assetUrl.isEmpty) {
      assetUrl = conventionalAssetUrl(
        repo: kGitHubRepo,
        tag: tag,
        version: latest,
        suffix: suffix,
      );
    }
    if (assetUrl.isEmpty && canAutoInstall) {
      throw HttpException('最新 Release 中没有找到可自动安装的更新包');
    }
    return UpdateInfo(
      latestVersion: latest,
      currentVersion: await resolveCurrentVersion(),
      dmgUrl: assetUrl,
      releaseUrl: 'https://github.com/$kGitHubRepo/releases/tag/$tag',
    );
  }

  /// 下载安装包到临时文件,返回本地路径。
  ///
  /// **多源回退**:先直连 GitHub;失败(超时/连接失败/5xx/限流)则依次尝试
  /// 免费公共加速代理。国内访问 release 资产所在的
  /// `release-assets.githubusercontent.com` 经常只有几十 KB/s 甚至断流,
  /// 走代理是零成本且实测有效的出路。
  ///
  /// 安全性:无论走哪个源,下载后都会做 Content-Length 完整性校验、
  /// 魔数格式校验与 SHA256 校验([expectedSha256]),被篡改的包会被拒。
  ///
  /// [onProgress] 回调下载进度(0.0 ~ 1.0);换源时会回调一次负数表示重来
  /// (UI 据此重置进度条),调用方需容忍 progress < 0。
  /// [sources] 允许注入自定义源列表(测试用)。
  Future<File> download(
    String url, {
    void Function(double)? onProgress,
    String? expectedSha256,
    String? version,
    List<DownloadSource>? sources,
  }) async {
    // 安卓必须落在应用私有目录(cache),否则 FileProvider 无法把 APK 交给
    // 系统安装器;桌面沿用系统临时目录。
    final dir = _downloadDirOverride ??
        (Platform.isAndroid
            ? await getTemporaryDirectory()
            : Directory.systemTemp);
    final file = File(
      '${dir.path}/${updateDownloadFileNameFor(
        isAndroid: Platform.isAndroid,
        isWindows: Platform.isWindows,
        isMacOS: Platform.isMacOS,
        version: version,
      )}',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    // 清掉所有历史更新包:万一有旧版本残留(musicx_update*.apk),
    // 交给安装器时会以「已安装更高版本」被拒,且用户看到的版本对不上。
    try {
      for (final e in dir.listSync()) {
        if (e is File && e.path.split('/').last.startsWith('musicx_update')) {
          e.deleteSync();
        }
      }
    } catch (_) {}
    if (file.existsSync()) file.deleteSync();

    // 只对 GitHub 域名做代理改写:自建 OSS/CDN 等直链不应被叠加代理。
    final candidates = (sources ??
            (isRewritableGitHubUrl(url)
                ? buildDownloadSources()
                : const [DownloadSource.direct]))
        .toList();

    final failures = <String>[];
    for (var i = 0; i < candidates.length; i++) {
      final source = candidates[i];
      final target = source.rewrite(url);
      try {
        debugPrint(
          'MusicX 更新下载: 尝试来源「${source.label}」'
          '(${i + 1}/${candidates.length})',
        );
        return await _downloadFrom(
          target,
          file: file,
          onProgress: onProgress,
          expectedSha256: expectedSha256,
          label: source.label,
        );
      } on FatalUpdateException {
        // 安全性失败(SHA256 不符):**立即终止**。
        // 换下一个源只会再下 60MB 去撞同样的结果,而且真正的问题是
        // 「拿到的内容不对」,不该被"重试"掩盖。
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
        rethrow;
      } on HttpException catch (e) {
        // 换源前把半成品清掉,避免下一次续写/误判
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
        failures.add('${source.label}: ${_shortReason(e.message)}');
        debugPrint('MusicX 更新下载: 来源「${source.label}」失败 → $e');
        // 换源重来:通知 UI 重置进度
        if (onProgress != null && i + 1 < candidates.length) onProgress(-1);
      }
    }
    throw HttpException(
      '所有下载源都失败了(${failures.length} 个):\n${failures.join('\n')}\n'
      '请检查网络后重试,或到 GitHub Releases 手动下载。',
    );
  }

  /// 把异常信息压成一行,便于在"所有源都失败"的汇总里展示。
  String _shortReason(String message) {
    final oneLine = message.replaceAll('\n', ' ').trim();
    return oneLine.length > 80 ? '${oneLine.substring(0, 80)}…' : oneLine;
  }

  /// 从**单个** URL 下载并完成全部校验;失败抛 [HttpException]。
  Future<File> _downloadFrom(
    String url, {
    required File file,
    void Function(double)? onProgress,
    String? expectedSha256,
    required String label,
  }) async {
    final req = http.Request('GET', Uri.parse(url));
    // GitHub 下载需要 UA,否则部分 CDN 拒绝
    req.headers['User-Agent'] = 'MusicX/${currentVersion()}';
    final http.StreamedResponse resp;
    try {
      resp = await _client.send(req).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw HttpException('连接超时(30 秒无响应)');
    } catch (e) {
      throw HttpException('连接失败:$e');
    }
    if (resp.statusCode != 200) {
      await resp.stream.drain<void>();
      throw HttpException('HTTP ${resp.statusCode}');
    }
    final total = resp.contentLength;
    var received = 0;
    final sink = file.openWrite();
    // sink 必须**只关闭一次**:catch 里关过之后,finally 再 flush/close
    // 一个已关闭的 IOSink 会永久挂起(实测:外层 Future 永不完成,
    // 应用卡死在「下载中」)。用一个标志位保证唯一一次关闭。
    var sinkClosed = false;
    Future<void> closeSink() async {
      if (sinkClosed) return;
      sinkClosed = true;
      try {
        await sink.flush();
      } catch (_) {}
      try {
        await sink.close();
      } catch (_) {}
    }

    try {
      // **停滞检测**:免费公共代理实测会出现「连上了但传输卡死」
      // (30 秒零字节),而 `_client.send()` 的 timeout 只覆盖建立连接,
      // 对传输过程无效 —— 没有这层保护,应用会永久卡在「下载中」。
      //
      // 判定:只要在 [kDownloadStallTimeoutSeconds] 内一个字节都没收到,
      // 就判为本源卡死并换下一个源;只要持续有数据进来,总耗时不受限制
      // (国内慢速下载 60MB 可能要好几分钟,不能按总时长杀)。
      final stall = Duration(seconds: kDownloadStallTimeoutSeconds);
      final stream = resp.stream.timeout(
        stall,
        onTimeout: (s) => s.addError(
          TimeoutException('传输停滞 ${stall.inSeconds} 秒无数据'),
        ),
      );
      await for (final chunk in stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await closeSink();
    } catch (e) {
      // 传输中断/停滞(代理断流常见):换源重试,不要留下半截文件
      await closeSink();
      throw HttpException(
        received > 0 ? '传输中断(已收到 $received 字节):$e' : '传输停滞:$e',
      );
    }

    // ① 完整性:声明了 Content-Length 就必须下满,否则是断流。
    if (total != null && total > 0 && received != total) {
      throw HttpException('下载不完整($received/$total 字节)');
    }
    // ② 格式:**按平台各自的魔数**校验(APK=PK 开头 / Windows=MZ 开头 /
    //    macOS DMG=结尾 koly trailer)。
    //    上一版这里写死「必须以 PK 开头」,而 DMG 不是 ZIP → macOS 必然报
    //    「不是有效的安装包」,安卓端也一并误拦(用户实测截图)。
    try {
      final kind = packageKindFor(
        isAndroid: Platform.isAndroid,
        isMacOS: Platform.isMacOS,
        isWindows: Platform.isWindows,
      );
      final head = await file.openRead(0, 8).fold<List<int>>(
        <int>[],
        (a, b) => a..addAll(b),
      );
      List<int>? tail;
      if (kind == PackageKind.dmg) {
        final len = await file.length();
        if (len >= 512) {
          tail = await file.openRead(len - 512, len - 508).fold<List<int>>(
            <int>[],
            (a, b) => a..addAll(b),
          );
        }
      }
      final ok = looksLikePackage(kind: kind, head: head, tail: tail);
      debugPrint(
        'MusicX 更新校验: 格式=${kind.name} head=${head.take(2).toList()} '
        'ok=$ok size=${await file.length()}',
      );
      if (!ok) {
        file.deleteSync();
        throw HttpException('下载到的文件不是有效的安装包,已作废,请重新下载');
      }
    } on HttpException {
      rethrow;
    } catch (_) {
      // 读取失败按无效处理(宁可不装)
      try {
        file.deleteSync();
      } catch (_) {}
      throw HttpException('安装包校验失败(无法读取文件),请重新下载');
    }

    // SHA256 完整性校验:不匹配说明下载被篡改/损坏,拒绝安装并清理。
    //
    // **这里刻意不当作"换源重试"的理由**:SHA256 不符意味着内容被篡改
    // (或下载源返回了错误的文件),属于安全性失败,直接终止并告知用户
    // 比默默换下一个代理更安全、也更容易定位问题。
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final actual = await _sha256Of(file);
      if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
        try {
          file.deleteSync();
        } catch (_) {}
        throw FatalUpdateException(
          '更新包完整性校验失败(SHA256 不匹配),已拒绝安装。'
          '(来源: $label)\n'
          '这份安装包与 GitHub 官方发布的不一致,可能被篡改或下载损坏。\n'
          '请检查网络后重试,或手动从 GitHub Release 下载。',
        );
      }
    }
    return file;
  }

  /// 计算文件 SHA256(十六进制小写)。
  Future<String> _sha256Of(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// 读取 .app 内 Info.plist 的 CFBundleShortVersionString(失败返回 null)。
  Future<String?> _bundleVersion(String plistPath) async {
    try {
      final r = await Process.run('/usr/libexec/PlistBuddy', [
        '-c',
        'Print :CFBundleShortVersionString',
        plistPath,
      ]);
      if (r.exitCode != 0) return null;
      final v = r.stdout.toString().trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// 安装包校验结果(供 UI/日志展示)。
  ///
  /// 抽成独立方法是为了**可测试**:真机上「下载到的包版本不对」这类问题
  /// 只能靠版本号核对定位。
  Future<
    ({
      InstallDecision decision,
      int? apkCode,
      String? apkVersion,
      String? apkPackageName,
      int? installedVersion,
      InstallFacts facts,
    })
  >
  verifyPackageForInstall({
    required String path,
    required String expectedVersion,
  }) async {
    final apkCode = await ApkInstaller.versionCodeOf(path);
    final apkName = await ApkInstaller.versionNameOf(path);
    final apkPkg = await ApkInstaller.packageNameOf(path);
    final apkSig = await ApkInstaller.signatureSha256Of(path);
    final installedCode = await ApkInstaller.versionCode();
    final installedSig = await ApkInstaller.installedSignatureSha256();
    final facts = InstallFacts(
      apkVersionCode: apkCode,
      apkVersionName: apkName,
      apkPackageName: apkPkg,
      apkSignatureSha256: apkSig,
      installedVersionCode: installedCode,
      installedSignatureSha256: installedSig,
      expectedVersion: expectedVersion,
    );
    final decision = decideInstall(
      apkVersionCode: apkCode,
      apkVersionName: apkName,
      installedVersionCode: installedCode,
      expectedVersion: expectedVersion,
      apkPackageName: apkPkg,
      expectedPackageName: ApkInstaller.androidPackageName,
      apkSignatureSha256: apkSig,
      installedSignatureSha256: installedSig,
    );
    debugPrint(
      'MusicX 更新校验: 安装包=$apkPkg v${apkName ?? "?"}($apkCode) '
      '已装=$installedCode 目标=v$expectedVersion → ${decision.name}',
    );
    debugPrint('MusicX 更新校验详情: ${facts.describe()}');
    return (
      decision: decision,
      apkCode: apkCode,
      apkVersion: apkName,
      apkPackageName: apkPkg,
      installedVersion: installedCode,
      facts: facts,
    );
  }

  /// 用 DMG 替换当前应用并重启。
  ///
  /// 步骤:挂载 DMG → 复制新版 .app 覆盖当前 .app → 卸载 DMG →
  /// 生成重启脚本(延迟 2s,等本进程退出后 `open` 新应用) → 退出当前进程。
  Future<void> installAndRestart(File package, {String? version}) async {
    // 安卓:把下载好的 APK 交给系统安装器(首次需用户授权「安装未知应用」)。
    // 安装器接管后本进程不需要退出,系统会在安装完成时替换并重启应用。
    if (Platform.isAndroid) {
      // 交给安装器前**严格核对**(用户反复遇到「提示有新版却报已安装相同版本」):
      //   ① 包名必须是我们自己;
      //   ② 签名必须与已装应用一致(不一致系统必然拒绝);
      //   ③ 必须能读出安装包与已装应用的版本号(fail-closed,读不到就不装);
      //   ④ 安装包的 versionName 必须等于本次要更新的目标版本;
      //   ⑤ 安装包 versionCode 必须严格大于已装版本。
      // 任一不满足都给出可读原因 + 具体数字,绝不再把含糊的
      // 「已安装相同版本 / 更新失败」留给系统提示。
      final result = await verifyPackageForInstall(
        path: package.path,
        expectedVersion: version ?? '',
      );
      switch (result.decision) {
        case InstallDecision.install:
          break;
        // 签名不符:系统必然拒绝(INSTALL_FAILED_UPDATE_INCOMPATIBLE)。
        // 给用户可执行的出路,而不是含糊的「更新失败」。
        case InstallDecision.signatureMismatch:
          throw HttpException(
            '安装包签名与当前应用不一致,系统会拒绝安装。\n'
            '${result.facts.describe()}\n'
            '这个包不是用同一个签名密钥发布的,无法覆盖安装。'
            '请从官方 Release 重新下载;若当前应用是早期用别的密钥签的,'
            '需要卸载后重装(会清除本地歌曲与设置,请先备份)。',
          );
        case InstallDecision.alreadyLatest:
          UpdateService.invalidateVersionCache();
          throw HttpException(
            '当前已是最新版本(code ${result.installedVersion}),'
            '安装包 code=${result.apkCode} 不高于它,'
            '系统会以「已安装更高版本」拒绝。\n'
            '${result.facts.describe()}',
          );
        case InstallDecision.mismatchRetry:
          unawaited(package.delete().catchError((_) => package));
          throw HttpException(
            '下载到的安装包是 v${result.apkVersion}'
            '(code=${result.apkCode}),与目标版本 v$version 不一致,已作废,'
            '请重新点击更新。\n${result.facts.describe()}',
          );
        case InstallDecision.invalid:
          throw HttpException('安装包校验失败,请重新下载。\n${result.facts.describe()}');
      }
      debugPrint(
        'MusicX 更新: 交给系统安装器 包名=${result.apkPackageName} '
        'v${result.apkVersion}(code=${result.apkCode}) '
        '已装 code=${result.installedVersion}',
      );
      final ok = await ApkInstaller.installApk(package.path);
      if (!ok) {
        throw HttpException('未能调起系统安装器,请到「设置 → 应用 → 未知来源」授权后重试');
      }
      return;
    }
    // Windows:交给 Inno Setup 安装包静默安装。
    //
    // 参数含义(Inno Setup 官方约定):
    //   /SILENT            显示进度但不需交互
    //   /SUPPRESSMSGBOXES  不弹消息框
    //   /CLOSEAPPLICATIONS 用 Restart Manager 关闭正在运行的旧版本(否则文件被占用)
    //   /RESTARTAPPLICATIONS 安装完成后自动重新启动应用
    //   /NORESTART         不重启系统
    // 安装到 Program Files 时需要管理员权限,UAC 会由系统弹一次(用户确认即可)。
    if (Platform.isWindows) {
      final p = await Process.start(
        package.path,
        [
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/CLOSEAPPLICATIONS',
          '/RESTARTAPPLICATIONS',
          '/NORESTART',
        ],
        runInShell: false,
      );
      debugPrint('MusicX 更新: 已启动 Windows 安装包 pid=${p.pid}');
      // 给安装器一点时间接管(Restart Manager 会关闭本进程),随后主动退出,
      // 避免旧进程占用文件导致替换失败。
      await Future<void>.delayed(const Duration(seconds: 2));
      exit(0);
    }

    // macOS:DMG 挂载替换;其余平台应走"打开 Release 页"。
    if (!Platform.isMacOS) {
      throw HttpException('当前平台不支持自动安装,请从 GitHub Release 手动下载');
    }
    final dmg = package;
    // 1. 挂载 DMG 到显式的临时挂载点,避免解析 stdout 的路径(脆弱)。
    final mountPoint = Directory(
      '${Directory.systemTemp.path}/musicx_update_mount',
    );
    if (mountPoint.existsSync()) mountPoint.deleteSync(recursive: true);
    mountPoint.createSync(recursive: true);
    final mount = await Process.run('hdiutil', [
      'attach',
      dmg.path,
      '-nobrowse',
      '-readonly',
      '-mountpoint',
      mountPoint.path,
    ]);
    if (mount.exitCode != 0) {
      throw HttpException('挂载更新包失败: ${mount.stderr}');
    }

    final newAppDir = Directory(mountPoint.path);
    Directory? newApp;
    await for (final e in newAppDir.list()) {
      if (e is Directory && e.path.endsWith('.app')) {
        newApp = e;
        break;
      }
    }
    if (newApp == null) throw HttpException('更新包中没有找到应用');

    // 校验新 .app 的版本号:与安卓同样坚持「下载到的必须就是目标版本」,
    // 防止拿到旧包/错包后把好端端的应用替换成旧版本。
    final plistPath = '${newApp.path}/Contents/Info.plist';
    final newVersion = await _bundleVersion(plistPath);
    if (version != null &&
        version.isNotEmpty &&
        newVersion != null &&
        newVersion != version) {
      await Process.run('hdiutil', ['detach', mountPoint.path, '-force']);
      throw HttpException('更新包版本($newVersion)与目标版本($version)不一致,已取消安装');
    }
    debugPrint('MusicX 更新校验(macOS): 包内版本=${newVersion ?? "?"} 目标=v$version');

    // 3. 覆盖当前应用
    //    先复制到临时位置再原子替换,避免运行中的 .app 被占用导致失败
    final exe = Platform.resolvedExecutable;
    final currentApp = File(exe).parent.parent.parent; // .../musicx.app
    final backup = Directory('${currentApp.path}.old');
    if (backup.existsSync()) backup.deleteSync(recursive: true);
    // 复制旧版到备份(若失败不阻断;仅用于回滚)
    await Process.run('ditto', ['--rsrc', currentApp.path, backup.path]);
    // 复制新版覆盖当前 .app
    final copy = await Process.run('ditto', [
      '--rsrc',
      newApp.path,
      currentApp.path,
    ]);
    if (copy.exitCode != 0) {
      // 替换失败:回滚备份
      if (backup.existsSync()) {
        await Process.run('ditto', ['--rsrc', backup.path, currentApp.path]);
      }
      throw HttpException('替换应用失败: ${copy.stderr}');
    }
    // 去掉来自 DMG 的隔离属性:否则新版本首次启动可能被 Gatekeeper 拦住
    // (「无法验证开发者」/「已损坏」)。这是自更新应用的常规处理。
    await Process.run('xattr', [
      '-dr',
      'com.apple.quarantine',
      currentApp.path,
    ]);

    // 清理备份
    if (backup.existsSync()) backup.deleteSync(recursive: true);

    // 4. 卸载 DMG
    await Process.run('hdiutil', ['detach', mountPoint.path, '-force']);
    // 清理临时挂载点目录
    try {
      if (mountPoint.existsSync()) mountPoint.deleteSync(recursive: true);
    } catch (_) {}

    // 5. 生成重启脚本(延迟 2s,等本进程退出后启动新版本)
    //    用 nohup + 独立进程组,确保父进程 exit 后脚本仍执行
    final script = File('${Directory.systemTemp.path}/musicx_restart.sh');
    script.writeAsStringSync(
      '#!/bin/sh\n'
      '# 等待当前进程完全退出\n'
      'sleep 2\n'
      'open "${currentApp.path}"\n',
    );
    await Process.run('chmod', ['+x', script.path]);
    // detached 模式:脚本独立于本进程运行,exit(0) 不会杀掉它
    await Process.start('/bin/sh', [
      script.path,
    ], mode: ProcessStartMode.detached);

    // 6. 退出当前进程,让重启脚本接管
    exit(0);
  }
}
