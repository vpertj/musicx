# 桌面歌词浮窗 v2(可调毛玻璃)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把桌面歌词浮窗从「写死样式、模糊无效、不能缩放」重做成「封面模糊真毛玻璃 + 字号颜色可调 + 四边四角自由缩放 + 自适应布局 + 设置页/悬停工具条双入口」。

**Architecture:** 设置层先用「合并写」存储替代整体覆盖写(修既有缺陷),再在其上加歌词外观模型;布局与缩放几何全部收敛为**纯函数**便于单测;玻璃质感是独立的分层渲染组件,浮窗与设置页预览共用;主窗口是唯一设置写者,浮窗(独立引擎)只读首帧 + 接收推送,工具条改动走独立上行通道回传。

**Tech Stack:** Flutter 3.44 / flutter_riverpod 3.x / desktop_multi_window 0.3.1 / window_manager 0.5.2 / screen_retriever 0.2.2(已是传递依赖,本计划提为直接依赖)

**Spec:** `docs/superpowers/specs/2026-09-11-desktop-lyrics-v2-design.md`(实现与验收以 spec 为准,本计划逐条落实)

## Global Constraints

- **不修改任何原生代码**:`macos/`、`windows/`、`android/` 一律不动。
- **不新增第三方 package**;唯一的 pubspec 改动是把已在依赖图里的 `screen_retriever` 提为直接依赖(否则 `depend_on_referenced_packages` lint 会报)。
- Dart/Flutter 版本 3.44:`Color` 序列化用 `toARGB32()`(不要用已废弃的 `.value`)。
- 所有 `windowManager.*` / `WindowMethodChannel` 调用必须包 try/catch(沿用现有代码的容错惯例),不得让浮窗因插件异常崩溃。
- 持久化写入**只**能经 `SettingsStore.merge`,禁止再出现整体覆盖写。
- 布局/几何逻辑必须是纯函数,放在 `lyrics_layout.dart` / `lyrics_resize.dart`,Widget 里不得内联计算规则。
- 每个任务结束 `flutter analyze` 不得新增告警,`flutter test` 必须全绿。
- 中文文案与注释沿用现有代码风格(简体中文、全角标点)。

---

### Task 1: SettingsStore —— settings.json 的合并写存储

**Files:**
- Create: `lib/core/settings/settings_store.dart`
- Test: `test/core/settings/settings_store_test.dart`

**Interfaces:**
- Consumes: 无(直接持有 `File`,不依赖 Riverpod,便于单测)
- Produces: `class SettingsStore { SettingsStore(File file); Map<String, dynamic> readAll(); void merge(Map<String, dynamic> patch); }` —— 后续所有任务经 `settingsStoreProvider` 使用它

- [ ] **Step 1: 写失败测试**

```dart
// test/core/settings/settings_store_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/settings_store.dart';

void main() {
  late Directory tmp;
  late File file;
  late SettingsStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mx_settings_store');
    file = File('${tmp.path}/settings.json');
    store = SettingsStore(file);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('merge 写入新 key 并落盘', () {
    store.merge({'themeMode': 'dark'});
    expect(jsonDecode(file.readAsStringSync()), {'themeMode': 'dark'});
  });

  test('merge 只覆盖传入 key,不冲掉其它设置', () {
    store.merge({'desktopLyrics': {'fontSize': 40}});
    store.merge({'themeMode': 'dark'});
    expect(store.readAll()['themeMode'], 'dark');
    expect((store.readAll()['desktopLyrics'] as Map)['fontSize'], 40);
  });

  test('文件不存在时 readAll 返回空 map', () {
    expect(store.readAll(), isEmpty);
  });

  test('文件损坏时 readAll 返回空且 merge 能自愈', () {
    file.writeAsStringSync('{not json');
    expect(store.readAll(), isEmpty);
    store.merge({'a': 1});
    expect(store.readAll()['a'], 1);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/settings/settings_store_test.dart`
Expected: FAIL(`settings_store.dart` 不存在,编译错误)

- [ ] **Step 3: 最小实现**

```dart
// lib/core/settings/settings_store.dart
import 'dart:convert';
import 'dart:io';

/// settings.json 的合并写存储。
///
/// 旧实现在 `_persist` 中**整体覆盖写**文件,任何新增设置项都会被其它设置项
/// 冲掉;因此所有读写必须经由 [SettingsStore]:[merge] 只覆盖传入的 key。
///
/// 只做一层浅合并:当前全部设置项都是标量或一层嵌套 map,无需深合并。
class SettingsStore {
  SettingsStore(this.file);

  final File file;

  /// 读取全部设置;文件不存在或损坏时返回空 map(不抛异常)。
  Map<String, dynamic> readAll() {
    try {
      if (!file.existsSync()) return const {};
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) return Map<String, dynamic>.of(decoded);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return const {};
  }

  /// 合并写入:只覆盖 [patch] 中出现的 key。
  void merge(Map<String, dynamic> patch) {
    if (patch.isEmpty) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(<String, dynamic>{...readAll(), ...patch}));
    } catch (_) {}
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/settings/settings_store_test.dart`
Expected: PASS(4 个测试全绿)

- [ ] **Step 5: Commit**

```bash
git add lib/core/settings/settings_store.dart test/core/settings/settings_store_test.dart
git commit -m "feat(settings): merge-write SettingsStore for settings.json"
```

---

### Task 2: 主题写入迁移到 SettingsStore(修「冲掉其它设置」缺陷)

**Files:**
- Modify: `lib/core/settings/settings_providers.dart`(只动 `ThemePreferenceController` 的 `build` 与 `_persist`)
- Test: `test/core/settings/theme_preference_test.dart`(追加 1 个测试)

**Interfaces:**
- Consumes: `SettingsStore`(Task 1)
- Produces: `settingsStoreProvider = Provider<SettingsStore>`(定义在本文件,后续任务都用它);`themePreferenceProvider` 对外 API 不变

- [ ] **Step 1: 追加失败测试**(加到 `test/core/settings/theme_preference_test.dart` 的 `main()` 末尾)

```dart
  test('切主题不冲掉其它设置项(desktopLyrics 保留)', () {
    file.writeAsStringSync(
      jsonEncode({'desktopLyrics': {'fontSize': 44}}),
    );
    final c = makeContainer();
    addTearDown(c.dispose);
    c.read(themePreferenceProvider.notifier).setDark();

    final map =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(map['themeMode'], 'dark');
    expect((map['desktopLyrics'] as Map)['fontSize'], 44);
  });
```

注意:该测试文件目前没有 `file` 变量,需要在 `setUp` 里补 `file = File('${tmp.path}/settings.json');`(与 `makeContainer()` 里的路径一致),并在文件头补 `import 'dart:convert';`。`setUp` 改为:

```dart
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mx_theme');
    file = File('${tmp.path}/settings.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/settings/theme_preference_test.dart`
Expected: 新增测试 FAIL(写入后 `desktopLyrics` key 丢失),既有 3 个测试 PASS

- [ ] **Step 3: 实现** —— `lib/core/settings/settings_providers.dart` 里:

a) 文件头加 `import 'package:musicx/core/settings/settings_store.dart';`

b) 紧跟 `settingsFileProvider` 之后新增:

```dart
/// 设置存储(合并写),所有设置项的落盘都经由它。
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(settingsFileProvider)),
);
```

c) `ThemePreferenceController` 的 `build` 与 `_persist` 改为:

```dart
  @override
  ThemeMode build() {
    final map = ref.watch(settingsStoreProvider).readAll();
    if (map['themeMode'] == 'dark') return ThemeMode.dark;
    return ThemeMode.light;
  }
```

```dart
  void _persist() {
    ref
        .read(settingsStoreProvider)
        .merge({'themeMode': state == ThemeMode.dark ? 'dark' : 'light'});
  }
```

(`dart:convert` / `dart:io` 若因此不再被本文件使用,删除对应 import。)

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/settings/theme_preference_test.dart test/core/settings/settings_store_test.dart`
Expected: PASS(4 + 4 全绿)

- [ ] **Step 5: Commit**

```bash
git add lib/core/settings/settings_providers.dart test/core/settings/theme_preference_test.dart
git commit -m "fix(settings): persist theme via merge-write store to avoid clobbering other keys"
```

---

### Task 3: DesktopLyricsSettings 模型 + provider

**Files:**
- Create: `lib/core/settings/desktop_lyrics_settings.dart`
- Test: `test/core/settings/desktop_lyrics_settings_test.dart`

**Interfaces:**
- Consumes: `settingsStoreProvider`(Task 2)
- Produces:
  - `class DesktopLyricsSettings` 字段:`textColor/nextColor (Color)`、`fontSize (double, 默认34)`、`autoScale (bool, true)`、`showNext (bool, true)`、`showArtwork (bool, true)`、`glassTint (int, 45)`、`blurSigma (double, 38)`、`cornerRadius (double, 26)`、`bounds (Rect?, null)`;常量 `defaultTextColor = Color(0xFFFF5A76)`、`defaultNextColor = Color(0xB8FFFFFF)`、`minFontSize = 12`、`maxFontSize = 120`、`minGlassTint/maxGlassTint = 0/100`、`minBlurSigma/maxBlurSigma = 0/60`、`minCornerRadius/maxCornerRadius = 0/60`;方法 `copyWith(...)`、`clamp()`、`toJson()`、`fromJson(Map<String,dynamic>)`(兼容 null/缺字段/越界)
  - `desktopLyricsSettingsProvider = NotifierProvider<DesktopLyricsSettingsController, DesktopLyricsSettings>`,`DesktopLyricsSettingsController.update(DesktopLyricsSettings)` 负责写入持久化

- [ ] **Step 1: 写失败测试**

```dart
// test/core/settings/desktop_lyrics_settings_test.dart
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
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/settings/desktop_lyrics_settings_test.dart`
Expected: FAIL(`desktop_lyrics_settings.dart` 不存在)

- [ ] **Step 3: 实现**

```dart
// lib/core/settings/desktop_lyrics_settings.dart
import 'dart:ui' show Color, Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:musicx/core/settings/settings_providers.dart';

