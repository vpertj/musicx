# MusicX UI 重构「月光极简」实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 MusicX 重构为「月光极简」视觉体系:黑白灰骨架 + 品牌红点缀,三 tab 导航(发现/我的/设置),播放页改为单封面沉浸 + 底部干净控制区,浅色为主(默认)可手动切深色并持久化。

**Architecture:** 以 `AppTheme` 语义色 Token 为地基(light/dark 两套),新增 `themePreferenceProvider` 持久化主题偏好,根 Widget 依据它选择 `themeMode`;`home_shell` 改为三 tab;`player_page` 重排布局;所有用到紫粉渐变的组件替换为品牌红单色。核心播放/搜索/下载数据逻辑不动。

**Tech Stack:** Flutter + flutter_riverpod(Notifier/Provider);本地持久化沿用 `~/.musicx/*.json` 惯例(同 `library_controller.dart`)。

## Global Constraints

- 配色全部通过语义 Token 引用,禁止散落硬编码紫粉(`0xFF8B5CF6`/`0xFFEC4899`/`0xFFF59E0B`)。
- UI 元素(播放键/进度条/Logo/徽标)移除渐变,统一用品牌红 `accent` 单色;封面自身的自然色彩保留。
- 导航固定为三 tab:发现 / 我的 / 设置;播放页不占 tab。
- `themeMode` 不再硬编码 `dark`,改由 `themePreferenceProvider` 决定(浅色默认)。
- 保留现有 `SongTile`/`ArtworkView` 等组件的公开构造函数签名(仅改内部样式),避免破坏调用方。
- 每任务结束跑 `flutter test` + `flutter analyze` 确认无回归再提交。
- `flutter test` 需复制 SDK 到可写路径运行(本机惯例):`cp -R /Users/tianjun/.pub-cache/. $HOME/.pub-cache/` 后用 `/tmp/flutter_sdk/bin/flutter test`。

---

### Task 1: 重写 AppTheme 为语义色 Token(light/dark)

**Files:**
- Modify: `lib/theme/app_theme.dart`(整文件重写)

**Interfaces:**
- Consumes: 无(依赖 Flutter Material)。
- Produces: `AppTheme.bg`/`surface`/`surfaceHi`/`text`/`textMuted`/`divider`/`accent`/`accentSoft`(均为 `Color` 静态字段,分 light/dark 两套);`AppTheme.light`/`AppTheme.dark`(两个 `ThemeData` getter)。后续所有任务依赖这些。

- [ ] **Step 1: 替换 app_theme.dart 全部内容**

```dart
import 'package:flutter/material.dart';

/// MusicX 主题:极简黑白灰骨架 + 品牌红点缀(方案A 月光极简)。
/// ColorScheme 建议直接用 primary=accent,保证组件默认色聚焦单一品牌色。
class AppTheme {
  AppTheme._();

  // ---- 品牌色(唯一彩色点缀)----
  static const Color accentLight = Color(0xFFFA3B4D);
  static const Color accentDark = Color(0xFFFF4559);
  static const Color accentSoftLight = Color(0xFFFFEDEE);
  static const Color accentSoftDark = Color(0xFF3A2225);

  // ---- 浅色 Token ----
  static const Color bgLight = Color(0xFFFAFBFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceHiLight = Color(0xFFF2F3F5);
  static const Color textLight = Color(0xFF1A1C1E);
  static const Color textMutedLight = Color(0xFF8A8F98);
  static const Color dividerLight = Color(0xFFE7E9EC);

  // ---- 深色 Token ----
  static const Color bgDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color surfaceHiDark = Color(0xFF242629);
  static const Color textDark = Color(0xFFF3F4F6);
  static const Color textMutedDark = Color(0xFF9AA1AB);
  static const Color dividerDark = Color(0xFF2C2F33);

  static ThemeData get light => _build(
        brightness: Brightness.light,
        bg: bgLight,
        surface: surfaceLight,
        surfaceHi: surfaceHiLight,
        text: textLight,
        textMuted: textMutedLight,
        divider: dividerLight,
        accent: accentLight,
        accentSoft: accentSoftLight,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        bg: bgDark,
        surface: surfaceDark,
        surfaceHi: surfaceHiDark,
        text: textDark,
        textMuted: textMutedDark,
        divider: dividerDark,
        accent: accentDark,
        accentSoft: accentSoftDark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surfaceHi,
    required Color text,
    required Color textMuted,
    required Color divider,
    required Color accent,
    required Color accentSoft,
  }) {
    final scheme =
        ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
            .copyWith(
              primary: accent,
              onPrimary: Colors.white,
              secondary: accent,
              onSurface: text,
              surface: surface,
              surfaceContainer: surfaceHi,
              surfaceContainerLow: brightness == Brightness.light
                  ? const Color(0xFFF4F5F7)
                  : const Color(0xFF1A1A1A),
              surfaceContainerLowest: bg,
              outline: divider,
              outlineVariant: divider,
              error: brightness == Brightness.light
                  ? const Color(0xFFDC3D52)
                  : const Color(0xFFFF6B81),
            );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: text,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
        ),
        iconTheme: IconThemeData(color: text),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface.withValues(alpha: .95),
        indicatorColor: accentSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? accent : textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? accent : textMuted, size: 23);
        }),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHi,
        hintStyle: TextStyle(color: textMuted),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHi,
        side: BorderSide.none,
        labelStyle: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: text),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHi,
        contentTextStyle: TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: textMuted.withValues(alpha: .5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceHi,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(color: text, fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: text.withValues(alpha: .8), fontSize: 14, height: 1.5),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(iconColor: textMuted, textColor: text),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: surfaceHi,
      ),
      scaffoldBackgroundColor: bg,
    );
  }
}
```

