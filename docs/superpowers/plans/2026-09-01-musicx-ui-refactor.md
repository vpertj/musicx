# MusicX UI 重构(月光极简)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 MusicX 从"紫粉渐变的深色沉浸"UI 重构为「月光极简」——黑白灰骨架 + 品牌红点缀、三 tab 导航(发现/我的/设置)、播放页重排、浅色为主可手动切深色。

**Architecture:** 基于语义色 Token 重写 `AppTheme` 的 light/dark 两套 ThemeData;新增主题偏好 provider 并持久化,根 Widget 据此选择 themeMode;重排导航与播放页;把散落各 UI 文件的紫粉渐变/品牌色替换为品牌红点缀。

**Tech Stack:** Flutter + Material 3 + flutter_riverpod。无新依赖。

## Global Constraints

- 目标平台:Android + Windows + macOS(iOS 不需要)。所有改动对三平台一致,无平台分支。
- 不使用新的 pub 依赖。
- 配色只通过 `lib/theme/app_theme.dart` 的语义常量引用,禁止在 UI 文件硬编码新的彩色值。
- 移除所有用于 UI 元素的紫→粉渐变(`AppTheme.accentGradient`、`AppTheme.softGradient`),播放进度条/播放键/高亮统一用品牌红 `accent`。
- 深浅两套主题在同一文件中组织(light 默认、dark 手动切换),默认浅色。
- 中文 UI 文案与现有保持一致;不新增社交/评论等功能。
- 每任务结束:新增/更新测试 → 运行相关测试 → `flutter analyze` 无错误 → commit。

---

### Task 1: 重写 AppTheme 为语义色 Token + 品牌红

**Files:**
- Modify: `lib/theme/app_theme.dart`(整体重写)

**Interfaces:**
- Produces:
  - `static const Color accent`(品牌红,浅色 `#FA3B4D`,深色 `#FF4559`)
  - `static const Color accentSoft`(浅色 `#0xFFEDEE`,深色 `#0x3A2225`)
  - `static ThemeData get light` / `static ThemeData get dark`
  - `static Color bgOf(Brightness)`、`static LinearGradient albumPlaceholder(Brightness)`(可选辅助)
  - 移除 `violet`、`pink`、`orange`、`accentGradient`、`softGradient`(或保留 `orange` 若其它处必需——见 Task 6 替换后再删)
- Consumes: 无(基础层)

- [ ] **Step 1: 重写 app_theme.dart**

用语义 token 重写。核心:黑白灰背景/表面/文字 + 品牌红点缀,ColorScheme 的 `primary` 设为品牌红,`scaffoldBackgroundColor` 用 `bg`。删除紫粉渐变常量。示例关键代码:

```dart
// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();
  static const Color accent = Color(0xFFFA3B4D);   // 浅色品牌红
  static const Color accentDark = Color(0xFFFF4559); // 深色品牌红
  static const Color accentSoft = Color(0xFFFFEDEE); // 浅色红底
  static const Color accentSoftDark = Color(0xFF3A2225); // 深色红底

  static Color _bg(Brightness b) => b == Brightness.dark ? const Color(0xFF121212) : const Color(0xFFFAFBFC);
  static Color _surface(Brightness b) => b == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  static Color _surfaceHi(Brightness b) => b == Brightness.dark ? const Color(0xFF242629) : const Color(0xFFF2F3F5);
  static Color _text(Brightness b) => b == Brightness.dark ? const Color(0xFFF3F4F6) : const Color(0xFF1A1C1E);
  static Color _muted(Brightness b) => b == Brightness.dark ? const Color(0xFF9AA1AB) : const Color(0xFF8A8F98);
  static Color _divider(Brightness b) => b == Brightness.dark ? const Color(0xFF2C2F33) : const Color(0xFFE7E9EC);
  static Color _accent(Brightness b) => b == Brightness.dark ? accentDark : accent;
  static Color _accentSoft(Brightness b) => b == Brightness.dark ? accentSoftDark : accentSoft;

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme(
      brightness: b,
      primary: _accent(b),
      onPrimary: Colors.white,
      secondary: _accent(b),
      onSecondary: Colors.white,
      surface: _surface(b),
      onSurface: _text(b),
      error: isDark ? const Color(0xFFFF6B81) : const Color(0xFFD63A5B),
      onError: Colors.white,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
      scaffoldBackgroundColor: _bg(b),
      splashFactory: InkSparkle.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: _text(b), displayColor: _text(b)),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: _text(b), fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: .2),
        iconTheme: IconThemeData(color: _text(b)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surface(b).withValues(alpha: .95),
        indicatorColor: _accentSoft(b),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? _text(b) : _muted(b),
        )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? _accent(b) : _muted(b), size: 23,
        )),
      ),
      cardTheme: CardThemeData(
        color: _surface(b), elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: _surfaceHi(b),
        hintStyle: TextStyle(color: _muted(b)),
        prefixIconColor: _muted(b), suffixIconColor: _muted(b),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _accent(b), width: 1.4)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _surfaceHi(b), side: BorderSide.none,
        labelStyle: TextStyle(color: _text(b), fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: _text(b))),
      snackBarTheme: SnackBarThemeData(backgroundColor: _surfaceHi(b), contentTextStyle: TextStyle(color: _text(b)), behavior: SnackBarBehavior.floating),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: _surface(b), modalBackgroundColor: _surface(b),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        showDragHandle: true, dragHandleColor: _muted(b).withValues(alpha: .5)),
      dialogTheme: DialogThemeData(backgroundColor: _surfaceHi(b),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(color: _text(b), fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: _text(b).withValues(alpha: .8), fontSize: 14, height: 1.5)),
      dividerTheme: DividerThemeData(color: _divider(b), thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(iconColor: _muted(b), textColor: _text(b)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: _accent(b), linearTrackColor: _surfaceHi(b)),
    );
  }
}
```

- [ ] **Step 2: 运行 analyze**

Run: `flutter analyze`
Expected: 因其它文件仍引用被删的 `AppTheme.violet/pink/accentGradient` 等,会有未定义引用错误——这是预期,Task 6 会替换它们。**此步骤只确认 app_theme.dart 本身无语法错误(可临时保留旧的 `pink`/`violet` 别名以让 analyze 通过,Task 6 之后删除)**。

> 注意:为避免中间态大面积报错,Task 1 可在类内**临时保留** `violet`/`pink`/`accentGradient`/`softGradient` 作为基于已有颜色的占位,待 Task 6 全部替换后一并删除。Task 1 的验收以 `flutter analyze` 无新增错误为准。

- [ ] **Step 3: Commit**

```bash
git add lib/theme/app_theme.dart
git commit -m "theme: rewrite AppTheme as semantic color tokens (月光极简)"
```

---

### Task 2: 新增主题偏好 provider(浅色默认 + 持久化)

**Files:**
- Modify: `lib/core/settings/settings_providers.dart`
- Create: `test/core/settings/theme_preference_test.dart`

**Interfaces:**
- Produces:`themePreferenceProvider` = `NotifierProvider<ThemePreferenceController, ThemeMode>`,默认 `ThemeMode.light`,`toggle()` 设置为 light/dark 并持久化到 `~/.musicx/settings.json`。
- Consumes: 仅在 Task 3(main.dart)与 Task 7(设置页)使用。

- [ ] **Step 1: 写失败测试**

```dart
// test/core/settings/theme_preference_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/settings_providers.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mx_theme'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('默认浅色 ThemeMode.light', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(themePreferenceProvider), ThemeMode.light);
  });

  test('setDark 切到深色并持久化', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(themePreferenceProvider.notifier).setDark();
    expect(c.read(themePreferenceProvider), ThemeMode.dark);
    // 重启后(新容器)应仍为深色
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect(c2.read(themePreferenceProvider), ThemeMode.dark);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/core/settings/theme_preference_test.dart`
Expected: FAIL,`themePreferenceProvider` 未定义。

- [ ] **Step 3: 实现 provider**