/// 桌面歌词浮窗外观设置。持久化到 settings.json 的 `desktopLyrics` 键。
class DesktopLyricsSettings {
  const DesktopLyricsSettings({
    this.textColor = defaultTextColor,
    this.nextColor = defaultNextColor,
    this.fontSize = 34,
    this.autoScale = true,
    this.showNext = true,
    this.showArtwork = true,
    this.glassTint = 45,
    this.blurSigma = 38,
    this.cornerRadius = 26,
    this.bounds,
  });

  static const Color defaultTextColor = Color(0xFFFF5A76);
  static const Color defaultNextColor = Color(0xB8FFFFFF); // 白 72%

  static const double minFontSize = 12;
  static const double maxFontSize = 120;
  static const int minGlassTint = 0;
  static const int maxGlassTint = 100;
  static const double minBlurSigma = 0;
  static const double maxBlurSigma = 60;
  static const double minCornerRadius = 0;
  static const double maxCornerRadius = 60;

  /// 当前句颜色。
  final Color textColor;

  /// 下一句颜色。
  final Color nextColor;

  /// 基准字号;[autoScale] 开启时按窗口高度等比缩放。
  final double fontSize;
  final bool autoScale;

  /// 是否显示下一句(窗口高度不足时布局会强制隐藏)。
  final bool showNext;

  /// 是否用专辑封面做模糊背景(关掉退化为纯彩色玻璃)。
  final bool showArtwork;

  /// 暗色遮罩浓度 0–100。
  final int glassTint;

  /// 封面模糊强度 0–60。
  final double blurSigma;

  /// 卡片圆角基准值 0–60(布局会再按窗口缩放并夹取)。
  final double cornerRadius;

  /// 上次窗口几何(逻辑坐标);null 表示从未记录。
  final Rect? bounds;

  DesktopLyricsSettings copyWith({
    Color? textColor,
    Color? nextColor,
    double? fontSize,
    bool? autoScale,
    bool? showNext,
    bool? showArtwork,
    int? glassTint,
    double? blurSigma,
    double? cornerRadius,
    Rect? bounds,
    bool clearBounds = false,
  }) {
    return DesktopLyricsSettings(
      textColor: textColor ?? this.textColor,
      nextColor: nextColor ?? this.nextColor,
      fontSize: fontSize ?? this.fontSize,
      autoScale: autoScale ?? this.autoScale,
      showNext: showNext ?? this.showNext,
      showArtwork: showArtwork ?? this.showArtwork,
      glassTint: glassTint ?? this.glassTint,
      blurSigma: blurSigma ?? this.blurSigma,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      bounds: clearBounds ? null : (bounds ?? this.bounds),
    );
  }

  /// 把所有数值收敛到合法区间,防止手改配置导致界面异常。
  DesktopLyricsSettings clamp() {
    return DesktopLyricsSettings(
      textColor: textColor,
      nextColor: nextColor,
      fontSize: fontSize.clamp(minFontSize, maxFontSize),
      autoScale: autoScale,
      showNext: showNext,
      showArtwork: showArtwork,
      glassTint: glassTint.clamp(minGlassTint, maxGlassTint),
      blurSigma: blurSigma.clamp(minBlurSigma, maxBlurSigma),
      cornerRadius: cornerRadius.clamp(minCornerRadius, maxCornerRadius),
      bounds: bounds,
    );
  }

  Map<String, dynamic> toJson() {
    final b = bounds;
    return <String, dynamic>{
      'textColor': textColor.toARGB32(),
      'nextColor': nextColor.toARGB32(),
      'fontSize': fontSize,
      'autoScale': autoScale,
      'showNext': showNext,
      'showArtwork': showArtwork,
      'glassTint': glassTint,
      'blurSigma': blurSigma,
      'cornerRadius': cornerRadius,
      if (b != null)
        'bounds': {
          'x': b.left,
          'y': b.top,
          'w': b.width,
          'h': b.height,
        },
    };
  }

  factory DesktopLyricsSettings.fromJson(Map<String, dynamic> json) {
    return DesktopLyricsSettings(
      textColor: _color(json['textColor'], defaultTextColor),
      nextColor: _color(json['nextColor'], defaultNextColor),
      fontSize: _double(json['fontSize'], 34),
      autoScale: _bool(json['autoScale'], true),
      showNext: _bool(json['showNext'], true),
      showArtwork: _bool(json['showArtwork'], true),
      glassTint: _int(json['glassTint'], 45),
      blurSigma: _double(json['blurSigma'], 38),
      cornerRadius: _double(json['cornerRadius'], 26),
      bounds: _rect(json['bounds']),
    ).clamp();
  }

  static Color _color(Object? raw, Color fallback) {
    final v = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (v == null || v < 0 || v > 0xFFFFFFFF) return fallback;
    return Color(v);
  }

  static double _double(Object? raw, double fallback) {
    if (raw is num) {
      final v = raw.toDouble();
      return v.isFinite ? v : fallback;
    }
    final v = double.tryParse('$raw');
    return v ?? fallback;
  }

  static int _int(Object? raw, int fallback) {
    if (raw is num) return raw.round();
    return int.tryParse('$raw') ?? fallback;
  }

  static bool _bool(Object? raw, bool fallback) =>
      raw is bool ? raw : fallback;

  static Rect? _rect(Object? raw) {
    if (raw is! Map) return null;
    final x = (raw['x'] as num?)?.toDouble();
    final y = (raw['y'] as num?)?.toDouble();
    final w = (raw['w'] as num?)?.toDouble();
    final h = (raw['h'] as num?)?.toDouble();
    if (x == null || y == null || w == null || h == null) return null;
    if (w <= 0 || h <= 0) return null;
    return Rect.fromLTWH(x, y, w, h);
  }
}

/// 歌词外观设置控制器:主窗口是唯一写者(浮窗只读 + 接收推送)。
class DesktopLyricsSettingsController extends Notifier<DesktopLyricsSettings> {
  @override
  DesktopLyricsSettings build() {
    final map = ref.watch(settingsStoreProvider).readAll();
    final raw = map['desktopLyrics'];
    return DesktopLyricsSettings.fromJson(
      raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{},
    );
  }

  /// 更新并持久化(经合并写,不影响其它设置)。
  void update(DesktopLyricsSettings next) {
    final value = next.clamp();
    state = value;
    ref.read(settingsStoreProvider).merge({'desktopLyrics': value.toJson()});
  }
}

