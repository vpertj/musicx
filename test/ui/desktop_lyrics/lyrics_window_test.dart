// test/ui/desktop_lyrics/lyrics_window_test.dart
//
// 浮窗渲染分支验证:默认「极简纯文字」不画任何卡片/边框,
// 切到毛玻璃样式才渲染玻璃卡。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_glass.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_text_view.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_window.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mx_lyrics_window');
    file = File('${tmp.path}/settings.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(880, 190);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsFileProvider.overrideWithValue(file)],
        child: const LyricsWindow(),
      ),
    );
    await tester.pump();
  }

  testWidgets('默认极简纯文字:只有文字,没有卡片/边框/模糊', (tester) async {
    await pump(tester);
    expect(find.byType(LyricsTextView), findsOneWidget);
    expect(find.byType(LyricsGlassCard), findsNothing);
    expect(find.byType(ClipRRect), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.text('MusicX · 桌面歌词'), findsOneWidget);
  });

  testWidgets('毛玻璃样式才渲染玻璃卡', (tester) async {
    file.writeAsStringSync('{"desktopLyrics":{"cardStyle":"glass"}}');
    await pump(tester);
    expect(find.byType(LyricsGlassCard), findsOneWidget);
  });

  testWidgets('双击歌词不会抛异常(唤出主程序走上行通道)', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(LyricsTextView));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byType(LyricsTextView));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
