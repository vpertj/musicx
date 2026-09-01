import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/plugins/plugin_info.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

/// 插件管理器(根目录为稳定的用户数据目录)。
final pluginManagerProvider = Provider<PluginManager>((ref) {
  final dir = PluginManager.pluginsDir();
  return PluginManager(dir);
});

/// 已安装插件列表(缓存):插件安装/卸载/更新后调用
/// `ref.invalidate(pluginListProvider)` 刷新,避免每次 build 都重新扫描磁盘。
final pluginListProvider = FutureProvider<List<PluginInfo>>((ref) {
  return ref.watch(pluginManagerProvider).listPlugins();
});