final desktopLyricsSettingsProvider =
    NotifierProvider<DesktopLyricsSettingsController, DesktopLyricsSettings>(
      DesktopLyricsSettingsController.new,
    );
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/settings/desktop_lyrics_settings_test.dart`
Expected: PASS(5 个测试全绿)

- [ ] **Step 5: Commit**

```bash
git add lib/core/settings/desktop_lyrics_settings.dart test/core/settings/desktop_lyrics_settings_test.dart
git commit -m "feat(desktop-lyrics): appearance settings model with merge-write persistence"
```

---

### Task 4: 自适应布局纯函数

**Files:**
- Create: `lib/ui/desktop_lyrics/lyrics_layout.dart`
- Test: `test/ui/desktop_lyrics/lyrics_layout_test.dart`

**Interfaces:**
- Consumes: `DesktopLyricsSettings`(Task 3)
- Produces:
  - `class LyricsLayout { fontSize, nextFontSize (double); showNext (bool); direction (Axis); padding (EdgeInsets); accentBarWidth, cardRadius (double); }`
  - `LyricsLayout resolveLyricsLayout({required Size windowSize, required DesktopLyricsSettings settings, required String current, required String next})`
  - 常量 `kLyricsReferenceHeight = 190.0`、`kLyricsMinScale = 0.55`、`kLyricsMaxScale = 2.2`、`kLyricsSingleLineHeight = 120.0`、`kLyricsHorizontalRatio = 6.0`(Task 8 的浮窗用)

- [ ] **Step 1: 写失败测试**

```dart
// test/ui/desktop_lyrics/lyrics_layout_test.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const settings = DesktopLyricsSettings();

  LyricsLayout resolve(Size size, {DesktopLyricsSettings s = settings}) {
    return resolveLyricsLayout(
      windowSize: size,
      settings: s,
      current: '等到树叶都泛了黄',
      next: '等到眼里全是伤',
    );
  }

  test('基准高度 190 时不缩放', () {
    final l = resolve(const Size(880, 190));
    expect(l.fontSize, 34);
    expect(l.showNext, isTrue);
    expect(l.direction, Axis.vertical);
    expect(l.cardRadius, 26);
  });

  test('autoScale 关闭时字号恒为基准值', () {
    final l = resolve(const Size(400, 600),
        s: const DesktopLyricsSettings(autoScale: false));
    expect(l.fontSize, 34);
  });

  test('过高窗口字号放大并夹到 2.2 倍', () {
    final l = resolve(const Size(400, 900));
    expect(l.fontSize, closeTo(34 * 2.2, 0.01));
  });

  test('过矮窗口字号夹到 0.55 倍且不低于 12', () {
    final l = resolve(const Size(400, 60));
    expect(l.fontSize, closeTo(34 * 0.55, 0.01));
    expect(l.fontSize, greaterThanOrEqualTo(12));
  });

  test('高度低于 120 时隐藏下一句', () {
    final l = resolve(const Size(880, 100));
    expect(l.showNext, isFalse);
  });

  test('showNext 关掉时即使窗口够高也不显示', () {
    final l = resolve(const Size(880, 300),
        s: const DesktopLyricsSettings(showNext: false));
    expect(l.showNext, isFalse);
    expect(l.direction, Axis.vertical);
  });

  test('宽扁窗口且放得下时横向并排', () {
    final l = resolve(const Size(1600, 110));
    expect(l.direction, Axis.horizontal);
  });

  test('超长当前句逐档降字号到下限 12', () {
    final l = resolveLyricsLayout(
      windowSize: const Size(400, 190),
      settings: settings,
      current: '长' * 200,
      next: '短',
    );
    expect(l.fontSize, 12);
  });

  test('内边距随窗口等比缩放且被夹取', () {
    expect(resolve(const Size(880, 190)).padding.horizontal, 56);
    expect(resolve(const Size(880, 900)).padding.horizontal, lessThanOrEqualTo(96));
    expect(resolve(const Size(400, 60)).padding.horizontal, greaterThanOrEqualTo(32));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/desktop_lyrics/lyrics_layout_test.dart`
Expected: FAIL(`lyrics_layout.dart` 不存在)

- [ ] **Step 3: 实现**

```dart
// lib/ui/desktop_lyrics/lyrics_layout.dart
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'package:musicx/core/settings/desktop_lyrics_settings.dart';

/// 自适应基准:浮窗默认高度,保证老用户观感不变。
const double kLyricsReferenceHeight = 190;

/// 字号缩放系数上下限。
const double kLyricsMinScale = 0.55;
const double kLyricsMaxScale = 2.2;

/// 窗口高度低于该值时只显示当前句。
const double kLyricsSingleLineHeight = 120;

/// 宽高比达到该值且两行都放得下时,当前句与下一句横向并排。
const double kLyricsHorizontalRatio = 6;

/// 布局解析结果:浮窗与设置页预览都以它为唯一布局事实来源。
class LyricsLayout {
  const LyricsLayout({
    required this.fontSize,
    required this.nextFontSize,
    required this.showNext,
    required this.direction,
    required this.padding,
    required this.accentBarWidth,
    required this.cardRadius,
  });

  final double fontSize;
  final double nextFontSize;
  final bool showNext;
  final Axis direction;
  final EdgeInsets padding;
  final double accentBarWidth;
  final double cardRadius;
}

/// 由窗口尺寸 + 设置解析出实际布局(纯函数,无 Widget 依赖)。
LyricsLayout resolveLyricsLayout({
  required Size windowSize,
  required DesktopLyricsSettings settings,
  required String current,
  required String next,
}) {
  final safeSize = Size(
    windowSize.width <= 0 ? 1 : windowSize.width,
    windowSize.height <= 0 ? 1 : windowSize.height,
  );

  final scale = settings.autoScale
      ? (safeSize.height / kLyricsReferenceHeight)
          .clamp(kLyricsMinScale, kLyricsMaxScale)
      : 1.0;

  // 派生内边距/竖条/圆角:按窗口缩放再夹取,避免极端尺寸下变形。
  final padding = EdgeInsets.symmetric(
    horizontal: (28 * scale).clamp(16.0, 48.0),
    vertical: (18 * scale).clamp(10.0, 34.0),
  );
  final accentBarWidth = (6 * scale).clamp(3.0, 12.0);
  final cardRadius = (settings.cornerRadius * scale).clamp(8.0, 60.0);

  var fontSize = (settings.fontSize * scale).clamp(
    DesktopLyricsSettings.minFontSize,
    DesktopLyricsSettings.maxFontSize,
  );
  final showNext = settings.showNext &&
      next.trim().isNotEmpty &&
      safeSize.height >= kLyricsSingleLineHeight;

  // 纵向可用宽度 = 窗口宽 - 内边距 - 竖条与间距。
  final reserved = padding.horizontal + accentBarWidth + 22 * scale;
  final availableWidth = math.max(1.0, safeSize.width - reserved);

  // 溢出保护:当前句放不下时逐档降字号到下限,仍放不下才交给 ellipsis。
  while (fontSize > DesktopLyricsSettings.minFontSize &&
      measureTextWidth(current, fontSize) > availableWidth) {
    fontSize -= 1;
  }
  fontSize = math.max(DesktopLyricsSettings.minFontSize, fontSize);

  // 排布方向:宽扁窗口且两行并排实测放得下才横向。
  var direction = Axis.vertical;
  if (showNext && safeSize.width / safeSize.height >= kLyricsHorizontalRatio) {
    final nextSize = (fontSize * 0.56).clamp(11.0, fontSize);
    final total = measureTextWidth(current, fontSize) +
        22 * scale +
        measureTextWidth(next, nextSize);
    if (total <= availableWidth) direction = Axis.horizontal;
  }

  return LyricsLayout(
    fontSize: fontSize,
    nextFontSize: (fontSize * 0.56).clamp(11.0, fontSize),
    showNext: showNext,
    direction: direction,
    padding: padding,
    accentBarWidth: accentBarWidth,
    cardRadius: cardRadius,
  );
}

/// 实测单行文本宽度(TextPainter),供溢出保护与横排判断使用。
double measureTextWidth(String text, double fontSize) {
  if (text.trim().isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.width;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/ui/desktop_lyrics/lyrics_layout_test.dart`
Expected: PASS(9 个测试全绿)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/desktop_lyrics/lyrics_layout.dart test/ui/desktop_lyrics/lyrics_layout_test.dart
git commit -m "feat(desktop-lyrics): pure adaptive layout resolution"
```

---

### Task 5: 缩放几何纯函数

**Files:**
- Create: `lib/ui/desktop_lyrics/lyrics_resize.dart`
- Test: `test/ui/desktop_lyrics/lyrics_resize_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum ResizeEdge { top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight }`
  - `const Size kLyricsMinWindowSize = Size(320, 90)`
  - `Rect resizeRect({required Rect current, required ResizeEdge edge, required Offset delta, Size minSize = kLyricsMinWindowSize, Size? maxSize})`
  - `Rect clampRectToWorkArea(Rect rect, Rect workArea)`(Task 8 还原窗口几何时用)

- [ ] **Step 1: 写失败测试**

```dart
// test/ui/desktop_lyrics/lyrics_resize_test.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_resize.dart';

void main() {
  const base = Rect.fromLTWH(100, 200, 880, 190);

  Rect drag(ResizeEdge edge, double dx, double dy, {Size? maxSize}) {
    return resizeRect(
      current: base,
      edge: edge,
      delta: Offset(dx, dy),
      maxSize: maxSize,
    );
  }

  test('拖右边缘:宽度增加、左边界不动', () {
    final r = drag(ResizeEdge.right, 50, 0);
    expect(r.left, 100);
    expect(r.width, 930);
  });

  test('拖左边缘向左:左边界左移、宽度增加', () {
    final r = drag(ResizeEdge.left, -30, 0);
    expect(r.left, 70);
    expect(r.right, 980);
    expect(r.width, 910);
  });

  test('拖左边缘越过最小宽度:宽度被夹到最小且不翻转', () {
    final r = drag(ResizeEdge.left, 900, 0);
    expect(r.width, 320);
    expect(r.left, 980 - 320);
  });

  test('拖顶边向上:高度增加、底边不动;越过最小高度被夹住', () {
    expect(drag(ResizeEdge.top, 0, -40).bottom, 390);
    expect(drag(ResizeEdge.top, 0, 500).height, 90);
  });

  test('拖左上角同时改变左边与顶边', () {
    final r = drag(ResizeEdge.topLeft, -10, -10);
    expect(r.left, 90);
    expect(r.top, 190);
  });

  test('maxSize 限制最大尺寸', () {
    final r = drag(ResizeEdge.right, 5000, 0, maxSize: const Size(1200, 800));
    expect(r.width, 1200);
  });

  test('clampRectToWorkArea 把跑出屏幕的窗口拉回来', () {
    final work = const Rect.fromLTWH(0, 0, 1440, 900);
    final r = clampRectToWorkArea(const Rect.fromLTWH(1400, 850, 880, 190), work);
    expect(r.right <= work.right, isTrue);
    expect(r.bottom <= work.bottom, isTrue);
    expect(r.width, 880);
  });

  test('clampRectToWorkArea 把大于工作区的窗口压到工作区大小', () {
    final work = const Rect.fromLTWH(0, 0, 1000, 600);
    final r = clampRectToWorkArea(const Rect.fromLTWH(-50, -50, 2000, 1200), work);
    expect(r, work);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/desktop_lyrics/lyrics_resize_test.dart`
Expected: FAIL(`lyrics_resize.dart` 不存在)

- [ ] **Step 3: 实现**

```dart
// lib/ui/desktop_lyrics/lyrics_resize.dart
import 'dart:math' as math;
import 'dart:ui';

/// 缩放热区:四条边 + 四个角。
enum ResizeEdge {
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// 浮窗最小尺寸(逻辑像素)。
const Size kLyricsMinWindowSize = Size(320, 90);

/// 根据拖拽增量计算缩放后的窗口几何(纯函数,便于单测)。
///
/// 拖左/上边时同步移动原点;结果被 [minSize] 与 [maxSize] 双向夹取,
/// 保证尺寸永不小于最小值、永不大于最大值,也不会左右/上下翻转。
Rect resizeRect({
  required Rect current,
  required ResizeEdge edge,
  required Offset delta,
  Size minSize = kLyricsMinWindowSize,
  Size? maxSize,
}) {
  var left = current.left;
  var top = current.top;
  var right = current.right;
  var bottom = current.bottom;

  final growsRight = edge == ResizeEdge.right ||
      edge == ResizeEdge.topRight ||
      edge == ResizeEdge.bottomRight;
  final growsLeft = edge == ResizeEdge.left ||
      edge == ResizeEdge.topLeft ||
      edge == ResizeEdge.bottomLeft;
  final growsBottom = edge == ResizeEdge.bottom ||
      edge == ResizeEdge.bottomLeft ||
      edge == ResizeEdge.bottomRight;
  final growsTop = edge == ResizeEdge.top ||
      edge == ResizeEdge.topLeft ||
      edge == ResizeEdge.topRight;

  if (growsRight) right += delta.dx;
  if (growsBottom) bottom += delta.dy;
  if (growsLeft) left += delta.dx;
  if (growsTop) top += delta.dy;

  void clampWidth(double maxW) {
    final w = right - left;
    if (w < minSize.width) {
      if (growsLeft) left = right - minSize.width;
      if (growsRight) right = left + minSize.width;
    } else if (w > maxW) {
      if (growsLeft) left = right - maxW;
      if (growsRight) right = left + maxW;
    }
  }

  void clampHeight(double maxH) {
    final h = bottom - top;
    if (h < minSize.height) {
      if (growsTop) top = bottom - minSize.height;
      if (growsBottom) bottom = top + minSize.height;
    } else if (h > maxH) {
      if (growsTop) top = bottom - maxH;
      if (growsBottom) bottom = top + maxH;
    }
  }

  clampWidth(maxSize == null ? double.infinity : math.max(minSize.width, maxSize.width));
  clampHeight(maxSize == null ? double.infinity : math.max(minSize.height, maxSize.height));

  return Rect.fromLTRB(left, top, right, bottom);
}

/// 把窗口几何夹回 [workArea] 内,保证窗口完整可见可操作。
Rect clampRectToWorkArea(Rect rect, Rect workArea) {
  final width = math.min(rect.width, workArea.width);
  final height = math.min(rect.height, workArea.height);
  final left = (rect.left).clamp(workArea.left, workArea.right - width);
  final top = (rect.top).clamp(workArea.top, workArea.bottom - height);
  return Rect.fromLTWH(left, top, width, height);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/ui/desktop_lyrics/lyrics_resize_test.dart`
Expected: PASS(8 个测试全绿)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/desktop_lyrics/lyrics_resize.dart test/ui/desktop_lyrics/lyrics_resize_test.dart
git commit -m "feat(desktop-lyrics): pure resize geometry helpers"
```

---

### Task 6: 玻璃渲染组件(浮窗与预览共用)

**Files:**
- Create: `lib/ui/desktop_lyrics/lyrics_glass.dart`
- Test: `test/ui/desktop_lyrics/lyrics_glass_test.dart`

**Interfaces:**
- Consumes: `DesktopLyricsSettings`(Task 3)
- Produces: `class LyricsGlassCard extends StatelessWidget { const LyricsGlassCard({Key? key, required DesktopLyricsSettings settings, required String? artworkUrl, required double radius, Widget? child}); }` —— Task 8(浮窗)与 Task 9(设置页预览)共用;兜底渐变容器带 `Key('lyrics_glass_fallback')`

- [ ] **Step 1: 写失败测试**

```dart
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/desktop_lyrics/lyrics_glass_test.dart`
Expected: FAIL(`lyrics_glass.dart` 不存在)

- [ ] **Step 3: 实现**

```dart
// lib/ui/desktop_lyrics/lyrics_glass.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:musicx/core/settings/desktop_lyrics_settings.dart';

/// 毛玻璃卡片:封面模糊层 + 压暗层 + 噪点层 + 高光描边层 + 内容层。
///
/// 浮窗与设置页预览共用,保证「所见即所得」。
/// 关键:模糊作用在**封面图自己的子树**上([ImageFiltered]),
/// 而不是像旧版那样用 [BackdropFilter] 去模糊一个空的窗口背景。
class LyricsGlassCard extends StatelessWidget {
  const LyricsGlassCard({
    super.key,
    required this.settings,
    required this.artworkUrl,
    required this.radius,
    this.child,
  });

  final DesktopLyricsSettings settings;

  /// 专辑封面 URL;null/空/加载失败时退化为柔光斑渐变。
  final String? artworkUrl;

  /// 圆角,由布局解析给出(随窗口缩放),不由设置直接决定。
  final double radius;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 34,
            spreadRadius: -4,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _CoverBackdrop(settings: settings, artworkUrl: artworkUrl),
            _TintLayer(settings: settings),
            const Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: _NoisePainter())),
            ),
            _HighlightLayer(radius: radius),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}

/// 第①层:封面模糊背景(或兜底柔光斑)。
class _CoverBackdrop extends StatelessWidget {
  const _CoverBackdrop({required this.settings, required this.artworkUrl});

  final DesktopLyricsSettings settings;
  final String? artworkUrl;

  @override
  Widget build(BuildContext context) {
    final tint = settings.textColor;

    Widget fallback() => DecoratedBox(
          key: const Key('lyrics_glass_fallback'),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.6, -0.4),
              radius: 1.4,
              colors: [
                tint.withValues(alpha: 0.55),
                tint.withValues(alpha: 0.16),
                Colors.black.withValues(alpha: 0.35),
              ],
            ),
          ),
        );

    final url = artworkUrl;
    if (!settings.showArtwork || url == null || url.isEmpty) return fallback();

    Widget image = Image.network(
      url,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback(),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback(),
    );

    // 提饱和,让模糊后的封面更「透亮」。
    image = ColorFiltered(colorFilter: ColorFilter.matrix(_saturation(1.25)), child: image);

    final sigma = settings.blurSigma;
    if (sigma <= 0.5) return image;

    // 放大 1.3 倍,避免模糊后在边缘露出透明区。
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: Transform.scale(scale: 1.3, child: image),
    );
  }

  /// 饱和度增强矩阵。
  List<double> _saturation(double s) => <double>[
        0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
        0, 0, 0, 1, 0,
      ];
}

