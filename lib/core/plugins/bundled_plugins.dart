import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 内置(随 App 打包)音源条目。
///
/// 这些插件是第三方作品:清单里保留作者与上游地址,UI 上标注来源,
/// 且不改动插件 JS 内原有的作者信息。
class BundledPlugin {
  const BundledPlugin({
    required this.name,
    required this.platform,
    required this.version,
    required this.assetPath,
    this.author = '',
    this.sourceUrl = '',
  });

  /// 展示名,如「网易云音乐」。
  final String name;

  /// 插件元数据里的 platform。
  final String platform;

  /// 随 App 打包的版本。
  final String version;

  /// asset 路径,如 assets/plugins/netease.js。
  final String assetPath;

  /// 插件作者(第三方署名)。
  final String author;

  /// 上游地址(便于用户自行检查更新)。
  final String sourceUrl;
}

/// 内置音源相对已装插件的状态。
enum BundledInstallState { notInstalled, installed, updatable }

/// 解析内置清单(纯函数)。
///
/// 容错:顶层必须是对象;缺 name/platform/asset 的条目跳过;
/// 缺少 version/author/sourceUrl 时按空处理。
List<BundledPlugin> parseBundledPlugins(String jsonText) {
  final dynamic decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('内置音源清单必须是 JSON 对象');
  }
  final raw = decoded['plugins'];
  if (raw is! List) return const [];
  final result = <BundledPlugin>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final name = item['name'];
    final platform = item['platform'];
    final asset = item['asset'];
    if (name is! String || name.isEmpty) continue;
    if (platform is! String || platform.isEmpty) continue;
    if (asset is! String || asset.isEmpty) continue;
    result.add(
      BundledPlugin(
        name: name,
        platform: platform,
        version: item['version'] is String ? item['version'] as String : '',
        assetPath: asset,
        author: item['author'] is String ? item['author'] as String : '',
        sourceUrl: item['sourceUrl'] is String ? item['sourceUrl'] as String : '',
      ),
    );
  }
  return result;
}

/// 版本一致视为已装;不一致提示用户可更新(不判断谁更新,交由用户决定)。
BundledInstallState bundledInstallState({
  required String bundledVersion,
  String? installedVersion,
}) {
  if (installedVersion == null) return BundledInstallState.notInstalled;
  if (installedVersion == bundledVersion) return BundledInstallState.installed;
  return BundledInstallState.updatable;
}

/// 历史上随 App 内置过、后来改名或下线的平台名。
///
/// 升级是覆盖安装,老版本的插件文件会留在插件目录里;而内置源被识别靠的是
/// 平台名,于是这些「历史内置源」会被当成**用户自己装的音源**显示出来
/// (用户反馈:「默认音源怎么那么多,以前不是只有三个还是四个」)。
const Set<String> kLegacyBundledPlatforms = {
  'netease', // a9b70d7 最早内置(平台名就是库名)
  'kuwo', // 同上
  '网易音乐', // 早期内置平台名,与随包 wy.js 同源
  '酷我(独家音源)', // 08e9431 内置;ed5e51c 起下线(官方接口失效)
};

/// 同上,按上游文件名认(老内置源改名后仍能对上随包的那支)。
const Set<String> kLegacyBundledAssetNames = {
  'kuwo_dujia.js',
  '酷我_竹岑.js',
};

/// 判断一个已装音源是否属于「随 App 内置」(含历史遗留的改名/下线版本)。
///
/// 只看当前清单的平台名是不够的:内置源改过名(网易音乐 → 网yi),也下过线
/// (酷我(独家音源)),老文件仍留在设备上。这里三重识别:平台名命中当前清单、
/// 上游文件与随包资源同名(改名但同源)、或命中历史内置名单。
bool isBundledPluginSource({
  required String platform,
  required String srcUrl,
  required Iterable<BundledPlugin> catalog,
}) {
  if (platform.isEmpty) return false;
  final srcName = _urlFileName(srcUrl);
  for (final bundled in catalog) {
    if (bundled.platform == platform) return true;
    if (srcName.isNotEmpty &&
        srcName == bundled.assetPath.split('/').last) {
      return true;
    }
  }
  if (kLegacyBundledPlatforms.contains(platform)) return true;
  return srcName.isNotEmpty && kLegacyBundledAssetNames.contains(srcName);
}

/// 取 URL 最后一段文件名(去 query);非 URL 或为空时返回空串。
String _urlFileName(String url) {
  if (url.isEmpty) return '';
  final noQuery = url.split('?').first.split('#').first;
  final slash = noQuery.lastIndexOf('/');
  return slash < 0 ? noQuery : noQuery.substring(slash + 1);
}

/// 需要安装/更新的内置音源(未安装 + 版本不同);已是最新的跳过。
///
/// 「下载音源」一键安装与面板角标共用同一判定,避免多处条件漂移。
List<BundledPlugin> pendingBundledPlugins({
  required List<BundledPlugin> bundled,
  required Map<String, String> installedVersions,
}) {
  return bundled
      .where(
        (p) =>
            bundledInstallState(
              bundledVersion: p.version,
              installedVersion: installedVersions[p.platform],
            ) !=
            BundledInstallState.installed,
      )
      .toList();
}

/// 内置音源目录:读清单 + 读插件正文。
///
/// asset 读取经构造注入,便于单测(不依赖真实 bundle)。
class BundledPluginCatalog {
  BundledPluginCatalog({Future<String> Function(String key)? loadAsset})
      : _load = loadAsset ?? rootBundle.loadString;

  static const String manifestAsset = 'assets/plugins/bundled.json';

  final Future<String> Function(String key) _load;

  Future<List<BundledPlugin>> list() async {
    try {
      return parseBundledPlugins(await _load(manifestAsset));
    } catch (_) {
      return const [];
    }
  }

  Future<String> readJs(BundledPlugin plugin) => _load(plugin.assetPath);
}