在 `settings_providers.dart` 追加(保持与 `SearchSourceNotifier` 一致的风格,持久化到 `~/.musicx/settings.json`):

```dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';

final _prefFile = () {
  final home = Platform.environment['HOME'];
  final dir = Directory(home == null || home.isEmpty ? '.musicx' : '$home/.musicx');
  return File('${dir.path}/settings.json');
}();

class ThemePreferenceController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    try {
      if (_prefFile.existsSync()) {
        final map = jsonDecode(_prefFile.readAsStringSync()) as Map<String, dynamic>;
        final v = map['themeMode'];
        if (v == 'dark') return ThemeMode.dark;
      }
    } catch (_) {}
    return ThemeMode.light;
  }

  void setDark() {
    state = ThemeMode.dark;
    _persist();
  }

  void setLight() {
    state = ThemeMode.light;
    _persist();
  }

  void _persist() {
    try {
      _prefFile.parent.createSync(recursive: true);
      _prefFile.writeAsStringSync(jsonEncode({'themeMode': state == ThemeMode.dark ? 'dark' : 'light'}));
    } catch (_) {}
  }
}

final themePreferenceProvider = NotifierProvider<ThemePreferenceController, ThemeMode>(ThemePreferenceController.new);
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/core/settings/theme_preference_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/core/settings/settings_providers.dart test/core/settings/theme_preference_test.dart
git commit -m "feat(theme): add themePreferenceProvider with persistence (light default)"
```

---

### Task 3: 根 Widget 按主题偏好应用 themeMode

**Files:**
- Modify: `lib/main.dart`
- Modify: `test/ui/home_shell_test.dart`(补充主题偏好读取,如合适)

**Interfaces:**
- Consumes:`themePreferenceProvider`(Task 2)。
- Produces:无。

- [ ] **Step 1: 改 main.dart**

把 `MusicxApp` 改成 `ConsumerWidget`,用 `ref.watch(themePreferenceProvider)` 决定 `themeMode`:

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
      themeMode: themeMode, // 默认 light,可手动切 dark
      home: const HomeShell(),
    );
  }
}
```

注意:`ProviderScope` 包裹在 `runApp`,`MusicxApp` 作为 ConsumerWidget 才能 watch。

- [ ] **Step 2: 运行测试**

Run: `flutter test test/ui/home_shell_test.dart`
Expected: PASS(现有测试不依赖硬编码 dark,应不受影响;若测试显式设置了 MaterialApp themeMode,则确认逻辑仍成立)。

- [ ] **Step 3: analyze** — Run: `flutter analyze` Expected: 无错误。

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat(theme): apply themePreference to root MaterialApp"
```

---

### Task 4: 导航重构 —— 三 tab(发现/我的/设置)

**Files:**
- Modify: `lib/ui/home_shell.dart`
- Modify: `test/ui/home_shell_test.dart`(若断言了"播放"tab,更新)

**Interfaces:**
- Consumes:独立页面(`SearchPage`/`LibraryPage`/`PluginPage`)。
- Produces:三 tab 布局;移除"播放"顶级 tab;下载/歌单归入"我的"页;设置成为第三个 tab。

- [ ] **Step 1: 修改 home_shell.dart 的导航结构**

把 `_pages` 和 `_Sidebar`/`NavigationBar` 的 items 从 `[发现, 播放, 我的]` 改为 `[发现, 我的, 设置]`:

- `_pages = [SearchPage(...), LibraryPage(...), PluginPage()]`
- 移动端 bottom `NavigationDestination`:探索/我的/设置三个。
- 移除 `_openPlayer` 不再是 tab(仍保留从迷你条打开全屏播放器的入口 `_openPlayer` 供 `MiniPlayerBar` 使用,但不再作为顶级 tab)。
- `index` 语义:0=发现,1=我的,2=设置。

```dart
_pages = [
  SearchPage(onOpenPlugins: () {}),   // 发现
  LibraryPage(key: ValueKey<String?>(_libraryPlaylistId), initialPlaylistId: _libraryPlaylistId), // 我的
  const PluginPage(),                 // 设置
];
```