/// 第②层:暗色渐变,浓度由 glassTint 控制,保证文字对比度。
class _TintLayer extends StatelessWidget {
  const _TintLayer({required this.settings});

  final DesktopLyricsSettings settings;

  @override
  Widget build(BuildContext context) {
    final a = settings.glassTint / 100;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.45, 1.0],
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.03),
            Colors.black.withValues(alpha: 0.18 + 0.50 * a),
          ],
        ),
      ),
    );
  }
}

/// 第④层:左上高光 + 1px 内描边,玻璃「折射感」来源。
class _HighlightLayer extends StatelessWidget {
  const _HighlightLayer({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.center,
            colors: [
              Colors.white.withValues(alpha: 0.10),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

/// 第③层:确定性噪点 —— 固定种子生成归一化坐标,绘制时才按尺寸缩放,
/// 因此窗口尺寸变化无需重新生成,painter 可保持 const 且不重绘。
class _NoisePainter extends CustomPainter {
  const _NoisePainter();

  static final Float32List _points = _buildPoints();

  static Float32List _buildPoints() {
    final rng = math.Random(20260911);
    const count = 2600;
    final values = Float32List(count * 2);
    for (var i = 0; i < count; i++) {
      values[i * 2] = rng.nextDouble();
      values[i * 2 + 1] = rng.nextDouble();
    }
    return values;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scaled = Float32List(_points.length);
    for (var i = 0; i < _points.length; i += 2) {
      scaled[i] = _points[i] * size.width;
      scaled[i + 1] = _points[i + 1] * size.height;
    }
    canvas.drawPoints(
      ui.PointMode.points,
      scaled,
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/ui/desktop_lyrics/lyrics_glass_test.dart`
Expected: PASS(4 个测试全绿)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/desktop_lyrics/lyrics_glass.dart test/ui/desktop_lyrics/lyrics_glass_test.dart
git commit -m "feat(desktop-lyrics): layered glass card with blurred artwork backdrop"
```

---

### Task 7: 通道协议扩展(样式下行 + 改动上行)

**Files:**
- Modify: `lib/ui/desktop_lyrics/lyrics_window.dart`(只加通道常量,本任务不重写 UI)
- Modify: `lib/ui/desktop_lyrics/desktop_lyrics_service.dart`

**Interfaces:**
- Consumes: `DesktopLyricsSettings`(Task 3)
- Produces(常量定义在 `lyrics_window.dart`):
  - `kLyricsStyleMethod = 'style'`(主→浮窗:推送外观)
  - `kLyricsUpChannelName = 'musicx_desktop_lyrics_up'`、`kLyricsStyleUpMethod = 'styleChanged'`(浮窗→主:回传改动)
  - `push` 载荷新增 `'artwork': String?`
- Produces(`desktop_lyrics_service.dart`):
  - `static Future<void> pushStyle(DesktopLyricsSettings settings)`(同时缓存,`open()` 成功后自动补推一次)
  - `static Future<void> setUpStyleHandler(Future<void> Function(DesktopLyricsSettings) onStyle)`

- [ ] **Step 1: 在 `lyrics_window.dart` 现有常量区追加**

```dart
/// 主窗口 → 歌词窗口:推送外观设置(字号/颜色/玻璃参数)。
const kLyricsStyleMethod = 'style';

/// 浮窗 → 主窗口通道(unidirectional,handler = 主窗口)。
/// desktop_multi_window 的 unidirectional 通道只允许一个引擎注册 handler,
/// 因此反向通信必须独立建通道,不能复用 [kLyricsChannelName]。
const kLyricsUpChannelName = 'musicx_desktop_lyrics_up';

/// 浮窗 → 主窗口:回传工具条改动(主窗口负责持久化,保持单一写者)。
const kLyricsStyleUpMethod = 'styleChanged';
```

- [ ] **Step 2: `desktop_lyrics_service.dart` 实现**

文件头新增:

```dart
import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
```

```dart
import 'lyrics_window.dart';
```
(已有)

类内新增:

```dart
  /// 浮窗 → 主窗口(工具条改动回传,主窗口持久化)。
  static const WindowMethodChannel _upChannel = WindowMethodChannel(
    kLyricsUpChannelName,
    mode: ChannelMode.unidirectional,
  );

  /// 最近一次推送的外观,浮窗打开成功后补推,避免默认样式闪现。
  static DesktopLyricsSettings? _lastStyle;

  /// 注册上行 handler:浮窗工具条改动回传主窗口。主窗口启动时调用一次。
  static Future<void> setUpStyleHandler(
    Future<void> Function(DesktopLyricsSettings settings) onStyle,
  ) async {
    if (!supported) return;
    try {
      await _upChannel.setMethodCallHandler((call) async {
        if (call.method == kLyricsStyleUpMethod) {
          final arg = call.arguments;
          if (arg is Map && arg['style'] is Map) {
            await onStyle(
              DesktopLyricsSettings.fromJson(
                Map<String, dynamic>.from(arg['style'] as Map),
              ),
            );
          }
        }
        return null;
      });
    } catch (_) {}
  }

  /// 推送外观设置到浮窗(浮窗未开时仅缓存,待 open 后补推)。
  static Future<void> pushStyle(DesktopLyricsSettings settings) async {
    _lastStyle = settings;
    if (_windowId == null) return;
    try {
      await _channel.invokeMethod(kLyricsStyleMethod, {
        'style': settings.toJson(),
      });
    } catch (_) {}
  }
```

`open()` 末尾(`await controller.show();` 之后)追加:

```dart
    final style = _lastStyle;
    if (style != null) {
      try {
        await _channel.invokeMethod(kLyricsStyleMethod, {
          'style': style.toJson(),
        });
      } catch (_) {}
    }
```

`push()` 增加封面参数并在载荷中带上:

```dart
  static Future<void> push({
    required String current,
    required String next,
    required bool playing,
    required bool hasSong,
    String? artwork,
  }) async {
    if (_windowId == null) return;
    try {
      await _channel.invokeMethod(kLyricsUpdateMethod, {
        'current': current,
        'next': next,
        'playing': playing,
        'hasSong': hasSong,
        'artwork': artwork,
      });
    } catch (_) {}
  }
```

- [ ] **Step 3: 静态检查**

Run: `flutter analyze lib/ui/desktop_lyrics`
Expected: No issues found!(此时 `kLyricsStyleMethod` 等常量已被 service 使用,无 unused 警告)

- [ ] **Step 4: Commit**

```bash
git add lib/ui/desktop_lyrics/lyrics_window.dart lib/ui/desktop_lyrics/desktop_lyrics_service.dart
git commit -m "feat(desktop-lyrics): style down-channel and toolbar up-channel protocol"
```

---

### Task 8: 重写浮窗(应用样式 + 缩放热区 + 悬停工具条 + 几何持久化)

**Files:**
- Modify: `lib/ui/desktop_lyrics/lyrics_window.dart`(整体重写,删除 `_GlassCard`/`_AccentBar`)
- Modify: `pubspec.yaml`(`dependencies` 增加 `screen_retriever: ^0.2.2`)
- Modify: `lib/main.dart`(歌词分支补 `AppPaths.init()` + `ProviderScope`)

**Interfaces:**
- Consumes: Task 3–7 的全部产物
- Produces: `LyricsWindow` widget(签名不变,`main.dart` 无需改动引用);删除 `main.dart` 对旧 `_kAccent` 的任何依赖(本就没有)

- [ ] **Step 1: pubspec 增加直接依赖**

在 `pubspec.yaml` 的 `dependencies:` 里 `desktop_multi_window: ^0.3.1` 附近加:

```yaml
  screen_retriever: ^0.2.2
```

然后 Run: `flutter pub get`
Expected: Got dependencies!

- [ ] **Step 2: `lib/main.dart` 歌词分支**

```dart
  if (isLyricsWindowArguments(windowArguments)) {
    // 浮窗也要能读 settings.json(首帧样式),先初始化数据目录。
    await AppPaths.init();
    runApp(const ProviderScope(child: LyricsWindow()));
    return;
  }
```

- [ ] **Step 3: 重写 `lyrics_window.dart`**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'package:musicx/core/settings/settings_providers.dart';

import 'lyrics_glass.dart';
import 'lyrics_layout.dart';
import 'lyrics_resize.dart';

/// 窗口类型标识(写入 WindowConfiguration.arguments)。
const kLyricsWindowType = 'lyrics';

/// 主窗口 ⇄ 歌词窗口 的跨引擎通道名(unidirectional:歌词窗口注册 handler)。
const kLyricsChannelName = 'musicx_desktop_lyrics';

/// 主窗口 → 歌词窗口:更新当前歌词。
const kLyricsUpdateMethod = 'update';

/// 主窗口 → 歌词窗口:推送外观设置。
const kLyricsStyleMethod = 'style';

/// 浮窗 → 主窗口通道(unidirectional,handler = 主窗口)。
/// unidirectional 通道只允许一个引擎注册 handler,反向通信须独立建通道。
const kLyricsUpChannelName = 'musicx_desktop_lyrics_up';

/// 浮窗 → 主窗口:回传工具条改动(主窗口负责持久化)。
const kLyricsStyleUpMethod = 'styleChanged';

/// 主窗口 → 歌词窗口:关闭浮窗。
const kLyricsCloseMethod = 'close';

/// 浮窗默认尺寸与默认位置(未记录几何时使用)。
const Size kLyricsWindowSize = Size(880, 190);
const Offset kLyricsDefaultPosition = Offset(180, 160);

/// 窗口内边距:既留出投影空间,也是缩放热区所在。
const EdgeInsets kLyricsWindowPadding = EdgeInsets.fromLTRB(18, 14, 18, 22);

/// 缩放热区厚度。
const double kLyricsResizeHotSize = 8;

/// 桌面歌词浮窗:独立窗口 + 无边框 + 置顶 + 透明 + 可拖动 + 可自由缩放。
class LyricsWindow extends StatefulWidget {
  const LyricsWindow({super.key});

  @override
  State<LyricsWindow> createState() => _LyricsWindowState();
}

class _LyricsWindowState extends State<LyricsWindow> {
  static const WindowMethodChannel _channel = WindowMethodChannel(
    kLyricsChannelName,
    mode: ChannelMode.unidirectional,
  );

  static const WindowMethodChannel _upChannel = WindowMethodChannel(
    kLyricsUpChannelName,
    mode: ChannelMode.unidirectional,
  );

  String _current = '';
  String _next = '';
  bool _hasSong = false;
  String? _artwork;

  /// 生效中的外观:首帧取自 settings.json,此后以主窗口推送为准。
  DesktopLyricsSettings _style = const DesktopLyricsSettings();

  bool _hovering = false;
  bool _toolbarVisible = false;
  Timer? _toolbarTimer;
  Timer? _boundsSaveTimer;

  /// 缩放节流:单次在途,新目标覆盖旧目标。
  bool _resizeInFlight = false;
  Rect? _pendingResize;
  Rect? _liveResizeRect;

  @override
  void initState() {
    super.initState();
    _style = ref.read(desktopLyricsSettingsProvider);
    _configureWindow();
    _listenToMain();
  }

  @override
  void dispose() {
    _toolbarTimer?.cancel();
    _boundsSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _configureWindow() async {
    try {
      await windowManager.ensureInitialized();
      final restored = await _restoreBounds();
      const options = WindowOptions(
        size: kLyricsWindowSize,
        backgroundColor: Colors.transparent,
        skipTaskbar: true,
        titleBarStyle: TitleBarStyle.hidden,
        alwaysOnTop: true,
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.setAsFrameless();
        await windowManager.setAlwaysOnTop(true);
        // 自绘投影,关闭系统窗口阴影以免与圆角冲突。
        await windowManager.setHasShadow(false);
        if (restored != null) {
          await windowManager.setBounds(restored);
        } else {
          await windowManager.setPosition(kLyricsDefaultPosition);
        }
        await windowManager.show();
      });
    } catch (_) {}
  }

  /// 还原上次几何,并夹取到主屏工作区内(防止换显示器后窗口跑到屏幕外)。
  Future<Rect?> _restoreBounds() async {
    final saved = _style.bounds;
    if (saved == null || saved.width <= 0 || saved.height <= 0) return null;
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final origin = display.visiblePosition ?? Offset.zero;
      final visible = display.visibleSize ?? display.size;
      return clampRectToWorkArea(
        saved,
        Rect.fromLTWH(origin.dx, origin.dy, visible.width, visible.height),
      );
    } catch (_) {
      return saved;
    }
  }

  Future<void> _listenToMain() async {
    try {
      await _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case kLyricsUpdateMethod:
            final arg = call.arguments;
            if (arg is Map && mounted) {
              setState(() {
                _current = (arg['current'] as String?) ?? '';
                _next = (arg['next'] as String?) ?? '';
                _hasSong = (arg['hasSong'] as bool?) ?? false;
                _artwork = arg['artwork'] as String?;
              });
            }
          case kLyricsStyleMethod:
            final arg = call.arguments;
            if (arg is Map && arg['style'] is Map && mounted) {
              setState(() {
                _style = DesktopLyricsSettings.fromJson(
                  Map<String, dynamic>.from(arg['style'] as Map),
                );
              });
            }
          case kLyricsCloseMethod:
            try {
              await windowManager.close();
            } catch (_) {}
        }
        return null;
      });
    } catch (_) {}
  }

  // ── 拖动 ──────────────────────────────────────────────────────────

  void _startDrag() {
    try {
      windowManager.startDragging();
    } catch (_) {}
  }

  // ── 缩放 ──────────────────────────────────────────────────────────

  void _onResizeStart(ResizeEdge edge) {
    try {
      windowManager.getBounds().then((r) => _liveResizeRect = r);
    } catch (_) {}
  }

  void _onResizeUpdate(ResizeEdge edge, DragUpdateDetails d) {
    final base = _liveResizeRect;
    if (base == null) return; // 起始几何未取回前丢弃(几毫秒内)
    final next = resizeRect(current: base, edge: edge, delta: d.delta);
    _liveResizeRect = next;
    _applyBounds(next);
  }

  Future<void> _applyBounds(Rect rect) async {
    if (_resizeInFlight) {
      _pendingResize = rect;
      return;
    }
    _resizeInFlight = true;
    try {
      await windowManager.setBounds(rect);
    } catch (_) {}
    _resizeInFlight = false;
    final pending = _pendingResize;
    if (pending != null) {
      _pendingResize = null;
      await _applyBounds(pending);
    }
  }

  void _onResizeEnd() {
    _liveResizeRect = null;
    _scheduleBoundsSave();
  }

  /// 松手后 debounce 落盘窗口几何。
  void _scheduleBoundsSave() {
    _boundsSaveTimer?.cancel();
    _boundsSaveTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final b = await windowManager.getBounds();
        _sendStyleUp(_style.copyWith(bounds: b));
      } catch (_) {}
    });
  }

