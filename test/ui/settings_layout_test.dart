// test/ui/settings_layout_test.dart
//
// 设置页布局重构(用户诉求:看着乱)的确定性验证:
//   ① 桌面歌词不再内联(预览+滑块),列表里只留一行摘要,点进二级页
//   ② 顶部品牌卡瘦身成矮条(版本号 + N 个音源)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_glass.dart';
import 'package:musicx/ui/plugins/lyrics_settings_page.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';

const _plugin = '''
module.exports = { platform: "我的音源", version: "1.0.0",
  search: function () { return Promise.resolve({ isEnd: true, data: [] }); }
};
''';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mx_settings_layout');
    File('${tmp.path}/p.js').writeAsStringSync(_plugin);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('桌面歌词收敛为一行摘要,内容进二级页', (tester) async {
    await pump(tester);

    // 列表里只有一行入口(带摘要:样式 · 字号)
    expect(find.text('桌面歌词'), findsOneWidget);
    expect(find.textContaining('px'), findsWidgets, reason: '摘要应含字号');

    // 内联的歌词预览/滑块不应再出现(它们是二级页的内容)
    expect(find.byType(LyricsGlassCard), findsNothing);
    expect(find.text('玻璃浓度'), findsNothing, reason: '玻璃参数不再内联在设置页');

    // 点进二级页
    await tester.tap(find.text('桌面歌词'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricsSettingsPage), findsOneWidget);
  });

  testWidgets('顶部品牌卡瘦身:显示版本号与音源数,高度明显变小', (tester) async {
    await pump(tester);
    expect(find.text('MusicX'), findsOneWidget);
    expect(find.textContaining('个音源'), findsOneWidget);
    expect(find.text('插件化音乐播放器 · 轻量免费'), findsNothing,
        reason: '大卡副标题已移除(瘦身)');
  });
}
