// test/ui/bundled_sources_hidden_test.dart
//
// 用户诉求:随 App 内置的音源(腾讯/网易/酷我)装好后不要在音源列表里出现,
// 只显示「内置音源:已安装」状态;列表只列用户自己装的音源。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';

const _userPlugin = '''
module.exports = { platform: "我的音源", version: "1.0.0",
  search: function () { return Promise.resolve({ isEnd: true, data: [] }); }
};
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory srcDir;
  late PluginManager manager;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('musicx_bundled_hidden');
    // 源文件放在插件目录之外,否则会被 listPlugins 当成另一个插件扫描到
    srcDir = Directory.systemTemp.createTempSync('musicx_bundled_hidden_src');
    manager = PluginManager(tmp);
    // 安装全部内置音源 + 一个用户自己装的音源
    final catalog = BundledPluginCatalog();
    for (final p in await catalog.list()) {
      await manager.installBundledJs(
        await catalog.readJs(p),
        source: 'bundled:${p.assetPath}',
      );
    }
    await manager.installFromFile(
      (File('${srcDir.path}/my_plugin.js')..writeAsStringSync(_userPlugin)).path,
    );
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
    srcDir.deleteSync(recursive: true);
  });

  testWidgets('内置音源不出现在列表里,只显示已安装状态;用户音源照常显示', (tester) async {
    // 页面首帧要真实文件 I/O(listPlugins 扫描插件目录),pumpAndSettle 在
    // 假时钟下不会推进 → 必须 runAsync(与 layout_audit 同思路)
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [pluginManagerProvider.overrideWithValue(manager)],
          child: const MaterialApp(home: PluginPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 内置音源名不出现
    for (final name in ['腾讯音乐', '网yi', '酷我(念心音源)']) {
      expect(find.text(name), findsNothing, reason: '内置音源「$name」不应出现在列表里');
    }
    // 只有状态行
    expect(find.text('内置音源'), findsOneWidget);
    expect(find.text('已安装 3'), findsOneWidget);

    // 已安装音源计数只统计用户音源(内置 3 个不计入)
    expect(find.text('1'), findsOneWidget, reason: '计数应只算用户音源');

    // 说明:二级页(已安装音源/默认音源选择器)共用同一份过滤后的列表
    // (userPlugins),其内容由 pluginListProvider 异步提供,故此处不导航断言。
  });
}