  // ── 工具条 ────────────────────────────────────────────────────────

  void _onEnter() {
    _hovering = true;
    _toolbarTimer?.cancel();
    _toolbarTimer = Timer(const Duration(milliseconds: 180), () {
      if (_hovering && mounted) setState(() => _toolbarVisible = true);
    });
  }

  void _onExit() {
    _hovering = false;
    _toolbarTimer?.cancel();
    _toolbarTimer = Timer(const Duration(milliseconds: 400), () {
      if (!_hovering && mounted) setState(() => _toolbarVisible = false);
    });
  }

  /// 应用工具条改动:本地立即生效 + 回传主窗口持久化。
  void _applyStyleChange(DesktopLyricsSettings next) {
    setState(() => _style = next);
    _sendStyleUp(next);
  }

  void _sendStyleUp(DesktopLyricsSettings next) {
    try {
      _upChannel.invokeMethod(kLyricsStyleUpMethod, {'style': next.toJson()});
    } catch (_) {}
  }

  Future<void> _resetSize() async {
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final origin = display.visiblePosition ?? Offset.zero;
      final visible = display.visibleSize ?? display.size;
      final rect = Rect.fromCenter(
        center: Offset(
          origin.dx + visible.width / 2,
          origin.dy + visible.height / 2,
        ),
        width: kLyricsWindowSize.width,
        height: kLyricsWindowSize.height,
      );
      _applyBounds(clampRectToWorkArea(rect,
          Rect.fromLTWH(origin.dx, origin.dy, visible.width, visible.height)));
    } catch (_) {}
    _applyStyleChange(_style.copyWith(clearBounds: true));
  }

  Future<void> _close() async {
    try {
      await windowManager.close();
    } catch (_) {}
  }

  // ── UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final line = _hasSong
        ? (_current.isEmpty ? '♪ 前奏…' : _current)
        : 'MusicX · 桌面歌词';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: MouseRegion(
          onEnter: (_) => _onEnter(),
          onExit: (_) => _onExit(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final windowSize = Size(constraints.maxWidth, constraints.maxHeight);
              final layout = resolveLyricsLayout(
                windowSize: windowSize,
                settings: _style,
                current: line,
                next: _next,
              );
              return Stack(
                children: [
                  // 1) 卡片 + 窗口拖动
                  Positioned.fill(
                    child: Padding(
                      padding: kLyricsWindowPadding,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => _startDrag(),
                        onPanEnd: (_) => _scheduleBoundsSave(),
                        child: LyricsGlassCard(
                          settings: _style,
                          artworkUrl: _artwork,
                          radius: layout.cardRadius,
                          child: Padding(
                            padding: layout.padding,
                            child: _LyricsContent(
                              layout: layout,
                              settings: _style,
                              current: line,
                              next: _next,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 2) 四边 + 四角缩放热区
                  ..._buildResizeHandles(),
                  // 3) 悬停工具条
                  if (_toolbarVisible)
                    Positioned(
                      top: 6,
                      right: 26,
                      child: _Toolbar(
                        settings: _style,
                        onFontSizeDelta: (d) => _applyStyleChange(
                          _style.copyWith(fontSize: _style.fontSize + d),
                        ),
                        onColor: (c) => _applyStyleChange(
                          _style.copyWith(textColor: c),
                        ),
                        onToggleNext: () => _applyStyleChange(
                          _style.copyWith(showNext: !_style.showNext),
                        ),
                        onResetSize: _resetSize,
                        onClose: _close,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 四边 + 四角热区:透明、带对应光标,拖拽时调用原生 setBounds。
  List<Widget> _buildResizeHandles() {
    const t = kLyricsResizeHotSize;

    Widget handle({
      required ResizeEdge edge,
      double? top,
      double? left,
      double? right,
      double? bottom,
      double? width,
      double? height,
      required SystemMouseCursor cursor,
    }) {
      return Positioned(
        top: top,
        left: left,
        right: right,
        bottom: bottom,
        width: width,
        height: height,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _onResizeStart(edge),
            onPanUpdate: (d) => _onResizeUpdate(edge, d),
            onPanEnd: (_) => _onResizeEnd(),
          ),
        ),
      );
    }

    return [
      handle(
        edge: ResizeEdge.top,
        top: 0, left: t, right: t, height: t,
        cursor: SystemMouseCursors.resizeUpDown,
      ),
      handle(
        edge: ResizeEdge.bottom,
        bottom: 0, left: t, right: t, height: t,
        cursor: SystemMouseCursors.resizeUpDown,
      ),
      handle(
        edge: ResizeEdge.left,
        left: 0, top: t, bottom: t, width: t,
        cursor: SystemMouseCursors.resizeLeftRight,
      ),
      handle(
        edge: ResizeEdge.right,
        right: 0, top: t, bottom: t, width: t,
        cursor: SystemMouseCursors.resizeLeftRight,
      ),
      handle(
        edge: ResizeEdge.topLeft,
        top: 0, left: 0, width: t, height: t,
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
      ),
      handle(
        edge: ResizeEdge.bottomRight,
        bottom: 0, right: 0, width: t, height: t,
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
      ),
      handle(
        edge: ResizeEdge.topRight,
        top: 0, right: 0, width: t, height: t,
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
      ),
      handle(
        edge: ResizeEdge.bottomLeft,
        bottom: 0, left: 0, width: t, height: t,
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
      ),
    ];
  }
}

/// 歌词内容:左侧律动竖条 + 当前句(与下一句,纵向或横向)。
class _LyricsContent extends StatelessWidget {
  const _LyricsContent({
    required this.layout,
    required this.settings,
    required this.current,
    required this.next,
  });

  final LyricsLayout layout;
  final DesktopLyricsSettings settings;
  final String current;
  final String next;

  @override
  Widget build(BuildContext context) {
    final color = settings.textColor;
    final bar = Container(
      width: layout.accentBarWidth,
      height: layout.fontSize * 1.6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(layout.accentBarWidth / 2),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withValues(alpha: 0.2)],
        ),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 14),
        ],
      ),
    );
    final gap = 22 * (layout.padding.horizontal / 56);

    final currentText = Text(
      current,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: layout.fontSize,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: 0.5,
        shadows: [
          Shadow(color: color.withValues(alpha: 0.4), blurRadius: 18),
        ],
      ),
    );
    final nextText = Text(
      next,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: settings.nextColor,
        fontSize: layout.nextFontSize,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: 0.3,
      ),
    );

    if (layout.direction == Axis.horizontal) {
      return Row(
        children: [
          bar,
          SizedBox(width: gap),
          Flexible(child: currentText),
          SizedBox(width: gap * 0.8),
          Flexible(child: nextText),
        ],
      );
    }

    return Row(
      children: [
        bar,
        SizedBox(width: gap),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              currentText,
              if (layout.showNext) ...[
                const SizedBox(height: 8),
                nextText,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 悬停工具条:半透明玻璃样式,字号/颜色/下一句/重置尺寸/关闭。
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.settings,
    required this.onFontSizeDelta,
    required this.onColor,
    required this.onToggleNext,
    required this.onResetSize,
    required this.onClose,
  });

  final DesktopLyricsSettings settings;
  final ValueChanged<double> onFontSizeDelta;
  final ValueChanged<Color> onColor;
  final VoidCallback onToggleNext;
  final VoidCallback onResetSize;
  final VoidCallback onClose;

  static const _quickColors = <Color>[
    Color(0xFFFF5A76),
    Color(0xFFFFFFFF),
    Color(0xFF8AD4FF),
    Color(0xFFFFD76A),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarButton(
              icon: Icons.remove_rounded,
              tooltip: '缩小字号',
              onTap: () => onFontSizeDelta(-2),
            ),
            _ToolbarButton(
              icon: Icons.add_rounded,
              tooltip: '放大字号',
              onTap: () => onFontSizeDelta(2),
            ),
            const SizedBox(width: 4),
            for (final c in _quickColors)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  onTap: () => onColor(c),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: settings.textColor == c
                          ? Border.all(color: Colors.white, width: 2)
                          : Border.all(color: Colors.white24),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            _ToolbarButton(
              icon: settings.showNext
                  ? Icons.view_agenda_rounded
                  : Icons.view_day_rounded,
              tooltip: settings.showNext ? '隐藏下一句' : '显示下一句',
              onTap: onToggleNext,
            ),
            _ToolbarButton(
              icon: Icons.settings_backup_restore_rounded,
              tooltip: '重置尺寸与位置',
              onTap: onResetSize,
            ),
            _ToolbarButton(
              icon: Icons.close_rounded,
              tooltip: '关闭桌面歌词',
              onTap: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.9)),
        ),
      ),
    );
  }
}