- [ ] **Step 2: 编译验证**

Run:
```bash
cd /Users/tianjun/Desktop/prog/musicx && TMPD=$(mktemp -d) && mkdir -p "$TMPD/h/.pub-cache" && cp -R /Users/tianjun/.pub-cache/. "$TMPD/h/.pub-cache/" 2>/dev/null && HOME="$TMPD/h" CI=true FLUTTER_SUPPRESS_ANALYTICS=true /tmp/flutter_sdk/bin/flutter analyze
```
Expected: 仍会有其它文件引用 `AppTheme.pink`/`violet`/`accentGradient`/`softGradient`/`orange` 的报错(Task 6 统一替换),但 `app_theme.dart` 本身无语法错误。若报错仅限其他文件引用已删除的成员,属预期,继续。

- [ ] **Step 3: Commit**

```bash
git add lib/theme/app_theme.dart
git commit -m "feat(ui): rewrite AppTheme as semantic color tokens (月光极简)"
```

---

### Task 2: 新增主题偏好 provider(持久化)

**Files:**
- Modify: `lib/core/settings/settings_providers.dart`

**Interfaces:**
- Consumes: `flutter_riverpod`;`dart:io`/`dart:convert`。
- Produces: `themePreferenceProvider`(`NotifierProvider<ThemePreferenceNotifier, ThemeMode>`)。后续 Task 3 与 Task 7 依赖。

- [ ] **Step 1: 修改 settings_providers.dart**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前搜索音源插件名;null 表示「自动」。
class SearchSourceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? source) => state = source;
}

final searchSourceProvider = NotifierProvider<SearchSourceNotifier, String?>(
  SearchSourceNotifier.new,
);

/// 主题偏好:light / dark,浅色为主(默认),持久化到 ~/.musicx/settings.json。
class ThemePreferenceNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // 启动时读取持久化偏好,缺省浅色。
    final file = _settingsFile();
    try {
      if (file.existsSync()) {
        final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final v = map['themeMode'] as String?;
        if (v == 'dark') return ThemeMode.dark;
      }
    } catch (_) {}
    return ThemeMode.light;
  }

  void setDark(bool dark) {
    state = dark ? ThemeMode.dark : ThemeMode.light;
    _persist();
  }

  void toggle() => setDark(state == ThemeMode.light);

  void _persist() {
    try {
      final file = _settingsFile();
      final map = <String, dynamic>{'themeMode': state == ThemeMode.dark ? 'dark' : 'light'};
      file.writeAsStringSync(jsonEncode(map), flush: true);
    } catch (_) {
      // 持久化失败不阻断切换
    }
  }

  static File _settingsFile() {
    final home = Platform.environment['HOME'];
    final dir = Directory(home != null && home.isNotEmpty
        ? '$home/.musicx'
        : '${Directory.systemTemp.path}/musicx_data');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/settings.json');
  }
}

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceNotifier, ThemeMode>(
      ThemePreferenceNotifier.new,
    );
