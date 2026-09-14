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
