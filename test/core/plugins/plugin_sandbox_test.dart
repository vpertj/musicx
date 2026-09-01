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
      () => sandbox.isolate(() async {
        await Future.delayed(const Duration(seconds: 5));
        return 'too late';
      }, timeout: const Duration(milliseconds: 100)),
      throwsA(isA<PluginIsolateTimeoutException>()),
    );
  });

  group('callPlugin (Isolate.spawn + kill)', () {
    const demoPlugin = '''
module.exports = {
  platform: "demo", version: "0.1.0",
  search: function (q) {
    return new Promise(function (resolve) {
      setTimeout(function () { resolve({ data: [{ id: "d1", title: "示例歌曲", songId: "d1" }] }); }, 10);
    });
  },
  getMediaSource: function (m) { return { url: "http://ok/" + m.songId }; }
};
''';

    test('callPlugin loads plugin and returns method result', () async {
      final sandbox = PluginSandbox();
      final result = await sandbox.callPlugin(
        demoPlugin,
        'search',
        ['周杰伦', 1, 'music'],
      );
      expect(result['data'], isA<List>());
      expect((result['data'] as List).first['title'], '示例歌曲');
    });

    test('callPlugin getMediaSource returns url', () async {
      final sandbox = PluginSandbox();
      final result = await sandbox.callPlugin(
        demoPlugin,
        'getMediaSource',
        [{'songId': 'd1'}],
      );
      expect(result['url'], 'http://ok/d1');
    });

    test('callPlugin times out and throws (kills isolate)', () async {
      final sandbox = PluginSandbox();
      // 用永不 resolve 的 Promise 模拟死循环/长任务,验证超时后真杀的路径。
      const hangingPlugin = '''
module.exports = {
  platform: "demo", version: "0.1.0",
  search: function () {
    return new Promise(function () { /* 永不 resolve */ });
  }
};
''';
      await expectLater(
        sandbox.callPlugin(
          hangingPlugin,
          'search',
          ['x', 1, 'music'],
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<PluginIsolateTimeoutException>()),
      );
    });
  });
}
