import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/search/search_controller.dart'
    show pluginManagerProvider;
import 'package:musicx/ui/plugins/plugin_page.dart';

const _demoPlugin = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function(q){ return Promise.resolve({isEnd:true,data:[{id:"1",title:"测试歌",artist:"歌手",songId:"1"}]}); },
  getMediaSource: function(m){ return Promise.resolve({url:"https://example.com/test.mp3"}); }
};
''';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_pp');
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('PluginPage shows grouped settings sections', (tester) async {
    // listPlugins 涉及真实 File IO,flutter_test 的 FakeAsync zone 无法推进
    // 真实异步(见 search_page_test 同款注释),需在 runAsync 中完成 future。
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
          ],
          child: const MaterialApp(home: PluginPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    // 主设置页采用左右栏分组:左侧菜单 + 右侧内容区
    // 宽屏默认显示「音乐源」区块内容;"音乐源"在菜单与内容标题各出现一次
    expect(find.text('音乐源'), findsWidgets);
    expect(find.text('外观'), findsOneWidget); // 左侧菜单项
    expect(find.text('通用'), findsOneWidget); // 左侧菜单项

    // 音乐源分组内有「已安装音源」入口(点击进二级页)
    expect(find.text('已安装音源'), findsOneWidget);
    expect(find.text('默认音源'), findsOneWidget);

    // 主设置页不再直接列出插件卡片(demo 在二级页)
    expect(find.text('v0.1.0'), findsNothing);
  });

  testWidgets('PluginPage appearance section toggles theme', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
          ],
          child: const MaterialApp(home: PluginPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    // 点击左侧「外观」菜单,右侧显示浅色/深色切换
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
  });
}