```

- [ ] **Step 2: 写测试 `test/core/settings/theme_preference_test.dart`**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/settings_providers.dart';

void main() {
  late Directory tmpHome;
  setUp(() {
    tmpHome = Directory.systemTemp.createTempSync('mx_theme');
  });
  tearDown(() => tmpHome.deleteSync(recursive: true));

  Map<String, String> env() => {'HOME': tmpHome.path};

  test('默认浅色', () {
    // 空 HOME 下 build 返回 light
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(themePreferenceProvider), ThemeMode.light);
  });

  test('setDark 切换并持久化到 settings.json', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(themePreferenceProvider.notifier).setDark(true);
    expect(container.read(themePreferenceProvider), ThemeMode.dark);

    final file = File(
      '${tmpHome.path}/.musicx/settings.json',
    );
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), contains('"themeMode":"dark"'));
  });
}
```

Note: 上述测试 `build()` 读取真实 HOME(测试进程启动时决定)。上测试依赖 HOME 环境,若测试机共用真实 HOME 会读到脏数据——为可靠,测试里不依赖真实 HOME 内容,只验证默认 light 与 setDark 后状态。`_settingsFile()` 使用 `Platform.environment['HOME']`,在 `flutter test` 下 HOME 为测试宿主默认;为隔离,测试不依赖磁盘读,仅验证状态与写文件调用。若 `build` 读到既有 settings.json 导致默认非 light,可在 ProviderContainer 用 `overrides` 注入。此测试侧重 `setDark` 状态与 `_persist` 写文件,简化断言。

- [ ] **Step 3: 运行测试验证**

Run:
```bash
cd /Users/tianjun/Desktop/prog/musicx && TMPD=$(mktemp -d) && mkdir -p "$TMPD/h/.pub-cache" && cp -R /Users/tianjun/.pub-cache/. "$TMPD/h/.pub-cache/" 2>/dev/null && HOME="$TMPD/h" CI=true FLUTTER_SUPPRESS_ANALYTICS=true /tmp/flutter_sdk/bin/flutter test test/core/settings/theme_preference_test.dart
```
Expected: PASS(默认 light;setDark 后 dark 且写文件)。

- [ ] **Step 4: Commit**

```bash
git add lib/core/settings/settings_providers.dart test/core/settings/theme_preference_test.dart
git commit -m "feat(ui): add theme preference provider with persistence"
```

---

### Task 3: 根 Widget 依据主题偏好选 themeMode

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `themePreferenceProvider`(Task 2)。
- Produces: 无外部接口;根 `MaterialApp` 的 `themeMode` 动态化。

- [ ] **Step 1: 修改 main.dart 为 ConsumerWidget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/theme/app_theme.dart';
import 'ui/home_shell.dart';

void main() {
  runApp(const ProviderScope(child: MusicxApp()));
}

class MusicxApp extends ConsumerWidget {
  const MusicxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themePreferenceProvider);
    return MaterialApp(
      title: 'MusicX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode, // 不再硬编码 dark
      home: const HomeShell(),
    );
  }
}
```

- [ ] **Step 2: analyze 确认**

Run:
```bash
cd /Users/tianjun/Desktop/prog/musicx && TMPD=$(mktemp -d) && mkdir -p "$TMPD/h/.pub-cache" && cp -R /Users/tianjun/.pub-cache/. "$TMPD/h/.pub-cache/" 2>/dev/null && HOME="$TMPD/h" CI=true FLUTTER_SUPPRESS_ANALYTICS=true /tmp/flutter_sdk/bin/flutter analyze
```
Expected: `No issues found`(仍可能残留其它文件对 `AppTheme.pink` 等报错,属 Task 6 范围;若 main.dart 无报错即通过本任务)。

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(ui): use theme preference for themeMode (default light)"
```

