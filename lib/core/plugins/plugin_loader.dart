import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'js_runtime_factory.dart';

export 'js_runtime_factory.dart';

/// 插件加载失败时抛出,携带 JS 运行时的原始错误信息。
class PluginLoadException implements Exception {
  final String message;
  final String? details;

  const PluginLoadException(this.message, {this.details});

  @override
  String toString() => details == null
      ? 'PluginLoadException: $message'
      : 'PluginLoadException: $message\n$details';
}

/// 把 CommonJS 插件源码包进 IIFE,提供 module/exports/require,
/// 并把导出挂到 globalThis.__musicx_export 供 Bridge 调用。
/// require 使用 JsRuntimeFactory 注入的白名单注册表(__musicx_require),
/// 以兼容 MusicFree 官方插件的运行时依赖(axios 等)。
String cjsShim(String source) =>
    '''
var __musicx_module = { exports: {} };
(function (module, exports, require) {
$source
})(__musicx_module, __musicx_module.exports, typeof __musicx_require === "function" ? __musicx_require : function (name) {
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
    final loadResult = runtime.evaluate(cjsShim(source));
    if (loadResult.isError) {
      throw PluginLoadException(
        'Plugin failed to load',
        details: loadResult.stringResult,
      );
    }
    final metaRaw = runtime.evaluate(
      'JSON.stringify({ meta: (globalThis.__musicx_export.platform !== undefined && globalThis.__musicx_export.version !== undefined) ? { platform: globalThis.__musicx_export.platform, version: globalThis.__musicx_export.version, srcUrl: globalThis.__musicx_export.srcUrl || null } : null, functions: Object.keys(globalThis.__musicx_export).filter(function(k){ return typeof globalThis.__musicx_export[k] === "function"; }) })',
    );
    if (metaRaw.isError) {
      throw PluginLoadException(
        'Failed to inspect plugin exports',
        details: metaRaw.stringResult,
      );
    }
    final decoded = jsonDecode(metaRaw.stringResult) as Map<String, dynamic>;
    final meta = decoded['meta'] as Map<String, dynamic>?;
    if (meta == null) {
      throw ArgumentError('Plugin does not export required platform/version');
    }
    return {...meta, 'functions': decoded['functions']};
  }
}