/// 解析窗口参数,判断是否歌词窗口。
bool isLyricsWindowArguments(String? arguments) {
  if (arguments == null || arguments.isEmpty) return false;
  try {
    final map = jsonDecode(arguments) as Map<String, dynamic>;
    return map['type'] == kLyricsWindowType;
  } catch (_) {
    return false;
  }
}
```

注意:
- `_LyricsWindowState` 需继承 `ConsumerState<LyricsWindow>`(因为 `initState` 里 `ref.read(desktopLyricsSettingsProvider)`),相应 `createState` 返回类型改为 `_LyricsWindowState`,文件头加 `import 'package:flutter_riverpod/flutter_riverpod.dart';`。上面代码里已按 `ref.read` 写,别忘了改父类。
- `dart:ui show Size` 与 `Size` 的导入可省略(`material.dart` 已导出),若 analyze 提示 unused import 就删掉该 import。
- 旧代码里的 `_kAccent`、`_GlassCard`、`_AccentBar` 全部删除,不再保留。

- [ ] **Step 4: 静态检查**

Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 5: 全量测试(确认没破坏已有功能)**

Run: `flutter test`
Expected: 全绿

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart lib/ui/desktop_lyrics/lyrics_window.dart
git commit -m "feat(desktop-lyrics): resizable frameless window with hover toolbar and adaptive layout"
```