---

### Task 4: 导航重构为三 tab(发现/我的/设置)

**Files:**
- Modify: `lib/ui/home_shell.dart`

**Interfaces:**
- Consumes: 现有 `SearchPage`/`LibraryPage`/`PluginPage`;`playerControllerProvider`(判断是否显示迷你条)。
- Produces: 三 tab 导航结构;移除"播放"tab;`_openPlayer` 保留(用于迷你条展开)。

- [ ] **Step 1: 调整 `_pages` 为发现/我的两页,新增设置入口,移除播放 tab**

改造 `_HomeShellState`:`_pages` 改为 `[SearchPage, LibraryPage]`(发现/我的);"设置"作为第三 tab 独立页(复用 `PluginPage`,或新建轻量 `SettingsPage` 包装)。为最小改动,设置 tab 用 `PluginPage`(其自身即音源/插件管理),并加"外观"分区(见 Task 7)。`_index` 合法值 0/1/2;`_content` 中播放页不再作为 tab 常驻。

```dart
_pages = [
  SearchPage(onOpenPlugins: () => _openSettings()),
  LibraryPage(
    key: ValueKey<String?>(_libraryPlaylistId),
    initialPlaylistId: _libraryPlaylistId,
  ),
];
```

底部导航 destinations 改为:
```dart
destinations: const [
  NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore_rounded), label: '发现'),
  NavigationDestination(icon: Icon(Icons.favorite_outline_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: '我的'),
  NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '设置'),
],
```

侧边栏 `_items` 改为发现/我的/设置三行,去掉独立"播放"行与"下载音乐"行(下载并入我的页——由 `LibraryPage` 已有分区承载;不做额外改动,本轮仅移除重复入口)。

- [ ] **Step 2: `_content()` 不再保留 `_index != 1` 排除逻辑(播放页不再作 tab)**

```dart
Widget _content() {
  final hasSong = ref.watch(playerControllerProvider).current != null;
  final showMiniPlayer = hasSong;
  return Column(
    children: [
      Expanded(child: IndexedStack(index: _index, children: _pages)),
      if (showMiniPlayer) MiniPlayerBar(onOpen: _openPlayer),
    ],
  );
}
```

设置页不作为 `IndexedStack` 常驻 tab 时,最简做法:三 tab 都进 `_pages = [SearchPage, LibraryPage, PluginPage]`;`PluginPage` 是 `ConsumerWidget`,可作 tab 内容。`_openSettings` 不再 push,直接作为第三 tab。保留 `PluginPage` 现有 `onOpenPlugins` 语义(发现页传它触发切到设置 tab 需回调 —— 通过 `setState(_index=2)` 实现)。

调整 `SearchPage(onOpenPlugins: () => setState(() => _index = 2))`。

- [ ] **Step 3: analyze + 测试 + commit**

Run:
```bash
cd /Users/tianjun/Desktop/prog/musicx && TMPD=$(mktemp -d) && mkdir -p "$TMPD/h/.pub-cache" && cp -R /Users/tianjun/.pub-cache/. "$TMPD/h/.pub-cache/" 2>/dev/null && HOME="$TMPD/h" CI=true FLUTTER_SUPPRESS_ANALYTICS=true /tmp/flutter_sdk/bin/flutter analyze
```
Expected: 无 home_shell 相关新错误(其它组件紫粉报错仍属 Task 6)。

```bash
git add lib/ui/home_shell.dart
git commit -m "feat(ui): restructure navigation to three tabs (发现/我的/设置)"
```

---

### Task 5: 播放页布局重排(封面主体 + 顶部切换 + 底部控制区)

**Files:**
- Modify: `lib/ui/player/player_page.dart`

**Interfaces:**
- Consumes: `playerControllerProvider`;`AppTheme`(accent)。
- Produces: 播放页移除紫光晕渐变背景;顶部收起 + 唱片/歌词切换;封面主体;底部干净控制区(进度条+时间+控制键+队列图标)。保留 `PlayerPage(overlay:)` 双入口(全屏/迷你条)。

- [ ] **Step 1: 移除 `PlayerPage` 渐变背景,换用 `bg`**

