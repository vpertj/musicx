// lib/core/plugins/bundled_install.dart
import 'bundled_plugins.dart';
import 'plugin_manager.dart';

/// 一次内置音源安装的结果。
class BundledInstallResult {
  const BundledInstallResult({required this.installed, required this.failed});

  /// 安装成功的条目。
  final List<BundledPlugin> installed;

  /// 安装失败的条目(单个失败不影响其它)。
  final List<BundledPlugin> failed;

  bool get hasFailure => failed.isNotEmpty;
}

/// 批量安装内置音源(读 asset → 落盘)。
///
/// 抽成独立函数便于单测:UI 只负责点击、确认与提示。
Future<BundledInstallResult> installBundledPlugins({
  required PluginManager manager,
  required BundledPluginCatalog catalog,
  required List<BundledPlugin> plugins,
}) async {
  final installed = <BundledPlugin>[];
  final failed = <BundledPlugin>[];
  for (final plugin in plugins) {
    try {
      await manager.installBundledJs(
        await catalog.readJs(plugin),
        source: 'bundled:${plugin.assetPath}',
      );
      installed.add(plugin);
    } catch (_) {
      failed.add(plugin);
    }
  }
  return BundledInstallResult(installed: installed, failed: failed);
}