底部导航 items:

```dart
destinations: const [
  NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore_rounded), label: '发现'),
  NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: '我的'),
  NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '设置'),
],
```

- [ ] **Step 2: 运行 home_shell 相关测试**

Run: `flutter test test/ui/home_shell_test.dart test/ui/layout_audit_test.dart`
Expected: PASS(若断言了"播放"tab,相应更新断言为"发现/我的/设置")。

- [ ] **Step 3: analyze** — Run: `flutter analyze` Expected: 无错误。

- [ ] **Step 4: Commit**

```bash
git add lib/ui/home_shell.dart test/ui/home_shell_test.dart
git commit -m "refactor(nav): three-tab navigation (发现/我的/设置), remove play tab"
```

---

### Task 5: 播放页重排(封面主体 + 顶部切换 + 底部干净控制区)

**Files:**
- Modify: `lib/ui/player/player_page.dart`
- Modify: `test/ui/player_page_test.dart`

**Interfaces:**
- Consumes:`PlayerController`、`AppTheme`(新的 accent)。
- Produces:重排后的播放页(顶栏收起+视图切换、大封面主体、底部控制区)。

- [ ] **Step 1: 重排 player_page.dart**

- **移除**页面背景紫光晕渐变 `LinearGradient(colors:[0xFF2E2356,...])`,改用 `Theme.of(context).colorScheme.surface` / scaffold 背景。
- 顶部:保留收起按钮(overlay 模式)+ 唱片/歌词切换(移到顶部,不再挤底部)。
- 主体:大封面 `_Artwork` 居中。
- 底部 `_BottomConsole`:进度条 + 时间 + 控制键(播放/暂停为品牌红大圆,上/下一首灰色图标)+ 队列图标(右侧,点击弹 `_showQueue`)。
- `_PlayButton` 的渐变 `AppTheme.accentGradient` 改为 `AppTheme.accent` 纯色。
- `_ViewToggle` 选中色 `AppTheme.violet` → `Theme.of(context).colorScheme.primary`(即品牌红)。
- 移除 `_RoundToggle` 中 `AppTheme.pink` → 改用 `colorScheme.primary`。

关键改动示例:

```dart
// 页面背景(替换原来紫光晕渐变)
Scaffold(
  extendBody: true,
  body: Container(color: Theme.of(context).colorScheme.surface, child: ...),
)

// 播放键(纯色品牌红,去掉渐变)
decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary),

// 视图切换选中色
color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
```

- [ ] **Step 2: 更新/运行 player 测试**

Run: `flutter test test/ui/player_page_test.dart`
Expected: PASS。

- [ ] **Step 3: analyze** — Run: `flutter analyze` Expected: 无错误。

- [ ] **Step 4: Commit**

```bash
git add lib/ui/player/player_page.dart test/ui/player_page_test.dart
git commit -m "refactor(player): reorder player page (cover hero + top toggle + clean control bar)"
```

---

### Task 6: 替换全部紫粉/品牌色引用为品牌红点缀

**Files(全项目替换):**
- `lib/ui/widgets/seek_bar.dart`(accentGradient→accent;pink→scheme.primary)
- `lib/ui/widgets/mini_player_bar.dart`(accentGradient→scheme.primary)
- `lib/ui/widgets/song_tile.dart`(scheme.primary 已是新品牌红,无需改,检查)[关注确认]
- `lib/ui/widgets/artwork_view.dart`(占位渐变用 scheme.primary,已随新主题)
- `lib/ui/widgets/playlist_picker.dart`(pink→scheme.primary)
- `lib/ui/widgets/download_picker.dart`(softGradient→scheme.primary)
- `lib/ui/plugins/plugin_page.dart`(violet/pink/softGradient→scheme.primary 或 accentSoft)
- `lib/ui/plugins/update_row.dart`(pink/violet→scheme.primary)
- `lib/ui/library/library_page.dart`(pink/violet→scheme.primary/accentSoft)
- `lib/ui/search/search_page.dart`(violet/pink→scheme.primary)
- `lib/ui/home_shell.dart`(accentGradient→accent,violet→scheme.primary)
- `lib/theme/app_theme.dart`(删除临时保留的 violet/pink/accentGradient/softGradient 别名)

