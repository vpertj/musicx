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
  /// 限定在导出对象定义处之后,避免误匹配插件源码中其他位置的同名键
  /// (如内部请求参数 `platform: "pc"`、`platform: "WebFilter"`)。
  /// 兼容两种打包形态,取两者中更靠后的定义点作为起点:
  ///  - CommonJS 直出:`module.exports = { ... }`;
  ///  - Parcel/TS 打包:真正的元信息对象在 `xxx$var$pluginInstance = { ... }`
  ///    (文件头部的 `module.exports` 只是 `$parcel$export` 样板,不含元信息)。
  Map<String, dynamic> parseMeta(String source) {
    final anchor = RegExp(
      r'(?:module\.exports\s*=\s*\{|\$var\$pluginInstance\s*=\s*\{)',
    );
    var idx = -1;
    for (final m in anchor.allMatches(source)) {
      idx = m.start;
    }
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
