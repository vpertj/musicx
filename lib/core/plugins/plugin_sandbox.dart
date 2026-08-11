import 'dart:async';
import 'dart:isolate';

class PluginIsolateTimeoutException implements Exception {
  final Duration timeout;
  const PluginIsolateTimeoutException(this.timeout);
}

class PluginSandbox {
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
