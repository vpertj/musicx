import 'package:flutter_js/flutter_js.dart';

/// 创建 JavascriptRuntime 的封装,便于测试替换。
class JsRuntimeFactory {
  static JavascriptRuntime create() => getJavascriptRuntime();
}
