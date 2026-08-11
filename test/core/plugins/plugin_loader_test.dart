import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('loadPlugin wraps CommonJS and exposes metadata', () {
    final runtime = JsRuntimeFactory.create();
    final loader = PluginLoader(runtime);
    final result = loader.loadPlugin(
      'module.exports = { platform: "demo", version: "0.1.0", srcUrl: "http://x", search: function(){ return []; } };',
    );
    expect(result['platform'], 'demo');
    expect(result['version'], '0.1.0');
    final funcs = (result['functions'] as List).cast<String>();
    expect(funcs, contains('search'));
    expect(funcs, isNot(contains('platform')));
  });

  test('loadPlugin surfaces JS syntax errors as PluginLoadException', () {
    final runtime = JsRuntimeFactory.create();
    final loader = PluginLoader(runtime);
    expect(
      () => loader.loadPlugin(
        'module.exports = { platform: "demo", version: "0.1.0", @ };',
      ),
      throwsA(
        isA<PluginLoadException>().having(
          (e) => e.details,
          'details',
          contains('ERROR:'),
        ),
      ),
    );
  });

  test('loadPlugin surfaces require() not supported at load time', () {
    final runtime = JsRuntimeFactory.create();
    final loader = PluginLoader(runtime);
    expect(
      () => loader.loadPlugin(
        'require("fs"); module.exports = { platform: "demo", version: "0.1.0" };',
      ),
      throwsA(
        isA<PluginLoadException>().having(
          (e) => e.details,
          'details',
          contains('require() not supported'),
        ),
      ),
    );
  });
}
