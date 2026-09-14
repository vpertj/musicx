// test/ui/desktop_lyrics/lyrics_glass_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_glass.dart';

Widget pump(DesktopLyricsSettings settings, {String? artwork}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 120,
        child: LyricsGlassCard(
          settings: settings,
          artworkUrl: artwork,
          radius: 20,
          child: const Text('歌词'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('关闭封面时使用兜底渐变且不发起网络请求', (tester) async {
    await tester.pumpWidget(pump(const DesktopLyricsSettings(showArtwork: false)));
    expect(find.byKey(const Key('lyrics_glass_fallback')), findsOneWidget);
    expect(find.text('歌词'), findsOneWidget);
  });

  testWidgets('封面 URL 为空时同样走兜底', (tester) async {
    await tester.pumpWidget(pump(const DesktopLyricsSettings()));
    expect(find.byKey(const Key('lyrics_glass_fallback')), findsOneWidget);
  });

  testWidgets('圆角来自布局解析值', (tester) async {
    await tester.pumpWidget(pump(const DesktopLyricsSettings()));
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(20));
  });

  testWidgets('模糊强度为 0 时不套 ImageFiltered', (tester) async {
    await tester.pumpWidget(
      pump(const DesktopLyricsSettings(showArtwork: false, blurSigma: 0)),
    );
    expect(find.byType(ImageFiltered), findsNothing);
  });
}
