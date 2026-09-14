// test/core/plugins/bundled_install_e2e_test.dart
//
// 端到端:读**真实打包的 asset**(assets/plugins/bundled.json + 插件 JS),
// 走与 UI 按钮相同的安装路径写盘,再用 listPlugins 验证可被扫描到。
// 这条链路覆盖「清单/资源没打进包」这类只在真机构建后暴露的问题。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('musicx_bundled_e2e'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('内置清单与插件正文都能从 asset 读到', () async {
    final bundled = await BundledPluginCatalog().list();
    expect(bundled.map((p) => p.platform), contains('腾讯音乐'));
    for (final p in bundled) {
      final js = await BundledPluginCatalog().readJs(p);
      expect(js, contains('module.exports'), reason: '${p.name} 正文应可读');
    }
  });

  test('逐个安装内置音源后可被 listPlugins 扫到', () async {
    final catalog = BundledPluginCatalog();
    final manager = PluginManager(tmp);
    final bundled = await catalog.list();

    for (final plugin in bundled) {
      await manager.installBundledJs(
        await catalog.readJs(plugin),
        source: 'bundled:${plugin.assetPath}',
      );
    }

    final installed = await manager.listPlugins();
    expect(installed.map((p) => p.platform), contains('腾讯音乐'));
    // 版本与清单一致(用于「已安装 / 可更新」判定)
    for (final plugin in bundled) {
      final hit = installed.firstWhere((p) => p.platform == plugin.platform);
      expect(hit.version, plugin.version, reason: '${plugin.name} 版本应一致');
    }
  });
}
