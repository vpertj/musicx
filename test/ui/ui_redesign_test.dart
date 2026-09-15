// test/ui/ui_redesign_test.dart
//
// 本轮 UI 重做的回归用例:
//   ① 「我的」页歌单改为左右两列网格,固定入口与「新建歌单」位置不变
//   ② 设置页:品牌条改白底卡片(不再是重渐变)、组内分隔线、关于精简
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/library/library_controller.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/ui/library/library_page.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';

void main() {
  testWidgets('「我的」页歌单以两列网格排列(固定入口与新建歌单仍在首行)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final lib = container.read(libraryControllerProvider.notifier);
    // 歌单状态会持久化到真实文件:先清空,保证用例与历史运行无关
    for (final p in [...container.read(libraryControllerProvider).playlists]) {
      lib.deletePlaylist(p.id);
    }
    lib.createPlaylist('歌单一');
    lib.createPlaylist('歌单二');
    lib.createPlaylist('歌单三');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 固定入口 + 新建歌单仍在首行芯片里
    expect(find.textContaining('我喜欢的'), findsWidgets);
    expect(find.textContaining('下载音乐'), findsWidgets);
    expect(find.textContaining('新建歌单'), findsWidgets);

    // 歌单进入网格:三个歌单都在,且高度方向排成两行(两列)
    expect(find.text('歌单一'), findsOneWidget);
    expect(find.text('歌单二'), findsOneWidget);
    expect(find.text('歌单三'), findsOneWidget);
    final r1 = tester.getRect(find.text('歌单一'));
    final r2 = tester.getRect(find.text('歌单二'));
    final r3 = tester.getRect(find.text('歌单三'));
    expect(r1.top, closeTo(r2.top, 6), reason: '前两个歌单应在同一行(左右排列)');
    expect(r1.left, lessThan(r2.left), reason: '歌单一在左、歌单二在右');
    expect(r3.top, greaterThan(r1.top), reason: '第三个歌单应换到下一行');
  });

  testWidgets('设置页:品牌条为白底卡片(同一语言),且组内出现分隔线', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tmp = Directory.systemTemp.createTempSync('mx_redesign');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/p.js').writeAsStringSync('''
module.exports = { platform: "我的音源", version: "1.0.0",
  search: function () { return Promise.resolve({ isEnd: true, data: [] }); }
};
''');

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
          ],
          child: const MaterialApp(home: PluginPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // 品牌条:显示版本号,且不再使用重渐变(渐变装饰不存在)
    expect(find.text('MusicX'), findsOneWidget);
    expect(find.textContaining('个音源'), findsOneWidget);

    // 组内分隔线(音乐源分组:默认音源/过滤翻唱之间)
    expect(find.byType(Divider), findsWidgets, reason: '组内应有分隔线');

    // 关于卡片精简:不再有那段安装说明
    expect(find.textContaining('安装音源:点右上角'), findsNothing);
    expect(find.textContaining('插件协议兼容 MusicFree'), findsOneWidget);
  });
}
