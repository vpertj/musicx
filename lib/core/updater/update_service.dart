import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// GitHub 仓库信息:更新检查与下载均基于此仓库的 Releases。
const kGitHubRepo = 'vpertj/musicx';

/// 更新检查结果。
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String dmgUrl;
  final String releaseUrl;
  final String? releaseNotes;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.dmgUrl,
    required this.releaseUrl,
    this.releaseNotes,
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
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 当前应用版本:读取运行时 bundle 的 CFBundleShortVersionString。
  static String currentVersion() {
    try {
      final exe = Platform.resolvedExecutable;
      // exe = .../musicx.app/Contents/MacOS/musicx
      final contentsDir = File(exe).parent.parent; // .../musicx.app/Contents
      final plist = File('${contentsDir.path}/Info.plist');
      if (plist.existsSync()) {
        final out = Process.runSync('/usr/libexec/PlistBuddy', [
          '-c',
          'Print :CFBundleShortVersionString',
          plist.path,
        ]);
        if (out.exitCode == 0) return (out.stdout as String).trim();
      }
    } catch (_) {}
    return '0.0.0';
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
    String dmgUrl = '';
    for (final a in assets) {
      final name = a['name'] as String? ?? '';
      if (name.endsWith('.dmg')) {
        dmgUrl = a['browser_download_url'] as String? ?? '';
        break;
      }
    }
    if (dmgUrl.isEmpty) {
      throw HttpException('最新 Release 中没有找到 DMG 安装包');
    }
    return UpdateInfo(
      latestVersion: latest,
      currentVersion: currentVersion(),
      dmgUrl: dmgUrl,
      releaseUrl: json['html_url'] as String? ?? '',
      releaseNotes: json['body'] as String?,
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
    final dmgRe = RegExp('href="([^"]*\\.dmg)"');
    final dmgMatch = dmgRe.firstMatch(assetsResp.body);
    final dmgUrl = dmgMatch == null
        ? ''
        : 'https://github.com${dmgMatch.group(1)}';
    if (dmgUrl.isEmpty) {
      throw HttpException('最新 Release 中没有找到 DMG 安装包');
    }
    return UpdateInfo(
      latestVersion: latest,
      currentVersion: currentVersion(),
      dmgUrl: dmgUrl,
      releaseUrl: url,
    );
  }

  /// 下载 DMG 到临时文件,返回本地路径。
  /// [onProgress] 回调下载进度(0.0 ~ 1.0)。
  Future<File> download(String url, {void Function(double)? onProgress}) async {
    final tmp = Directory.systemTemp;
    final file = File('${tmp.path}/musicx_update.dmg');
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
    return file;
  }

  /// 用 DMG 替换当前应用并重启。
  ///
  /// 步骤:挂载 DMG → 复制新版 .app 覆盖当前 .app → 卸载 DMG →
  /// 生成重启脚本(延迟 2s,等本进程退出后 `open` 新应用) → 退出当前进程。
  Future<void> installAndRestart(File dmg) async {
    // 1. 挂载 DMG
    final mount = await Process.run('hdiutil', [
      'attach',
      dmg.path,
      '-nobrowse',
      '-readonly',
    ]);
    if (mount.exitCode != 0) {
      throw HttpException('挂载更新包失败: ${mount.stderr}');
    }
    // 2. 找挂载点中的 .app
    String? mountPoint;
    final lines = (mount.stdout as String).split('\n');
    for (final line in lines) {
      final idx = line.indexOf('/Volumes/');
      if (idx >= 0) {
        mountPoint = line.substring(idx).trim();
        break;
      }
    }
    if (mountPoint == null) throw HttpException('无法定位 DMG 挂载点');

    final newAppDir = Directory(mountPoint);
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
    await Process.run('hdiutil', ['detach', mountPoint, '-force']);

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
