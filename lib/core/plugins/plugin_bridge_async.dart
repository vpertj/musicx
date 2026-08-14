import 'dart:async';
import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'plugin_bridge.dart';

/// 异步插件调用超时(默认 10s)时抛出。
class PluginAsyncTimeoutException implements Exception {
  final String method;
  const PluginAsyncTimeoutException(this.method);

  @override
  String toString() => 'PluginAsyncTimeoutException($method)';
}

/// 一个进行中的异步调用:method 用于构造 PluginCallException,completer 承载结果。
class _PendingAsyncCall {
  final String method;
  final Completer<Map<String, dynamic>> completer;
  _PendingAsyncCall(this.method, this.completer);
}

/// 异步调用通道:插件函数返回 Promise 时,resolve 值经
/// `sendMessage('__musicx_async_result', JSON.stringify({id, value|error}))`
/// 回传 Dart,由 [callAsync] 返回。
class PluginBridgeAsync {
  static const _resultChannel = '__musicx_async_result';

  final JavascriptRuntime runtime;

  /// id -> 待办调用。回调常驻、按 id 匹配,天然支持多次/并发调用。
  final Map<String, _PendingAsyncCall> _pending = {};
  bool _listenerRegistered = false;

  PluginBridgeAsync(this.runtime);

  /// 调用插件函数 [method] 并等待异步结果;超时抛 [PluginAsyncTimeoutException]。
  /// [args] 按 MusicFree 协议以位置参数传给插件函数(如 search(keyword, page, type))。
  Future<Map<String, dynamic>> callAsync(
    String method,
    List<dynamic> args, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = _PendingAsyncCall(method, completer);
    _ensureResultListener();

    try {
      // 遵循 Task 6 教训:参数直接嵌入 JSON 数组字面量,不套 JSON.parse。
      // jsonEncode(method) 生成合法 JS 字符串字面量。
      final js =
          '''
(function(){
  var fn = globalThis.__musicx_export && globalThis.__musicx_export[${jsonEncode(method)}];
  if (typeof fn !== "function") {
    sendMessage('$_resultChannel', JSON.stringify({ id: ${jsonEncode(id)}, error: "method not found" }));
    return;
  }
  try {
    var p = fn.apply(null, ${jsonEncode(args)});
    if (p && typeof p.then === "function") {
      p.then(function(v){
        sendMessage('$_resultChannel', JSON.stringify({ id: ${jsonEncode(id)}, value: v === undefined ? null : v }));
      }, function(e){
        sendMessage('$_resultChannel', JSON.stringify({ id: ${jsonEncode(id)}, error: String(e && e.message || e) }));
      });
    } else {
      sendMessage('$_resultChannel', JSON.stringify({ id: ${jsonEncode(id)}, value: p === undefined ? null : p }));
    }
  } catch (e) {
    sendMessage('$_resultChannel', JSON.stringify({ id: ${jsonEncode(id)}, error: String(e && e.message || e) }));
  }
})()
''';
      final result = runtime.evaluate(js);
      if (result.isError) {
        // evaluate 本身报错(语法/运行时错误),而不是通道回传的 {error}。
        completer.completeError(
          PluginCallException(method, result.stringResult),
        );
      }
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw PluginAsyncTimeoutException(method),
      );
    } finally {
      // 无论成功、JS 报错还是超时,都移除待办;迟到消息会被回调丢弃。
      _pending.remove(id);
    }
  }

  /// flutter_js 0.8.7 的 onMessage 返回 void;JavascriptCoreRuntime.setupBridge
  /// 对同一 channel 只接受首次注册(重复注册返回 false 且不覆盖)。
  /// 因此这里只注册一次常驻回调,靠 [_pending] 按 id 分发结果。
  void _ensureResultListener() {
    if (_listenerRegistered) return;
    runtime.onMessage(_resultChannel, _handleResultMessage);
    _listenerRegistered = true;
  }

  void _handleResultMessage(dynamic payload) {
    final Map<String, dynamic> data;
    final String? id;
    if (payload is Map) {
      // JavascriptCore/QuickJs 都把 JS 侧 message 参数 jsonDecode 后传给回调:
      // sendMessage(channel, JSON.stringify({id, value})) → payload 为 Map。
      data = Map<String, dynamic>.from(payload);
      id = data['id'] as String?;
    } else if (payload is List && payload.length >= 2) {
      // 兼容部分引擎把 [channel, message] 数组原样传给回调。
      id = payload[0] as String?;
      final message = payload[1];
      if (message is! String) return;
      data = jsonDecode(message) as Map<String, dynamic>;
    } else {
      return;
    }
    if (id == null) return;
    final call = _pending.remove(id);
    if (call == null) return; // 已超时/已清理,丢弃迟到消息。
    if (data.containsKey('error')) {
      call.completer.completeError(
        PluginCallException(call.method, data['error'] as String),
      );
    } else {
      final value = data['value'];
      if (value is Map<String, dynamic>) {
        call.completer.complete(value);
      } else {
        call.completer.completeError(
          PluginCallException(call.method, 'plugin returned non-object value'),
        );
      }
    }
  }
}
