import 'dart:io';
import 'package:musicx/core/plugins/plugin_bridge.dart';
import 'package:musicx/core/plugins/plugin_bridge_async.dart';
import 'package:musicx/core/plugins/plugin_info.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';
import 'package:musicx/core/plugins/plugin_sandbox.dart';
import 'package:musicx/core/plugins/plugin_store.dart';
import 'package:flutter_js/flutter_js.dart';

class PluginManager {
  final Directory rootDir;
  final PluginStore _store;
  final PluginSandbox _sandbox;
  PluginManager(this.rootDir)
      : _store = PluginStore(rootDir),
        _sandbox = PluginSandbox();

  Future<List<PluginInfo>> listPlugins() async {
    final files = _store.scanPluginFiles();
    final result = <PluginInfo>[];
    for (final f in files) {
      try {
        result.add(await _store.loadMeta(f));
      } catch (_) {
        // 跳过元数据损坏的插件文件
      }
    }
    return result;
  }

  Future<void> installFromFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('plugin source not found', path);
    }
    if (!rootDir.existsSync()) {
      rootDir.createSync(recursive: true);
    }
    final name = 'plugin_${DateTime.now().microsecondsSinceEpoch}.js';
    await file.copy('${rootDir.path}/$name');
  }

  Future<void> uninstall(PluginInfo info) async {
    final file = File(info.path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// 遍历所有插件,对每个插件在 isolate 内加载并执行 search;
  /// 返回第一个成功的结果,其余插件失败仅记录忽略。
  Future<Map<String, dynamic>> search(
    String keyword, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final plugins = await listPlugins();
    for (final plugin in plugins) {
      try {
        final source = await File(plugin.path).readAsString();
        final result = await _sandbox.isolate(
          () async {
            final runtime = getJavascriptRuntime(xhr: false);
            final loader = PluginLoader(runtime);
            loader.loadPlugin(source);
            final bridge = PluginBridgeAsync(runtime);
            return bridge.callAsync('search', {'keyword': keyword, 'page': 1});
          },
          timeout: timeout,
        );
        return result;
      } catch (e) {
        // 单插件失败不阻断整体;循环继续
      }
    }
    throw Exception('no plugin returned search results');
  }
}
