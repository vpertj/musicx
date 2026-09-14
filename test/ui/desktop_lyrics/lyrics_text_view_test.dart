// test/ui/desktop_lyrics/lyrics_text_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_layout.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_text_view.dart';

Widget pump({
  DesktopLyricsSettings settings = const DesktopLyricsSettings(),
  String current = '可长大后快乐却消失不见',
  String next = '日复一日的生活像是考验',
}) {
  final layout = resolveLyricsLayout(
    windowSize: const Size(880, 190),
    settings: settings,
    current: current,
    next: next,
  );
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 880,
        height: 190,
        child: LyricsTextView(
          layout: layout,
          settings: settings,
          current: current,
          next: next,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('渲染当前句与下一句,不绘制任何卡片背景', (tester) async {
    await tester.pumpWidget(pump());
    expect(find.text('可长大后快乐却消失不见'), findsOneWidget);
    expect(find.text('日复一日的生活像是考验'), findsOneWidget);
    // 纯文字模式:没有圆角裁剪 / 模糊 / 遮罩层
    expect(find.byType(ClipRRect), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('关闭「显示下一句」时不渲染下一句', (tester) async {
    await tester.pumpWidget(
      pump(settings: const DesktopLyricsSettings(showNext: false)),
    );
    expect(find.text('可长大后快乐却消失不见'), findsOneWidget);
    expect(find.text('日复一日的生活像是考验'), findsNothing);
  });

  testWidgets('当前句使用设置的颜色与字号', (tester) async {
    const settings = DesktopLyricsSettings(
      textColor: Color(0xFF00FF00),
      fontSize: 48,
    );
    await tester.pumpWidget(pump(settings: settings));
    final style = tester
        .widget<Text>(find.text('可长大后快乐却消失不见'))
        .style!;
    expect(style.color, const Color(0xFF00FF00));
    expect(style.fontSize, 48);
  });
}
