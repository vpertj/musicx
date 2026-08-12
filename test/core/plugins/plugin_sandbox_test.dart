import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_bridge.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';
import 'package:musicx/core/plugins/plugin_sandbox.dart';

void main() {
  test('runs plugin call inside isolate and returns value', () async {
    final sandbox = PluginSandbox();
    final value = await sandbox.isolate(() async {
      // 注:isolate 内不能加载 flutter asset(enableFetch 依赖主 isolate 的
      // ServicesBinding),故用 xhr:false 创建同一种 JavascriptCoreRuntime。
      // 播放地址获取只需同步 callSync,不需要 fetch polyfill。
      final runtime = getJavascriptRuntime(xhr: false);
      PluginLoader(runtime).loadPlugin(
        'module.exports = { platform: "demo", version: "0.1.0", '
        'getMediaSource: function(){ return { url: "http://ok" }; } };',
      );
      return PluginBridge(runtime).callSync('getMediaSource', [{}]);
    });
    expect(value['url'], 'http://ok');
  });

  test('isolate kills work that exceeds timeout and throws', () async {
    final sandbox = PluginSandbox();
    expect(
      () => sandbox.isolate(
        () async {
          await Future.delayed(const Duration(seconds: 5));
          return 'too late';
        },
        timeout: const Duration(milliseconds: 100),
      ),
      throwsA(isA<PluginIsolateTimeoutException>()),
    );
  });
}
