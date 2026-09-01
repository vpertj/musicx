import 'dart:async';
import 'dart:isolate';

import 'package:musicx/core/plugins/plugin_bridge_async.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';

class PluginIsolateTimeoutException implements Exception {
  final Duration timeout;
  const PluginIsolateTimeoutException(this.timeout);
  @override
  String toString() => 'PluginIsolateTimeoutException($timeout)';
}

/// 顶层 worker 入口:在隔离 isolate 中加载插件并调用方法,结果经 SendPort 回传。
///
/// [payload] 为 [source, method, args, SendPort] 的可序列化列表。
/// 每个调用使用独立的 [JsRuntimeFactory.createIsolateSafe]() runtime,
/// 与宿主隔离,超时后由宿主 `Isolate.kill` 回收(无需显式释放 runtime)。
void _pluginWorker(List<dynamic> payload) {
  final SendPort port = payload[3] as SendPort;
  final String source = payload[0] as String;
  final String method = payload[1] as String;
  final List<dynamic> args = payload[2] as List<dynamic>;
  try {
    final runtime = JsRuntimeFactory.createIsolateSafe();
    final loader = PluginLoader(runtime);
    loader.loadPlugin(source);
    final bridge = PluginBridgeAsync(runtime);
    // 统一走异步桥(Promise);同步返回值经 Promise 包装后同样 resolve。
    bridge.callAsync(method, args).then((r) {
      port.send(['ok', r]);
    }).catchError((e) {
      port.send(['err', e.toString()]);
    });
  } catch (e) {
    port.send(['err', e.toString()]);
  }
}

class PluginSandbox {
  /// 在可 kill 的隔离 isolate 中加载 [source] 插件并调用 [method]。
  ///
  /// 超时后真的 [Isolate.kill] 后台 isolate(死循环也退出),避免泄漏。
  /// 每次调用起一个独立 isolate,结果经 SendPort 回传。
  Future<Map<String, dynamic>> callPlugin(
    String source,
    String method,
    List<dynamic> args, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final resultPort = ReceivePort();
    late Isolate worker;
    try {
      worker = await Isolate.spawn(
        _pluginWorker,
        [source, method, args, resultPort.sendPort],
      );
    } catch (_) {
      resultPort.close();
      rethrow;
    }

    final completer = Completer<Map<String, dynamic>>();
    resultPort.listen((msg) {
      if (msg is! List || msg.isEmpty) return;
      if (msg[0] == 'ok') {
        completer.complete(
          (msg[1] as Map).cast<String, dynamic>(),
        );
      } else {
        completer.completeError(
          StateError('plugin $method failed: ${msg[1]}'),
        );
      }
    });

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          // 真杀后台 isolate,避免死循环/长任务泄漏。
          worker.kill(priority: Isolate.immediate);
          throw PluginIsolateTimeoutException(timeout);
        },
      );
    } finally {
      resultPort.close();
    }
  }

  /// 在隔离 isolate 中运行任意任务。
  ///
  /// 注意:[Isolate.run] 不暴露底层 isolate,超时后无法 kill 后台任务;
  /// 仅供无法数据化的通用任务使用。插件调用请使用 [callPlugin]。
  Future<T> isolate<T>(
    Future<T> Function() fn, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final result = await Isolate.run(fn).timeout(
      timeout,
      onTimeout: () => throw PluginIsolateTimeoutException(timeout),
    );
    return result;
  }
}
