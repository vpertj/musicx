import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_bridge.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JavascriptRuntime runtime;
  setUp(() {
    runtime = JsRuntimeFactory.create();
    PluginLoader(runtime).loadPlugin(
      'module.exports = { platform: "demo", version: "0.1.0", '
      'getMediaSource: function(item){ return { url: "http://media/" + item.id }; }, '
      'boom: function(){ throw new Error("kaboom"); } };',
    );
  });

  test('callSync invokes plugin function with JSON args', () {
    final bridge = PluginBridge(runtime);
    final result = bridge.callSync('getMediaSource', {'id': 'song1'});
    expect(result['url'], 'http://media/song1');
  });

  test('callSync throws PluginCallException on missing method', () {
    final bridge = PluginBridge(runtime);
    expect(() => bridge.callSync('nope', {}), throwsA(isA<PluginCallException>()));
  });

  test('callSync wraps JS exceptions', () {
    final bridge = PluginBridge(runtime);
    expect(
      () => bridge.callSync('boom', {}),
      throwsA(isA<PluginCallException>().having((e) => e.reason, 'reason', contains('kaboom'))),
    );
  });
}