**Interfaces:**
- Consumes:新的 `AppTheme` 只保留 `accent`/`accentSoft`/light/dark;`colorScheme.primary` 已是品牌红。

- [ ] **Step 1: 逐文件替换,移除对已删常量的引用**

逐个把 `AppTheme.violet`/`AppTheme.pink`/`AppTheme.orange`/`AppTheme.accentGradient`/`AppTheme.softGradient` 替换为 `Theme.of(context).colorScheme.primary`(或 `accentSoft` 用于浅红底选中态)。

- [ ] **Step 2: 删除 app_theme.dart 中临时保留的旧常量**

Task 1 若临时保留了 `violet`/`pink`/`accentGradient`/`softGradient`,此刻全部删除,只留 `accent`/`accentSoft`/light/dark。

- [ ] **Step 3: 运行 analyze** — Run: `flutter analyze` Expected: 0 error(若仍有未定义引用,说明遗漏某文件,补齐)。

- [ ] **Step 4: 运行全量测试** — Run: `flutter test` Expected: 全部通过。

- [ ] **Step 5: Commit**

```bash
git add lib/ && git add lib/theme/app_theme.dart
git commit -m "refactor(colors): replace violet/pink gradients with brand-red accent"
```

---

### Task 7: 设置页外观分区(浅色/深色切换)

**Files:**
- Modify: `lib/ui/plugins/plugin_page.dart`(设置页,加"外观"分区)或独立设置页
- Modify: `test/ui/plugin_page_test.dart`

**Interfaces:**
- Consumes:`themePreferenceProvider`(Task 2)。
- Produces:设置页"外观"分区含浅色/深色单选,点击调用 `setLight()`/`setDark()`。

- [ ] **Step 1: 在设置页加外观分区**

在设置页(plugin_page 或新增 `SettingsPage`)加入"外观"区块:

```dart
// 外观:浅色 / 深色
final themeMode = ref.watch(themePreferenceProvider);
// 用 SegmentedButton 或两个选择项
SegmentedButton<ThemeMode>(
  segments: const [
    ButtonSegment(value: ThemeMode.light, label: Text('浅色'), icon: Icon(Icons.light_mode_outlined)),
    ButtonSegment(value: ThemeMode.dark, label: Text('深色'), icon: Icon(Icons.dark_mode_outlined)),
  ],
  selected: {themeMode},
  onSelectionChanged: (s) => ref.read(themePreferenceProvider.notifier).setDark/setLight,
)
```

- [ ] **Step 2: 运行相关测试**

Run: `flutter test test/ui/plugin_page_test.dart`
Expected: PASS。

- [ ] **Step 3: analyze** — Run: `flutter analyze` Expected: 无错误。

- [ ] **Step 4: Commit**

```bash
git add lib/ui/plugins/plugin_page.dart test/ui/plugin_page_test.dart
git commit -m "feat(settings): add appearance section (light/dark toggle)"
```

---

## Self-Review 检查

- **Spec 覆盖**:设计文档 §3 配色(6 种语义 token + 品牌红)→ Task 1;§4 三 tab 导航 → Task 4;§5 播放页重排 → Task 5;§6 组件规范(歌曲行/导航项/卡片/输入框)→ Task 1&6;§7 主题切换(provider+持久化+根应用+设置入口)→ Task 2/3/7;§8 文件范围 → 各 Task;§9 验收 → 各 Task 测试 + 最后全量验证。
- **占位符**:无 TBD/TODO。
- **类型/命名一致**:`accent`/`accentSoft`/`themePreferenceProvider`/`setLight`/`setDark` 各 Task 引用一致。

## 执行交接

计划保存后,向用户提供两种执行方式:
1. **Subagent-Driven(推荐)**——每任务派新 subagent,任务间审查。
2. **Inline Execution**——本会话内用 executing-plans 分批执行。
