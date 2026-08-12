import 'dart:io';
import 'package:crypto/crypto.dart';
import 'plugin_info.dart';

class PluginStore {
  final Directory rootDir;
  PluginStore(this.rootDir);

  List<File> scanPluginFiles() {
    if (!rootDir.existsSync()) return [];
    return rootDir
        .listSync(followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'))
        .toList();
  }

  Future<PluginInfo> loadMeta(File file) async {
    final hash = await sha256Of(file);
    final meta = parseMeta(await file.readAsString());
    return PluginInfo.fromJsMeta(meta, hash: hash, path: file.path);
  }

  /// 轻量解析:匹配顶层 `platform`/`version`/`srcUrl` 字符串字面量,
  /// 不执行 JS(元数据解析阶段不加载插件)。
  ///
  /// 限定在最后一个 `module.exports` 之后,避免误匹配插件源码中
  /// 其他位置的同名键(如 bilibili 插件内部 `platform: "pc"` 参数)。
  Map<String, dynamic> parseMeta(String source) {
    final idx = source.lastIndexOf('module.exports');
    final tail = idx >= 0 ? source.substring(idx) : source;
    final re = RegExp("(platform|version|srcUrl)\\s*:\\s*[\"']([^\"']+)[\"']");
    final meta = <String, dynamic>{};
    for (final m in re.allMatches(tail)) {
      meta.putIfAbsent(m.group(1)!, () => m.group(2));
    }
    return meta;
  }

  Future<String> sha256Of(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
