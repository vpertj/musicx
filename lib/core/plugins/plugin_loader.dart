import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'js_runtime_factory.dart';

export 'js_runtime_factory.dart';

/// 把 CommonJS 插件源码包进 IIFE,提供 module/exports/require,
/// 并把导出挂到 globalThis.__musicx_export 供 Bridge 调用。
String cjsShim(String source) => '''
var __musicx_module = { exports: {} };
(function (module, exports, require) {
$source
})(__musicx_module, __musicx_module.exports, function (name) {
  throw new Error("require() not supported at load time: " + name);
});
globalThis.__musicx_export = __musicx_module.exports;
''';

class PluginLoader {
  final JavascriptRuntime runtime;
  PluginLoader(this.runtime);

  factory PluginLoader.create() => PluginLoader(JsRuntimeFactory.create());

  /// 加载插件,返回 { platform, version, srcUrl?, functions: [...] }。
  Map<String, dynamic> loadPlugin(String source) {
    runtime.evaluate(cjsShim(source));
    final metaRaw = runtime.evaluate(
      'JSON.stringify({ meta: (globalThis.__musicx_export.platform !== undefined && globalThis.__musicx_export.version !== undefined) ? { platform: globalThis.__musicx_export.platform, version: globalThis.__musicx_export.version, srcUrl: globalThis.__musicx_export.srcUrl || null } : null, functions: Object.keys(globalThis.__musicx_export).filter(function(k){ return typeof globalThis.__musicx_export[k] === "function"; }) })',
    );
    final decoded = jsonDecode(metaRaw.stringResult) as Map<String, dynamic>;
    final meta = decoded['meta'] as Map<String, dynamic>?;
    if (meta == null) {
      throw ArgumentError('Plugin does not export required platform/version');
    }
    return {
      ...meta,
      'functions': decoded['functions'],
    };
  }
}
