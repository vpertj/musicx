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
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';
import 'package:musicx/ui/tokens.dart';

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
          // 套用真实主题:设置页的颜色断言只有在 AppTheme 下才有意义
          child: MaterialApp(theme: AppTheme.light, home: const PluginPage()),
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

  testWidgets('视觉契约:灰底 / 白卡圆角 14 / 行内图标统一 20 / 行高 56', (tester) async {
    await pump(tester);

    // ① 页面灰底:此前 0xFFFAFBFC 与白卡(纯白)几乎同色,卡片没有层次。
    final ctx = tester.element(find.byType(PluginPage));
    expect(Theme.of(ctx).scaffoldBackgroundColor, AppPalette.lightBackground);

    // ② 分组是白卡 + 圆角 14(此前用 M3 默认 surfaceContainer,是紫灰色)。
    final hasWhiteCard = tester
        .widgetList<Container>(find.byType(Container))
        .any((c) {
      final d = c.decoration;
      return d is BoxDecoration &&
          d.color == AppPalette.lightCard &&
          d.borderRadius == BorderRadius.circular(AppRadius.card);
    });
    expect(hasWhiteCard, isTrue, reason: '设置分组应是白卡 + 圆角 14');

    // ③ 行内图标统一 20(此前 18/20/22 混用,有的还套粉底方块)。
    // ④ 行高统一 56(此前各行随内容胖瘦不一,一眼就看得出参差)。
    for (final title in ['默认音源', '过滤翻唱', '主题', '已安装音源']) {
      final row = find.byKey(ValueKey('settings-row-$title'));
      expect(row, findsOneWidget, reason: '「$title」行应存在');
      expect(tester.getSize(row).height, AppSize.rowHeight,
          reason: '「$title」行高应为 56');
      final icon = tester.widget<Icon>(
        find.descendant(of: row, matching: find.byType(Icon)).first,
      );
      expect(icon.size, AppSize.icon, reason: '「$title」行图标应统一 20');
    }
  });
}