---

### Task 9: 设置页「桌面歌词」配置区 + 实时预览

**Files:**
- Create: `lib/ui/desktop_lyrics/lyrics_settings_section.dart`
- Modify: `lib/ui/plugins/plugin_page.dart`(`_sectionContent` 的 `appearance` 分支)
- Test: `test/ui/desktop_lyrics/lyrics_settings_section_test.dart`

**Interfaces:**
- Consumes: `LyricsGlassCard`(Task 6)、`desktopLyricsSettingsProvider`(Task 3)、`DesktopLyricsService`(Task 7)
- Produces: `class LyricsSettingsSection extends ConsumerWidget` —— 无参数;调用方负责在 `DesktopLyricsService.supported == false` 时不渲染

- [ ] **Step 1: 写失败测试**

```dart
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
    expect(content.contains('"showNext": false'), isTrue);
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/desktop_lyrics/lyrics_settings_section_test.dart`
Expected: FAIL(`lyrics_settings_section.dart` 不存在)

- [ ] **Step 3: 实现**

```dart
// lib/ui/desktop_lyrics/lyrics_settings_section.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'package:musicx/ui/desktop_lyrics/desktop_lyrics_service.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_glass.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_layout.dart';

/// 设置页「桌面歌词」配置区:实时预览 + 颜色/字号/玻璃参数。
/// 改动即写 provider(持久化)并经 [DesktopLyricsService] 推送到浮窗。
/// 仅桌面平台渲染 —— 调用方需判断 [DesktopLyricsService.supported]。
class LyricsSettingsSection extends ConsumerWidget {
  const LyricsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(desktopLyricsSettingsProvider);
    final notifier = ref.read(desktopLyricsSettingsProvider.notifier);

    void change(DesktopLyricsSettings next) {
      notifier.update(next);          // 持久化
      DesktopLyricsService.pushStyle(next); // 实时推送到已打开的浮窗
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreviewCard(settings: settings),
        const SizedBox(height: 12),
        _ColorRow(
          selected: settings.textColor,
          onColor: (c) => change(settings.copyWith(textColor: c)),
        ),
        _SliderRow(
          label: '字号',
          value: settings.fontSize,
          min: DesktopLyricsSettings.minFontSize,
          max: DesktopLyricsSettings.maxFontSize,
          format: (v) => '${v.round()} px',
          onChanged: (v) => change(settings.copyWith(fontSize: v)),
        ),
        _SliderRow(
          label: '玻璃浓度',
          value: settings.glassTint.toDouble(),
          min: DesktopLyricsSettings.minGlassTint.toDouble(),
          max: DesktopLyricsSettings.maxGlassTint.toDouble(),
          format: (v) => '${v.round()}',
          onChanged: (v) => change(settings.copyWith(glassTint: v.round())),
        ),
        _SliderRow(
          label: '模糊强度',
          value: settings.blurSigma,
          min: DesktopLyricsSettings.minBlurSigma,
          max: DesktopLyricsSettings.maxBlurSigma,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) => change(settings.copyWith(blurSigma: v)),
        ),
        _SliderRow(
          label: '圆角',
          value: settings.cornerRadius,
          min: DesktopLyricsSettings.minCornerRadius,
          max: DesktopLyricsSettings.maxCornerRadius,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) => change(settings.copyWith(cornerRadius: v)),
        ),
        _SwitchRow(
          label: '字号随窗口缩放',
          value: settings.autoScale,
          onChanged: (v) => change(settings.copyWith(autoScale: v)),
        ),
        _SwitchRow(
          label: '显示下一句',
          value: settings.showNext,
          onChanged: (v) => change(settings.copyWith(showNext: v)),
        ),
        _SwitchRow(
          label: '用专辑封面做玻璃背景',
          value: settings.showArtwork,
          onChanged: (v) => change(settings.copyWith(showArtwork: v)),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => change(const DesktopLyricsSettings()),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('恢复默认'),
          ),
        ),
      ],
    );
  }
}

/// 实时预览:与浮窗同一套玻璃渲染,按 190 高度的基准比例取圆角。
class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.settings});

  final DesktopLyricsSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = resolveLyricsLayout(
      windowSize: const Size(880, 190),
      settings: settings,
      current: '等到树叶都泛了黄',
      next: '等到眼里全是伤',
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 130,
        width: double.infinity,
        child: LyricsGlassCard(
          settings: settings,
          artworkUrl: null, // 预览不发起网络请求,统一走兜底渐变
          radius: layout.cardRadius,
          child: Padding(
            padding: layout.padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '等到树叶都泛了黄',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: settings.textColor,
                    fontSize: math.min(layout.fontSize, 40),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '等到眼里全是伤',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: settings.nextColor,
                    fontSize: math.min(layout.nextFontSize, 22),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 颜色行:预设色板 + 自定义(HSV 三滑杆)。
class _ColorRow extends StatefulWidget {
  const _ColorRow({required this.selected, required this.onColor});

  final Color selected;
  final ValueChanged<Color> onColor;

  @override
  State<_ColorRow> createState() => _ColorRowState();
}

class _ColorRowState extends State<_ColorRow> {
  static const _presets = <Color>[
    Color(0xFFFF5A76),
    Color(0xFFFFFFFF),
    Color(0xFF8AD4FF),
    Color(0xFFFFD76A),
    Color(0xFF9BFF9B),
    Color(0xFFC79BFF),
    Color(0xFFFFB27A),
    Color(0xFF7A8CFF),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text('歌词颜色',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          for (final c in _presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => widget.onColor(c),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: widget.selected.toARGB32() == c.toARGB32()
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2.5)
                        : Border.all(color: Colors.black12),
                  ),
                ),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: () async {
              final c = await showDialog<Color>(
                context: context,
                builder: (_) => _HsvColorDialog(initial: widget.selected),
              );
              if (c != null) widget.onColor(c);
            },
            child: const Text('自定义'),
          ),
        ],
      ),
    );
  }
}

/// 极简 HSV 取色器:三个滑杆 + 预览,不引第三方依赖。
class _HsvColorDialog extends StatefulWidget {
  const _HsvColorDialog({required this.initial});

  final Color initial;

  @override
  State<_HsvColorDialog> createState() => _HsvColorDialogState();
}

class _HsvColorDialogState extends State<_HsvColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: const Text('自定义颜色'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(height: 12),
          _hsvSlider(
            label: '色相',
            value: _hsv.hue,
            max: 360,
            onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
          ),
          _hsvSlider(
            label: '饱和度',
            value: _hsv.saturation,
            max: 1,
            onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
          ),
          _hsvSlider(
            label: '明度',
            value: _hsv.value,
            max: 1,
            onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(color),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _hsvSlider({
    required String label,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 52, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max),
            min: 0,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            label: format(value),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            format(value),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
```

