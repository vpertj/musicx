import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_bridge.dart';
import 'package:musicx/core/plugins/plugin_bridge_async.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';
import 'package:musicx/core/plugins/plugin_sandbox.dart';

void main() {
  test('e2e: load demo plugin, search, then resolve media source', () async {
    final sandbox = PluginSandbox();
    final result = await sandbox.isolate(() async {
      // 注:isolate 内不能用 JsRuntimeFactory.create()(默认 xhr:true 会
      // enableFetch → rootBundle.loadString 依赖主 isolate 的 ServicesBinding)。
      // 必须用 xhr:false 创建同一种 JavascriptCoreRuntime。
      // 另注:flutter_test 的 expect 依赖测试 Zone,isolate 内不可用,
      // 因此所有断言放回主 isolate 执行。
      final runtime = getJavascriptRuntime(xhr: false);
      final loader = PluginLoader(runtime);
      final meta = loader.loadPlugin('''
module.exports = { platform: "demo-source", version: "0.1.0", srcUrl: "",
  search: function (query) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({ isEnd: true, data: [ { id: "d1", title: "示例歌曲", artist: "演示歌手",
          album: "演示专辑", artwork: "", duration: 180000, platform: "demo-source", songId: "d1", extra: {} } ] });
      }, 20);
    });
  },
  getMediaSource: function (musicItem) { return { url: "https://example.com/audio/" + musicItem.songId + ".mp3" }; }
};
''');

      // search 返回 Promise → 走异步通道 callAsync。
      final asyncBridge = PluginBridgeAsync(runtime);
      final searchResult =
          await asyncBridge.callAsync('search', {'keyword': '示例'});
      final first = (searchResult['data'] as List).first as Map<String, dynamic>;

      // getMediaSource 同步返回 → 走同步通道 callSync。
      final bridge = PluginBridge(runtime);
      final media = bridge.callSync('getMediaSource', first);
      return {
        'platform': meta['platform'],
        'title': first['title'],
        'url': media['url'],
      };
    });

    expect(result['platform'], 'demo-source');
    expect(result['title'], '示例歌曲');
    expect(result['url'], 'https://example.com/audio/d1.mp3');
  });
}