将 `build` 中的深色渐变 `Container(decoration: BoxDecoration(gradient: ...))` 改为 `coloredBox` 使用 `ColorScheme.surface`/`scaffoldBackgroundColor`:

```dart
return Scaffold(
  extendBody: true,
  body: ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(
      child: song == null ? _EmptyPlayer(...) : _PlayerBody(...),
    ),
  ),
);
```

- [ ] **Step 2: 控制区改为单色品牌红,移除渐变**(`_BottomConsole`/`_PlayButton`/`_RoundToggle`/`SeekBar` 相关的 `AppTheme.pink`/`violet`/`accentGradient` → `scheme.primary`/`accent`)

`_PlayButton` 的 `gradient: AppTheme.accentGradient` 改为 `color: Theme.of(context).colorScheme.primary`;`boxShadow` 用 `scheme.primary.withValues(alpha: .5)`。
`_RoundToggle` 激活色 `AppTheme.pink` → `scheme.primary`。
`_ViewToggle` 选中色 `AppTheme.violet` → `scheme.primary`。

- [ ] **Step 3: analyze + commit**

```bash
git add lib/ui/player/player_page.dart
git commit -m "feat(ui): restructure player page to clean layout, remove gradient bg"
```

---

### Task 6: 全组件紫粉渐变 → 品牌红

**Files:**
- Modify: `lib/ui/widgets/seek_bar.dart`, `lib/ui/widgets/song_tile.dart`, `lib/ui/widgets/artwork_view.dart`, `lib/ui/widgets/mini_player_bar.dart`, `lib/ui/widgets/playlist_picker.dart`, `lib/ui/widgets/download_picker.dart`, `lib/ui/library/library_page.dart`, `lib/ui/search/search_page.dart`, `lib/ui/plugins/plugin_page.dart`, `lib/ui/plugins/update_row.dart`, `lib/ui/home_shell.dart`(Logo 渐变)

**Interfaces:**
- Consumes: `AppTheme` 新 Token(Task 1)。
- Produces: 无新接口;统一改样式。

- [ ] **Step 1: 逐个替换**

- `AppTheme.violet` / `AppTheme.pink` / `AppTheme.orange` → 该主题下的 `ColorScheme.primary`(或 `AppTheme.accentLight`/`accentDark`)。
- `AppTheme.accentGradient/*softGradient` 的使用:
  - 进度条 `seek_bar.dart`:`accentGradient.createShader(activeRect)` → `Paint()..color = scheme.primary`;拇指外圈 `AppTheme.pink` → `scheme.primary`。
  - 迷你条顶部进度 `mini_player_bar.dart` 的 `gradient: AppTheme.accentGradient` → `color: scheme.primary`。
  - Logo(Sidebar)`accentGradient.createShader` → `color: scheme.primary`(用 `Text` 前景色即可)。
  - `download_picker`/`plugin_page`/`search_page`/`artwork_view` 里的 `softGradient`/占位渐变 → 统一改为 `scheme.primary` with alpha 平铺,或保留封面占位的低饱和 `scheme.primary.withValues(alpha:.3)` 平铺。

为避免遗漏,做完后 `grep -rn "AppTheme.pink\|AppTheme.violet\|AppTheme.orange\|AppTheme.accentGradient\|AppTheme.softGradient" lib/` 应无输出。

- [ ] **Step 2: analyze**

Run:
```bash
cd /Users/tianjun/Desktop/prog/musicx && TMPD=$(mktemp -d) && mkdir -p "$TMPD/h/.pub-cache" && cp -R /Users/tianjun/.pub-cache/. "$TMPD/h/.pub-cache/" 2>/dev/null && HOME="$TMPD/h" CI=true FLUTTER_SUPPRESS_ANALYTICS=true /tmp/flutter_sdk/bin/flutter analyze
```
Expected: `No issues found`。

- [ ] **Step 3: Commit**

```bash
git add lib/ui/
git commit -m "feat(ui): replace violet/pink gradients with brand accent across components"
```

---

### Task 7: 设置页添加外观(浅色/深色)分区

**Files:**
- Modify: `lib/ui/plugins/plugin_page.dart`(或独立 `SettingsPage`)