- [ ] **Step 4: 接入设置页** —— `lib/ui/plugins/plugin_page.dart` 的 `_sectionContent` 里 `appearance` 分支改为:

```dart
      case _SettingsSection.appearance:
        return [
          _SettingsGroup(
            title: '外观',
            children: [
              _AppearanceSection(),
            ],
          ),
          if (DesktopLyricsService.supported) ...[
            const SizedBox(height: 16),
            _SettingsGroup(
              title: '桌面歌词',
              children: [
                LyricsSettingsSection(),
              ],
            ),
          ],
        ];
```

文件头新增 import:

```dart
import 'package:musicx/ui/desktop_lyrics/desktop_lyrics_service.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_settings_section.dart';
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/ui/desktop_lyrics/lyrics_settings_section_test.dart`
Expected: PASS(3 个测试全绿)

- [ ] **Step 6: Commit**

```bash
git add lib/ui/desktop_lyrics/lyrics_settings_section.dart lib/ui/plugins/plugin_page.dart test/ui/desktop_lyrics/lyrics_settings_section_test.dart
git commit -m "feat(desktop-lyrics): settings section with live glass preview"
```

---

### Task 10: 主窗口接线(推送 / 上行回写 / 封面)

**Files:**
- Modify: `lib/ui/home_shell.dart`

**Interfaces:**
- Consumes: Task 3(`desktopLyricsSettingsProvider`)、Task 7(`setUpStyleHandler` / `pushStyle` / `artwork` 参数)
- Produces: 完整数据流闭环 —— 设置改动→浮窗;浮窗工具条改动→持久化;歌词与封面每 250ms 推送

- [ ] **Step 1: 修改 `home_shell.dart`**

a) import 增加:

```dart
import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
```

b) `initState()` 里,`_lyricsTimer` 初始化之后追加:

```dart
    // 浮窗工具条改动回传:写回 provider 持久化(主窗口是唯一写者)。
    if (DesktopLyricsService.supported) {
      DesktopLyricsService.setUpStyleHandler((settings) {
        ref.read(desktopLyricsSettingsProvider.notifier).update(settings);
      });
      // 先缓存当前样式,浮窗打开时由 service 补推,避免默认样式闪现。
      DesktopLyricsService.pushStyle(ref.read(desktopLyricsSettingsProvider));
    }
```

c) `build()` 里 `return ...` 之前(ConsumerStateful 的 build 开头)追加:

```dart
    // 设置改动实时推送到已打开的浮窗。
    ref.listen<DesktopLyricsSettings>(desktopLyricsSettingsProvider,
        (_, next) {
      DesktopLyricsService.pushStyle(next);
    });
```

d) `_pushLyrics()` 里 `await DesktopLyricsService.push(...)` 增加 `artwork`:

```dart
      await DesktopLyricsService.push(
        current: current,
        next: next,
        playing: state.isPlaying,
        hasSong: state.current != null,
        artwork: state.current?.artwork,
      );
```

- [ ] **Step 2: 静态检查 + 全量测试**

Run: `flutter analyze && flutter test`
Expected: No issues found! + 全部测试通过

- [ ] **Step 3: Commit**

```bash
git add lib/ui/home_shell.dart
git commit -m "feat(desktop-lyrics): wire settings sync and artwork push in home shell"
```

---

### Task 11: 全量验证(分析 / 测试 / 构建 / 实机截图)

**Files:**
- 无新改动;只验证,如发现问题回到对应任务修复

**Interfaces:**
- Consumes: 全部前序任务
- Produces: 验证证据(analyze 输出、test 汇总、截图文件)

- [ ] **Step 1: 静态分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: All tests passed!(含新增 5 个测试文件与既有全部测试)

- [ ] **Step 3: 构建 macOS Debug**

Run: `flutter build macos --debug`
Expected: `✓ Built build/macos/Build/Products/Debug/musicx.app`

- [ ] **Step 4: 实机启动并截图验证**

```bash
open build/macos/Build/Products/Debug/musicx.app
```

然后在 App 里打开桌面歌词浮窗(播放页歌词按钮),用 `screencapture` 截浮窗区域确认:
- 无封面/未播放时:卡片是柔光斑玻璃(tint/噪点/高光/描边可见),不是旧版那种生硬深色卡片;
- 拖动四角/四边可自由缩放,光标形态正确,松手后重启 App 几何保持;
- 拉矮窗口只显示当前句、字号变小;拉高字号变大;
- 设置页「外观 → 桌面歌词」改字号/颜色,浮窗立即变化。

截图命令示例(浮窗位置不确定时全屏截):

```bash
screencapture -x /tmp/lyrics_v2_check.png
```

- [ ] **Step 5: 汇报**

把截图与验证结论交给用户 review;如用户确认通过,再按其指示走发版(bump 版本号 + tag 触发 CI)。

---

## Self-Review 记录

**Spec 覆盖检查**(spec 第 N 节 → 任务):
- §3 玻璃分层 → Task 6;§3 性能(RepaintBoundary/sigma 不随尺寸放大)→ Task 6(`_NoisePainter` const + blur sigma 只来自设置)
- §4 自适应规则(1–5 条)→ Task 4
- §5.1 拖动 → Task 8;§5.2 缩放热区/节流/夹取 → Task 5 + Task 8;§5.3 几何持久化与工作区夹取 → Task 5 + Task 8;§5.4 关闭 → Task 8(`_Toolbar` 关闭按钮)
- §6.1 设置页分组/预览/恢复默认/Android 隐藏 → Task 9(`DesktopLyricsService.supported` 判断)
- §6.2 悬停工具条 → Task 8(实现为「悬停 180ms 淡入 / 离开 400ms 淡出」,比 spec 的「1.5s 无操作淡出」更不易误伤正在拖动滑杆的场景 —— 有意偏离,已在此说明)
- §6.3 数据流(下行/上行/打开补推/`AppPaths.init`)→ Task 7 + Task 8 + Task 10
- §7.1 SettingsStore + 主题迁移 → Task 1 + Task 2;§7.2 模型与默认值 → Task 3
- §9 验收 1–10 → Task 11 逐项验证

**占位符扫描**:无 TBD/TODO;所有代码步骤均给出完整代码。

**类型一致性**:`resolveLyricsLayout` / `LyricsLayout` / `resizeRect` / `ResizeEdge` / `LyricsGlassCard(settings, artworkUrl, radius, child)` / `pushStyle` / `setUpStyleHandler` / `kLyricsStyleMethod` 在各任务间签名一致(Task 4/5/6 定义,Task 8/9/10 按此消费)。
