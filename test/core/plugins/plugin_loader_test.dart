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

  test('Parcel/TS 打包产物:解包 exports.default 后仍能拿到 platform', () {
    // MusicFree 生态里相当一部分音源是 Parcel/TS 打包产物,导出形态是
    // `exports.default = pluginInstance`(顶层带 __esModule 标记)。
    // 内置只保留三个源了,但用户自己装的这类插件仍要能跑。
    final runtime = JsRuntimeFactory.create();
    final loader = PluginLoader(runtime);
    final result = loader.loadPlugin('''
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
var plugin = { platform: "打包源", version: "2026.09.21", search: function () { return []; } };
exports.default = plugin;
''');
    expect(result['platform'], '打包源');
    expect(result['version'], '2026.09.21');
    expect(
      (result['functions'] as List).cast<String>(),
      contains('search'),
    );
  });

  test('普通 CommonJS 导出不受解包逻辑影响', () {
    final runtime = JsRuntimeFactory.create();
    final loader = PluginLoader(runtime);
    final result = loader.loadPlugin('''
module.exports = { platform: "普通源", version: "1.0.0",
  default: { platform: "内层", version: "9" }, search: function () { return []; } };
''');
    expect(result['platform'], '普通源',
        reason: '顶层有 platform 时不能把 default 当成真身');
  });
}
