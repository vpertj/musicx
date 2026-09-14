// test/ui/desktop_lyrics/lyrics_settings_section_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_glass.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_settings_section.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_text_view.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mx_lyrics_section');
    file = File('${tmp.path}/settings.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [settingsFileProvider.overrideWithValue(file)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: LyricsSettingsSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('默认纯文字:预览不渲染玻璃卡,也不显示玻璃参数', (tester) async {
    await pump(tester);
    expect(find.byType(LyricsTextView), findsOneWidget);
    expect(find.byType(LyricsGlassCard), findsNothing);
    // 纯文字样式只有「字号」一个滑杆:浓度/模糊/圆角都只对卡片有意义
    expect(find.byType(Slider), findsNWidgets(1));
    expect(find.text('玻璃浓度'), findsNothing);
    expect(find.text('圆角'), findsNothing);
    expect(find.text('用专辑封面做玻璃背景'), findsNothing);
    expect(find.text('恢复默认'), findsOneWidget);
  });

  testWidgets('切到毛玻璃样式会写入设置并显示玻璃参数', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('毛玻璃'));
    await tester.pumpAndSettle();

    expect(
      container.read(desktopLyricsSettingsProvider).cardStyle,
      LyricsCardStyle.glass,
    );
    expect(file.readAsStringSync().contains('"cardStyle":"glass"'), isTrue);
    expect(find.byType(LyricsGlassCard), findsOneWidget);
    expect(find.text('玻璃浓度'), findsOneWidget);
  });

  testWidgets('关闭「显示下一句」会写入设置文件', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.descendant(
      of: find.ancestor(
        of: find.text('显示下一句'),
        matching: find.byType(Row),
      ),
      matching: find.byType(Switch),
    ));
    await tester.pumpAndSettle();

    expect(
      container.read(desktopLyricsSettingsProvider).showNext,
      isFalse,
    );
    final content = file.readAsStringSync();
    expect(content.contains('desktopLyrics'), isTrue);
    // SettingsStore.merge 用紧凑 jsonEncode,键值间无空格。
    expect(content.contains('"showNext":false'), isTrue);
  });

  testWidgets('拖动字号滑杆会改变 fontSize', (tester) async {
    final container = await pump(tester);
    final before = container.read(desktopLyricsSettingsProvider).fontSize;
    await tester.drag(find.byType(Slider).first, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(container.read(desktopLyricsSettingsProvider).fontSize,
        isNot(before));
  });
}
