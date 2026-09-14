import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'package:musicx/core/settings/settings_providers.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mx_lyrics_settings');
    file = File('${tmp.path}/settings.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [settingsFileProvider.overrideWithValue(file)],
      );

  test('默认值与 spec 一致', () {
    expect(
      const DesktopLyricsSettings(),
      const DesktopLyricsSettings(
        textColor: Color(0xFFFF5A76),
        nextColor: Color(0xB8FFFFFF),
        fontSize: 34,
        autoScale: true,
        showNext: true,
        showArtwork: true,
        glassTint: 45,
        blurSigma: 38,
        cornerRadius: 26,
      ),
    );
  });

  test('toJson/fromJson 往返一致', () {
    const s = DesktopLyricsSettings(
      textColor: Color(0xFF00FF00),
      fontSize: 48,
      glassTint: 70,
      blurSigma: 20,
      cornerRadius: 12,
      bounds: Rect.fromLTWH(10, 20, 800, 180),
    );
    final back = DesktopLyricsSettings.fromJson(s.toJson());
    expect(back.textColor, s.textColor);
    expect(back.fontSize, 48);
    expect(back.glassTint, 70);
    expect(back.blurSigma, 20);
    expect(back.cornerRadius, 12);
    expect(back.bounds, s.bounds);
  });

  test('clamp 收敛越界值', () {
    const s = DesktopLyricsSettings(
      fontSize: 999,
      glassTint: -5,
      blurSigma: 500,
      cornerRadius: -1,
    );
    final c = s.clamp();
    expect(c.fontSize, DesktopLyricsSettings.maxFontSize);
    expect(c.glassTint, DesktopLyricsSettings.minGlassTint);
    expect(c.blurSigma, DesktopLyricsSettings.maxBlurSigma);
    expect(c.cornerRadius, DesktopLyricsSettings.minCornerRadius);
  });

  test('fromJson 对缺失/错误字段回落默认值', () {
    final s = DesktopLyricsSettings.fromJson(const {
      'fontSize': 'abc',
      'bounds': 'garbage',
    });
    expect(s.fontSize, 34);
    expect(s.bounds, isNull);
    expect(s.autoScale, isTrue);
  });

  test('update 写入 settings.json 的 desktopLyrics 键且不冲掉主题', () {
    file.writeAsStringSync('{"themeMode":"dark"}');
    final c = makeContainer();
    addTearDown(c.dispose);

    c.read(desktopLyricsSettingsProvider.notifier).update(
          const DesktopLyricsSettings(fontSize: 50),
        );

    final map = (c.read(settingsStoreProvider).readAll());
    expect(map['themeMode'], 'dark');
    expect(
      DesktopLyricsSettings.fromJson(
        Map<String, dynamic>.from(map['desktopLyrics'] as Map),
      ).fontSize,
      50,
    );
  });

  test('bounds 子字段为数字字符串时容错解析', () {
    final s = DesktopLyricsSettings.fromJson(const {
      'bounds': {'x': '10', 'y': '20', 'w': '800', 'h': '180'},
    });
    expect(s.bounds, const Rect.fromLTWH(10, 20, 800, 180));
  });

  test('bounds 子字段为垃圾值时回落 null 而不抛异常', () {
    final s = DesktopLyricsSettings.fromJson(const {
      'bounds': {'x': true, 'y': [], 'w': {}, 'h': 'abc'},
    });
    expect(s.bounds, isNull);
  });

  test('settings.json 手改坏配置时 provider 回落默认值不抛异常', () {
    file.writeAsStringSync(
      '{"desktopLyrics":{"bounds":{"x":"10","w":800},"fontSize":"abc"}}',
    );
    final c = makeContainer();
    addTearDown(c.dispose);
    expect(c.read(desktopLyricsSettingsProvider), const DesktopLyricsSettings());
  });

  test('bounds 子字段为 NaN/Infinity 字符串时按垃圾值处理', () {
    expect(
      DesktopLyricsSettings.fromJson(const {
        'bounds': {'x': '10', 'y': '20', 'w': 'NaN', 'h': '180'},
      }).bounds,
      isNull,
    );
    expect(
      DesktopLyricsSettings.fromJson(const {
        'bounds': {'x': '10', 'y': '20', 'w': '800', 'h': 'Infinity'},
      }).bounds,
      isNull,
    );
  });
}
