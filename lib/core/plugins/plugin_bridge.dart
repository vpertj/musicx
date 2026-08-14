import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';

class PluginCallException implements Exception {
  final String method;
  final String reason;
  const PluginCallException(this.method, this.reason);
  @override
  String toString() => 'PluginCallException($method): $reason';
}

class PluginBridge {
  final JavascriptRuntime runtime;
  PluginBridge(this.runtime);

  /// 同步调用插件函数 [method]。[args] 按 MusicFree 协议以位置参数传给插件函数。
  Map<String, dynamic> callSync(String method, List<dynamic> args) {
    // jsonEncode(method) 生成合法的 JS 字符串字面量(含引号与转义),
    // argsJson 同理 —— JSON 数组字面量本身就是合法 JS 表达式,
    // 两者直接嵌入 JS 源码,不需要额外拼接。
    final methodKey = jsonEncode(method);
    final argsJson = jsonEncode(args);
    final js =
        '''
(function(){
  var fn = globalThis.__musicx_export && globalThis.__musicx_export[$methodKey];
  if (typeof fn !== "function") { return JSON.stringify({ error: "method not found: " + $methodKey }); }
  try {
    var out = fn.apply(null, $argsJson);
    return JSON.stringify({ value: out === undefined ? null : out });
  } catch (e) {
    return JSON.stringify({ error: String(e && e.message || e) });
  }
})()
''';
    final result = runtime.evaluate(js);
    if (result.isError) {
      // evaluate 本身报错(语法错误、运行时异常等),而不是返回 {error}。
      throw PluginCallException(method, result.stringResult);
    }
    final raw = result.stringResult;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded.containsKey('error')) {
      throw PluginCallException(method, decoded['error'] as String);
    }
    final value = decoded['value'];
    if (value is! Map<String, dynamic>) {
      throw PluginCallException(method, 'plugin returned non-object value');
    }
    return value;
  }
}