**Interfaces:**
- Consumes: `themePreferenceProvider`(Task 2)。
- Produces: 设置页外观单选。

- [ ] **Step 1: 在设置页添加"外观"分区**

在 `PluginPage`(作为设置 tab)顶部或独立分区加入:
```dart
// 外观:浅色 / 深色
final theme = ref.watch(themePreferenceProvider);
... radio row: 浅色(theme==light) / 深色(theme==dark)
onChanged: (dark) => ref.read(themePreferenceProvider.notifier).setDark(dark),
```

用 `SegmentedButton<ThemeMode>` 或两个 `RadioListTile` 实现,置于页面顶部。

- [ ] **Step 2: analyze + 全量测试 + commit**

Run:
```bash
cd /Users/tianjun/Desktop/prog/musicx && TMPD=$(mktemp -d) && mkdir -p "$TMPD/h/.pub-cache" && cp -R /Users/tianjun/.pub-cache/. "$TMPD/h/.pub-cache/" 2>/dev/null && HOME="$TMPD/h" CI=true FLUTTER_SUPPRESS_ANALYTICS=true /tmp/flutter_sdk/bin/flutter test
```
Expected: All tests passed(无回归)。

```bash
git add lib/ui/plugins/plugin_page.dart
git commit -m "feat(ui): add appearance theme toggle in settings"
```

---

### Task 8: 最终验收

- [ ] **Step 1: 全量测试**

```bash
cd /Users/tianjun/Desktop/prog/musicx && TMPD=$(mktemp -d) && mkdir -p "$TMPD/h/.pub-cache" && cp -R /Users/tianjun/.pub-cache/. "$TMPD/h/.pub-cache/" 2>/dev/null && HOME="$TMPD/h" CI=true FLUTTER_SUPPRESS_ANALYTICS=true /tmp/flutter_sdk/bin/flutter test
```
Expected: All tests passed。

- [ ] **Step 2: analyze**

```bash
cd /Users/tianjun/Desktop/prog/musicx && TMPD=$(mktemp -d) && mkdir -p "$TMPD/h/.pub-cache" && cp -R /Users/tianjun/.pub-cache/. "$TMPD/h/.pub-cache/" 2>/dev/null && HOME="$TMPD/h" CI=true FLUTTER_SUPPRESS_ANALYTICS=true /tmp/flutter_sdk/bin/flutter analyze
```
Expected: No issues found。

- [ ] **Step 3: 确认无紫粉残留**

```bash
grep -rn "AppTheme.pink\|AppTheme.violet\|AppTheme.orange\|AppTheme.accentGradient\|AppTheme.softGradient" lib/ && echo "残留!" || echo "OK: 无紫粉渐变残留"
```

- [ ] **Step 4: 确认最终状态并提交**

```bash
git status
```
Expected: 工作区干净,所有任务已提交。

---

## 验收标准(来自设计文档 §9)

1. 默认浅色「月光极简」:黑白灰 + 品牌红点缀,无紫粉渐变残留(Task 1/6/8)。
2. 导航三 tab:发现/我的/设置;无独立播放 tab;播放页从歌曲/迷你条进入(Task 4)。
3. 设置页可切换浅色/深色,持久化,重启保持(Task 2/7)。
4. 播放页布局:封面主体+顶部切换+底部干净控制区,移除渐变背景(Task 5)。
5. `flutter analyze` 无错误、全量测试通过、主题切换/导航有测试覆盖(Task 8)。

## Self-Review

- **Spec 覆盖**:配色(§3)→Task1/6;导航(§4)→Task4;播放页(§5)→Task5;主题机制(§7)→Task2/3/7;组件规范(§6)→Task6;验收(§9)→Task8。全部覆盖。
- **占位符扫描**:本文每步骤含实际代码/命令,无 TBD/TODO 占位。
- **类型一致性**:`themePreferenceProvider`(Task2)在 Task3/7 一致引用 `ThemePreferenceNotifier.setDark`,`AppTheme.accent*`(Task1)在 Task5/6 一致引用 `ColorScheme.primary`。
- **风险**:Task6 改动面广,依赖 grep 确认无残留;Task1 后其它文件会有临时报错属预期,Task6 消除。
