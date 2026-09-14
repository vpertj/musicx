// test/ui/desktop_lyrics/lyrics_settings_section_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_glass.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_settings_section.dart';

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
        child: const MaterialApp(home: Scaffold(body: LyricsSettingsSection())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('渲染预览卡与各配置项', (tester) async {
    await pump(tester);
    expect(find.byType(LyricsGlassCard), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(4)); // 字号/浓度/模糊/圆角
    expect(find.byType(Switch), findsNWidgets(3)); // 自动缩放/下一句/封面
    expect(find.text('恢复默认'), findsOneWidget);
  });

  testWidgets('关闭「显示下一句」会写入设置文件', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.byType(Switch).at(1));
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
