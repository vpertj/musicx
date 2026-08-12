import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_bridge_async.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('callAsync resolves Promise result via message channel', () async {
    final runtime = JsRuntimeFactory.create();
    PluginLoader(runtime).loadPlugin(
      'module.exports = { platform: "demo", version: "0.1.0", '
      'search: function(keyword){ return new Promise(function(resolve){ setTimeout(function(){ resolve({ list: [keyword] }); }, 30); }); } };',
    );
    final bridge = PluginBridgeAsync(runtime);
    final result = await bridge.callAsync('search', ['周杰伦']);
    expect(result['list'], ['周杰伦']);
  });
}
