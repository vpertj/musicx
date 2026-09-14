// test/core/plugins/bundled_install_test.dart
//
// 「下载音源」的服务层:读真实 asset → 落盘 → 可被 listPlugins 扫到。
// UI 只做点击与提示,这里保证按钮背后的行为正确且可重复。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/bundled_install.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late PluginManager manager;
  late BundledPluginCatalog catalog;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_bundled_install');
    manager = PluginManager(tmp);
    catalog = BundledPluginCatalog();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('内置清单包含用户现有的 4 个音源', () async {
    final bundled = await catalog.list();
    expect(
      bundled.map((p) => p.platform).toSet(),
      {'腾讯音乐', '网yi', '酷我(念心音源)'},
      reason: '酷我(独家音源) 上游仍为 v4、其 API 已拒绝,不再内置',
    );
  });

  test('一键安装把一个不落全部装好', () async {
    final bundled = await catalog.list();
    final pending = pendingBundledPlugins(
      bundled: bundled,
      installedVersions: const {},
    );
    expect(pending, hasLength(bundled.length));

    final result = await installBundledPlugins(
      manager: manager,
      catalog: catalog,
      plugins: pending,
    );

    expect(result.failed, isEmpty);
    expect(result.installed, hasLength(bundled.length));
    final installed = await manager.listPlugins();
    expect(
      installed.map((p) => p.platform).toSet(),
      {'腾讯音乐', '网yi', '酷我(念心音源)'},
    );
  });

  test('装完后再算待装集合为空(不会重复安装)', () async {
    final bundled = await catalog.list();
    await installBundledPlugins(
      manager: manager,
      catalog: catalog,
      plugins: bundled,
    );

    final installedVersions = {
      for (final p in await manager.listPlugins()) p.platform: p.version,
    };
    expect(
      pendingBundledPlugins(
        bundled: bundled,
        installedVersions: installedVersions,
      ),
      isEmpty,
    );
    // 文件数 = 插件数,没有重复文件
    expect(tmp.listSync().whereType<File>(), hasLength(bundled.length));
  });
}
