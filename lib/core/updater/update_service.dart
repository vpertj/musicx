import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:musicx/core/updater/install_decision.dart';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:musicx/core/updater/apk_installer.dart';

/// GitHub 仓库信息:更新检查与下载均基于此仓库的 Releases。
const kGitHubRepo = 'vpertj/musicx';

/// 安卓安装包 MIME 类型(交给系统安装器时必须带)。
const kApkMimeType = 'application/vnd.android.package-archive';

/// 是否支持「下载后应用内安装」:macOS 用 DMG 替换,Android 调系统安装器。
/// Windows/Linux 仍走打开 Release 页手动下载。
bool canAutoInstallFor({required bool isMacOS, required bool isAndroid}) =>
    isMacOS || isAndroid;

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

/// 下载后的本地文件名。
String updateDownloadFileNameFor({required bool isAndroid}) =>
    isAndroid ? 'musicx_update.apk' : 'musicx_update.dmg';

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
  /// macOS:DMG 挂载替换;Android:下载 APK 后调系统安装器。
  /// Windows/Linux:打开 Release 页手动下载。
  static bool get canAutoInstall =>
      canAutoInstallFor(isMacOS: Platform.isMacOS, isAndroid: Platform.isAndroid);

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
  static void invalidateVersionCache() => _cachedVersion = null;

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

  Future<String> resolveCurrentVersion() async {
    if (_cachedVersion != null) return _cachedVersion!;
    if (Platform.isAndroid) {
      try {
        final v = await ApkInstaller.versionName();
        if (v != null && v.isNotEmpty) {
          _cachedVersion = v;
          return v;
        }
      } catch (_) {}
    }
    final v = currentVersion();
    // macOS 之外读不到 bundle 版本时不要缓存 '0.0.0',否则永远提示有新版本。
    if (v != '0.0.0') _cachedVersion = v;
    return v;
  }

  /// 检查最新版本。失败时抛出异常。
  ///
  /// 优先走 GitHub API;若触发未认证限流(403),降级为直接访问 releases/latest
  /// 网页并解析其中的版本号与 DMG 下载链接。
  Future<UpdateInfo> checkForUpdate() async {
    try {
      return await _checkViaApi();
    } on HttpException {
      return await _checkViaWebPage();
    }
  }

  Future<UpdateInfo> _checkViaApi() async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$kGitHubRepo/releases/latest',
    );
    final resp = await _client.get(
      uri,
      headers: const {'Accept': 'application/vnd.github+json'},
    );
    if (resp.statusCode != 200) {
      throw HttpException('检查更新失败 (HTTP ${resp.statusCode})');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?) ?? '';
    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    final assets = (json['assets'] as List?) ?? const [];
    String assetUrl = '';
    String? assetSha256;
    final suffix = _assetSuffix;
    for (final a in assets) {
      final name = a['name'] as String? ?? '';
      if (name.endsWith(suffix)) {
        assetUrl = a['browser_download_url'] as String? ?? '';
        // GitHub asset digest 形如 "sha256:<64位hex>";提取 hex 部分。
        final digest = a['digest'] as String? ?? '';
        assetSha256 = digest.startsWith('sha256:')
            ? digest.substring('sha256:'.length).trim()
            : null;
        break;
      }
    }
    // macOS 必须找到 DMG 才能自动安装;其他平台仅需 Release 页链接(手动下载)。
    if (assetUrl.isEmpty && canAutoInstall) {
      throw HttpException('最新 Release 中没有找到可自动安装的更新包');
    }
    return UpdateInfo(
      latestVersion: latest,
      currentVersion: await resolveCurrentVersion(),
      dmgUrl: assetUrl,
      releaseUrl: json['html_url'] as String? ?? '',
      releaseNotes: json['body'] as String?,
      dmgSha256: assetSha256,
    );
  }

  /// 降级方案:抓取 releases/latest 页面解析版本号,
  /// 再请求 expanded_assets 端点(HTML 片段)解析 DMG 直链。
  Future<UpdateInfo> _checkViaWebPage() async {
    final url = 'https://github.com/$kGitHubRepo/releases/latest';
    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw HttpException('检查更新失败 (HTTP ${resp.statusCode})');
    }
    final tagRe = RegExp('releases/tag/(v[0-9][^"\\s]*)');
    final tagMatch = tagRe.firstMatch(resp.body);
    if (tagMatch == null) throw HttpException('无法解析最新版本号');
    final tag = tagMatch.group(1)!;
    final latest = tag.startsWith('v') ? tag.substring(1) : tag;

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
      releaseUrl: url,
    );
  }

  /// 下载 DMG 到临时文件,返回本地路径。
  /// [onProgress] 回调下载进度(0.0 ~ 1.0)。
  /// [expectedSha256] 若提供,下载后校验文件 SHA256;不匹配则删除文件并抛异常。
  Future<File> download(
    String url, {
    void Function(double)? onProgress,
    String? expectedSha256,
  }) async {
    // 安卓必须落在应用私有目录(cache),否则 FileProvider 无法把 APK 交给
    // 系统安装器;桌面沿用系统临时目录。
    final dir = _downloadDirOverride ??
        (Platform.isAndroid
            ? await getTemporaryDirectory()
            : Directory.systemTemp);
    final file = File(
      '${dir.path}/${updateDownloadFileNameFor(isAndroid: Platform.isAndroid)}',
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

    final req = http.Request('GET', Uri.parse(url));
    // GitHub 下载需要 UA,否则部分 CDN 拒绝
    req.headers['User-Agent'] = 'MusicX/${currentVersion()}';
    final resp = await _client.send(req).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      await resp.stream.drain<void>();
      throw HttpException('下载失败 (HTTP ${resp.statusCode})\n请检查网络后重试');
    }
    final total = resp.contentLength;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    // ① 完整性:声明了 Content-Length 就必须下满,否则是断流(此前只用于进度,
    //    截断的包会被交给系统并报出难以理解的错误)。
    if (total != null && total > 0 && received != total) {
      try {
        file.deleteSync();
      } catch (_) {}
      throw HttpException(
        '下载不完整($received/$total 字节),已作废,请重新下载',
      );
    }
    // ② 格式:APK 是 ZIP,必须以 PK 魔数开头;HTML 错误页/坏文件在这里就拦下。
    try {
      final head = await file.openRead(0, 4).fold<List<int>>(
        <int>[],
        (a, b) => a..addAll(b),
      );
      final isZip = head.length >= 2 && head[0] == 0x50 && head[1] == 0x4B;
      if (!isZip) {
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
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final actual = await _sha256Of(file);
      if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
        try {
          file.deleteSync();
        } catch (_) {}
        throw HttpException(
          '更新包完整性校验失败(SHA256 不匹配),已拒绝安装。\n'
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
    })
  >
  verifyPackageForInstall({
    required String path,
    required String expectedVersion,
  }) async {
    final apkCode = await ApkInstaller.versionCodeOf(path);
    final apkName = await ApkInstaller.versionNameOf(path);
    final apkPkg = await ApkInstaller.packageNameOf(path);
    final installedCode = await ApkInstaller.versionCode();
    final decision = decideInstall(
      apkVersionCode: apkCode,
      apkVersionName: apkName,
      installedVersionCode: installedCode,
      expectedVersion: expectedVersion,
      apkPackageName: apkPkg,
      expectedPackageName: ApkInstaller.androidPackageName,
    );
    debugPrint(
      'MusicX 更新校验: 安装包=$apkPkg v${apkName ?? "?"}($apkCode) '
      '已装=$installedCode 目标=v$expectedVersion → ${decision.name}',
    );
    return (
      decision: decision,
      apkCode: apkCode,
      apkVersion: apkName,
      apkPackageName: apkPkg,
      installedVersion: installedCode,
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
      //   ① 必须能读出安装包与已装应用的版本号(fail-closed,读不到就不装);
      //   ② 安装包的 versionName 必须等于本次要更新的目标版本;
      //   ③ 安装包 versionCode 必须严格大于已装版本。
      // 任一不满足都给出可读原因,绝不再把含糊的「已安装相同版本」留给系统提示。
      final result = await verifyPackageForInstall(
        path: package.path,
        expectedVersion: version ?? '',
      );
      switch (result.decision) {
        case InstallDecision.install:
          break;
        case InstallDecision.alreadyLatest:
          UpdateService.invalidateVersionCache();
          throw HttpException(
            '当前已是最新版本 v${result.installedVersion}(安装包 '
            'v${result.apkVersion}),无需重复安装',
          );
        case InstallDecision.mismatchRetry:
          unawaited(package.delete().catchError((_) => package));
          throw HttpException(
            '下载到的安装包是 v${result.apkVersion},与目标版本 v$version 不一致,'
            '已作废,请重新点击更新',
          );
        case InstallDecision.invalid:
          throw HttpException(
            '安装包校验失败(无法读取版本信息,可能下载不完整),请重新下载',
          );
      }
      final ok = await ApkInstaller.installApk(package.path);
      if (!ok) {
        throw HttpException('未能调起系统安装器,请到「设置 → 应用 → 未知来源」授权后重试');
      }
      return;
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
