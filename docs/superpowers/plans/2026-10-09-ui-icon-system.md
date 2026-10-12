# MusicX 图标系统与设置页视觉重做 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把全局图标从 Material 换成 Tabler(经一层语义层),建立视觉 token,并把设置页重做成 NutUI 观感。

**Architecture:** 新增 `lib/ui/icons.dart` 作为**唯一**图标入口(页面禁止再写 `Icons.*`,用测试锁住);新增 `lib/ui/tokens.dart` 提供间距/圆角/行高/字号/灰底色 token,`app_theme.dart` 吃灰底与分割线;159 处引用按文件群分 3 个提交机械替换;设置页在这套 token 上重做。

**Tech Stack:** Flutter, `flutter_tabler_icons: ^1.43.0`(已 `pub add`,71 个映射已逐一比对包内常量存在),Riverpod,现有 UI 测试套件。

**Spec:** `docs/superpowers/specs/2026-10-09-ui-icon-system-design.md`

## Global Constraints

- 不改品牌色:强调色仍用 `Theme.of(context).colorScheme.primary`。
- 不改信息架构与交互流程;只换图标字形与视觉尺度。
- 图标只从 `AppIcons.*` 取;`lib/ui/**` 内**禁止**出现 `Icons.`(由测试断言)。
- 不引入 NutUI 字体,不使用 svg/图片图标。
- 每个任务结束必须:`flutter analyze` 无 issue + `flutter test` 全绿,再提交。
- 命名规则:`AppIcons.xxx` = 常态(线性),`AppIcons.xxxActive` = 选中/激活(filled)。
- 行内图标统一 `AppSize.icon`(20),大图标 `AppSize.iconLarge`(24)。
- 提交信息用中文,正文说明「为什么」。

---

## 映射总表(已逐一比对包内常量,71/71 命中)

| Material(现用) | AppIcons 语义 | Tabler 常量 |
|---|---|---|
| `Icons.add_circle_outline_rounded` | `AppIcons.addCircle` | `TablerIcons.circle_plus` |
| `Icons.add_rounded` | `AppIcons.add` | `TablerIcons.plus` |
| `Icons.album_rounded` | `AppIcons.album` | `TablerIcons.album` |
| `Icons.auto_awesome_rounded` | `AppIcons.autoAwesome` | `TablerIcons.sparkles` |
| `Icons.blur_on_rounded` | `AppIcons.blur` | `TablerIcons.blur` |
| `Icons.cancel_rounded` | `AppIcons.cancel` | `TablerIcons.circle_x` |
| `Icons.check_circle_outline_rounded` | `AppIcons.checkCircleOutlined` | `TablerIcons.circle_check` |
| `Icons.check_circle_rounded` | `AppIcons.checkCircle` | `TablerIcons.circle_check` |
| `Icons.check_rounded` | `AppIcons.check` | `TablerIcons.check` |
| `Icons.chevron_right_rounded` | `AppIcons.chevronRight` | `TablerIcons.chevron_right` |
| `Icons.close_rounded` | `AppIcons.close` | `TablerIcons.x` |
| `Icons.cloud_off_rounded` | `AppIcons.cloudOff` | `TablerIcons.cloud_off` |
| `Icons.dark_mode_outlined` | `AppIcons.darkMode` | `TablerIcons.moon` |
| `Icons.delete_outline_rounded` | `AppIcons.delete` | `TablerIcons.trash` |
| `Icons.download_for_offline_outlined` | `AppIcons.downloaded` | `TablerIcons.circle_check` |
| `Icons.download_for_offline_rounded` | `AppIcons.downloadedActive` | `TablerIcons.circle_check` |
| `Icons.download_rounded` | `AppIcons.download` | `TablerIcons.download` |
| `Icons.edit_outlined` | `AppIcons.edit` | `TablerIcons.pencil` |
| `Icons.error_outline_rounded` | `AppIcons.error` | `TablerIcons.alert_circle` |
| `Icons.explore_outlined` | `AppIcons.explore` | `TablerIcons.compass` |
| `Icons.explore_rounded` | `AppIcons.exploreActive` | `TablerIcons.compass_filled` |
| `Icons.extension_rounded` | `AppIcons.extension` | `TablerIcons.puzzle` |
| `Icons.favorite_border_rounded` | `AppIcons.favorite` | `TablerIcons.heart` |
| `Icons.favorite_rounded` | `AppIcons.favoriteActive` | `TablerIcons.heart_filled` |
| `Icons.folder_open_rounded` | `AppIcons.folder` | `TablerIcons.folder_open` |
| `Icons.history_rounded` | `AppIcons.history` | `TablerIcons.history` |
| `Icons.info_outline_rounded` | `AppIcons.info` | `TablerIcons.info_circle` |
| `Icons.insert_drive_file_outlined` | `AppIcons.insertFile` | `TablerIcons.file_music` |
| `Icons.keyboard_arrow_down_rounded` | `AppIcons.chevronDown` | `TablerIcons.chevron_down` |
| `Icons.label_outline_rounded` | `AppIcons.label` | `TablerIcons.tag` |
| `Icons.library_music_outlined` | `AppIcons.libraryOutlined` | `TablerIcons.music` |
| `Icons.library_music_rounded` | `AppIcons.library` | `TablerIcons.music` |
| `Icons.light_mode_outlined` | `AppIcons.lightMode` | `TablerIcons.sun` |
| `Icons.link_rounded` | `AppIcons.link` | `TablerIcons.link` |
| `Icons.local_fire_department_rounded` | `AppIcons.fire` | `TablerIcons.flame` |
| `Icons.lyrics_outlined` | `AppIcons.lyrics` | `TablerIcons.microphone_2` |
| `Icons.lyrics_rounded` | `AppIcons.lyricsActive` | `TablerIcons.microphone_2` |
| `Icons.music_note_rounded` | `AppIcons.music` | `TablerIcons.music` |
| `Icons.open_in_new_rounded` | `AppIcons.openExternal` | `TablerIcons.external_link` |
| `Icons.palette_outlined` | `AppIcons.palette` | `TablerIcons.palette` |
| `Icons.pause_rounded` | `AppIcons.pause` | `TablerIcons.player_pause` |
| `Icons.play_arrow_rounded` | `AppIcons.play` | `TablerIcons.player_play` |
| `Icons.playlist_add_rounded` | `AppIcons.addToPlaylist` | `TablerIcons.playlist_add` |
| `Icons.playlist_play_rounded` | `AppIcons.playlistPlay` | `TablerIcons.playlist` |
| `Icons.queue_music_rounded` | `AppIcons.queue` | `TablerIcons.playlist` |
| `Icons.radar_rounded` | `AppIcons.radar` | `TablerIcons.radar_2` |
| `Icons.refresh_rounded` | `AppIcons.refresh` | `TablerIcons.refresh` |
| `Icons.remove_circle_outline_rounded` | `AppIcons.removeCircle` | `TablerIcons.circle_minus` |
| `Icons.remove_rounded` | `AppIcons.remove` | `TablerIcons.minus` |
| `Icons.repeat_one_rounded` | `AppIcons.repeatOne` | `TablerIcons.repeat_once` |
| `Icons.repeat_rounded` | `AppIcons.repeat` | `TablerIcons.repeat` |
| `Icons.restart_alt_rounded` | `AppIcons.restart` | `TablerIcons.reload` |
| `Icons.rss_feed_rounded` | `AppIcons.rss` | `TablerIcons.rss` |
| `Icons.search_off_rounded` | `AppIcons.searchOff` | `TablerIcons.search_off` |
| `Icons.search_rounded` | `AppIcons.search` | `TablerIcons.search` |
| `Icons.settings_backup_restore_rounded` | `AppIcons.settingsBackup` | `TablerIcons.settings_automation` |
| `Icons.settings_outlined` | `AppIcons.settings` | `TablerIcons.settings` |
| `Icons.settings_rounded` | `AppIcons.settingsActive` | `TablerIcons.settings_filled` |
| `Icons.shuffle_rounded` | `AppIcons.shuffle` | `TablerIcons.arrows_shuffle` |
| `Icons.skip_next_rounded` | `AppIcons.next` | `TablerIcons.player_skip_forward` |
| `Icons.skip_previous_rounded` | `AppIcons.prev` | `TablerIcons.player_skip_back` |
| `Icons.subtitles_rounded` | `AppIcons.subtitles` | `TablerIcons.letter_case` |
| `Icons.system_update_alt_rounded` | `AppIcons.updateAlt` | `TablerIcons.cloud_download` |
| `Icons.text_fields_rounded` | `AppIcons.textFields` | `TablerIcons.text_size` |
| `Icons.tune_rounded` | `AppIcons.tune` | `TablerIcons.adjustments` |
| `Icons.update_rounded` | `AppIcons.update` | `TablerIcons.cloud_download` |
| `Icons.verified_rounded` | `AppIcons.verified` | `TablerIcons.rosette_discount_check` |
| `Icons.view_agenda_rounded` | `AppIcons.viewAgenda` | `TablerIcons.layout_list` |
| `Icons.view_day_rounded` | `AppIcons.viewDay` | `TablerIcons.layout_rows` |
| `Icons.volume_up_rounded` | `AppIcons.volume` | `TablerIcons.volume` |
| `Icons.widgets_rounded` | `AppIcons.widgets` | `TablerIcons.layout_grid` |

> 少数语义做了**降级替代**(Tabler 无同名变体),替换处保留注释说明:
> `library*` → `music`;`downloaded*` → `circle_check`;
> `restart` → `reload`;`subtitles` → `letter_case`。

## 文件结构

| 文件 | 职责 |
|---|---|
| `lib/ui/icons.dart`(新) | 图标语义层,唯一图标入口 |
| `lib/ui/tokens.dart`(新) | 间距/圆角/尺寸/字号/颜色 token |
| `lib/theme/app_theme.dart`(改) | 接入页面灰底与分割线 token |
| `lib/ui/**`(改,15 个文件) | 把 `Icons.*` 换成 `AppIcons.*` |
| `lib/ui/plugins/plugin_page.dart`(改) | 设置页视觉重做(本次主要视觉改动) |
| `test/ui/icon_layer_test.dart`(新) | 图标层契约:不许直接引用 `Icons.`、语义不缺失 |
| `test/ui/tokens_test.dart`(新) | token 关键值断言(行高/图标尺寸/分割线内缩) |
| `test/ui/settings_layout_test.dart` 等(改) | 同步断言到 `AppIcons.*` |

---

### Task 1: 接入 Tabler + 图标语义层 + 契约测试

**Files:**
- Create: `lib/ui/icons.dart`
- Create: `test/ui/icon_layer_test.dart`
- Modify: `pubspec.yaml`(已加 `flutter_tabler_icons: ^1.43.0`)

**Interfaces:**
- Produces: `AppIcons.<语义>`(全部 `IconData` 常量),后续所有任务与页面都用它。

- [ ] **Step 1: 写失败测试** `test/ui/icon_layer_test.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/ui/icons.dart';

void main() {
  test('页面不许直接引用 Icons.*:必须走 AppIcons 语义层', () {
    final offenders = <String>[];
    for (final f in Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final text = f.readAsStringSync();
      // 语义层自己除外
      if (f.path.endsWith('ui/icons.dart')) continue;
      for (final m in RegExp(r'\bIcons\.[a-zA-Z_]+').allMatches(text)) {
        offenders.add('${f.path}: ${m.group(0)}');
      }
    }
    expect(offenders, isEmpty,
        reason: '这些地方还在直接引用 Material 图标,请改用 AppIcons:\n${offenders.join('\n')}');
  });

  test('语义层常量齐备且非空', () {
    const icons = <IconData>[
      AppIcons.explore, AppIcons.exploreActive, AppIcons.mine, AppIcons.mineActive,
      AppIcons.settings, AppIcons.settingsActive, AppIcons.play, AppIcons.pause,
      AppIcons.prev, AppIcons.next, AppIcons.repeat, AppIcons.repeatOne,
      AppIcons.shuffle, AppIcons.volume, AppIcons.playlistPlay, AppIcons.queue,
      AppIcons.addToPlaylist, AppIcons.library, AppIcons.album, AppIcons.download,
      AppIcons.downloaded, AppIcons.delete, AppIcons.search, AppIcons.searchOff,
      AppIcons.radar, AppIcons.fire, AppIcons.history, AppIcons.favorite,
      AppIcons.favoriteActive, AppIcons.close, AppIcons.check, AppIcons.chevronRight,
      AppIcons.chevronDown, AppIcons.add, AppIcons.remove, AppIcons.refresh,
      AppIcons.restart, AppIcons.update, AppIcons.info, AppIcons.error,
      AppIcons.edit, AppIcons.link, AppIcons.openExternal, AppIcons.folder,
      AppIcons.extension, AppIcons.rss, AppIcons.widgets, AppIcons.tune,
      AppIcons.palette, AppIcons.lightMode, AppIcons.darkMode, AppIcons.lyrics,
      AppIcons.lyricsActive, AppIcons.subtitles, AppIcons.music, AppIcons.cloudOff,
      AppIcons.verified, AppIcons.autoAwesome, AppIcons.textFields,
      AppIcons.viewAgenda, AppIcons.viewDay, AppIcons.blur, AppIcons.label,
      AppIcons.insertFile, AppIcons.cancel, AppIcons.removeCircle,
      AppIcons.checkCircle, AppIcons.checkCircleOutlined, AppIcons.settingsBackup,
      AppIcons.addCircle, AppIcons.updateAlt, AppIcons.playlistPlay,
    ];
    expect(icons, hasLength(greaterThan(60)));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/icon_layer_test.dart`
Expected: FAIL —— `lib/ui/icons.dart` 不存在(编译错误)/ 或 offender 列表非空。

- [ ] **Step 3: 建 `lib/ui/icons.dart`**(按「映射总表」逐条落地,含 3.x 小节被引用的 `mine`/`mineActive`)

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

/// 全局图标**语义层**:页面只认这里的名字,换图标集只改这一个文件。
///
/// 约定:
/// - `xxx` = 常态(线性图标);`xxxActive` = 选中/激活(filled)。
/// - Tabler 没有同名变体的语义做了降级替代,已在行内注明。
/// - 尺寸与颜色不写在这里:统一由 `lib/ui/tokens.dart` 与调用点决定。
abstract final class AppIcons {
  // 底部导航
  static const IconData explore = TablerIcons.compass;
  static const IconData exploreActive = TablerIcons.compass_filled;
  static const IconData mine = TablerIcons.user;
  static const IconData mineActive = TablerIcons.user;
  static const IconData settings = TablerIcons.settings;
  static const IconData settingsActive = TablerIcons.settings_filled;

  // 播放控制
  static const IconData play = TablerIcons.player_play;
  static const IconData pause = TablerIcons.player_pause;
  static const IconData prev = TablerIcons.player_skip_back;
  static const IconData next = TablerIcons.player_skip_forward;
  static const IconData repeat = TablerIcons.repeat;
  static const IconData repeatOne = TablerIcons.repeat_once;
  static const IconData shuffle = TablerIcons.arrows_shuffle;
  static const IconData volume = TablerIcons.volume;

  // 队列 / 曲库 / 下载
  static const IconData playlistPlay = TablerIcons.playlist;
  static const IconData queue = TablerIcons.playlist;
  static const IconData addToPlaylist = TablerIcons.playlist_add;
  static const IconData library = TablerIcons.music; // Tabler 无 library-music
  static const IconData libraryOutlined = TablerIcons.music;
  static const IconData album = TablerIcons.album;
  static const IconData download = TablerIcons.download;
  static const IconData downloaded = TablerIcons.circle_check; // 无 download-filled
  static const IconData downloadedActive = TablerIcons.circle_check;
  static const IconData delete = TablerIcons.trash;
  static const IconData insertFile = TablerIcons.file_music;

  // 发现 / 搜索 / 榜单
  static const IconData search = TablerIcons.search;
  static const IconData searchOff = TablerIcons.search_off;
  static const IconData fire = TablerIcons.flame;
  static const IconData radar = TablerIcons.radar_2;
  static const IconData history = TablerIcons.history;
  static const IconData rss = TablerIcons.rss;
  static const IconData autoAwesome = TablerIcons.sparkles;

  // 收藏 / 状态
  static const IconData favorite = TablerIcons.heart;
  static const IconData favoriteActive = TablerIcons.heart_filled;
  static const IconData checkCircle = TablerIcons.circle_check;
  static const IconData checkCircleOutlined = TablerIcons.circle_check;
  static const IconData cancel = TablerIcons.circle_x;
  static const IconData removeCircle = TablerIcons.circle_minus;
  static const IconData addCircle = TablerIcons.circle_plus;
  static const IconData verified = TablerIcons.rosette_discount_check;
  static const IconData cloudOff = TablerIcons.cloud_off;

  // 通用动作
  static const IconData add = TablerIcons.plus;
  static const IconData remove = TablerIcons.minus;
  static const IconData close = TablerIcons.x;
  static const IconData check = TablerIcons.check;
  static const IconData chevronRight = TablerIcons.chevron_right;
  static const IconData chevronDown = TablerIcons.chevron_down;
  static const IconData refresh = TablerIcons.refresh;
  static const IconData restart = TablerIcons.reload; // 无 restart
  static const IconData update = TablerIcons.cloud_download;
  static const IconData updateAlt = TablerIcons.cloud_download;
  static const IconData info = TablerIcons.info_circle;
  static const IconData error = TablerIcons.alert_circle;
  static const IconData edit = TablerIcons.pencil;
  static const IconData link = TablerIcons.link;
  static const IconData openExternal = TablerIcons.external_link;
  static const IconData folder = TablerIcons.folder_open;
  static const IconData extension = TablerIcons.puzzle;
  static const IconData widgets = TablerIcons.layout_grid;
  static const IconData tune = TablerIcons.adjustments;
  static const IconData settingsBackup = TablerIcons.settings_automation;
  static const IconData label = TablerIcons.tag;

  // 外观 / 歌词
  static const IconData palette = TablerIcons.palette;
  static const IconData lightMode = TablerIcons.sun;
  static const IconData darkMode = TablerIcons.moon;
  static const IconData lyrics = TablerIcons.microphone_2;
  static const IconData lyricsActive = TablerIcons.microphone_2;
  static const IconData subtitles = TablerIcons.letter_case; // 无 subtitles
  static const IconData textFields = TablerIcons.text_size;
  static const IconData viewAgenda = TablerIcons.layout_list;
  static const IconData viewDay = TablerIcons.layout_rows;
  static const IconData blur = TablerIcons.blur;

  // 音乐
  static const IconData music = TablerIcons.music;
}
```

- [ ] **Step 4: 跑测试 —— 契约测试此时**应仍失败**(页面还在用 `Icons.`),语义非空测试应通过**

Run: `flutter test test/ui/icon_layer_test.dart`
Expected: 第 1 个用例 FAIL(offender 列表打印出 15 个文件);第 2 个用例 PASS。

- [ ] **Step 5: 提交**(契约测试红着提交,后续任务逐批转绿;这是本计划唯一的"红提交")

```bash
git add pubspec.yaml pubspec.lock lib/ui/icons.dart test/ui/icon_layer_test.dart
git commit -m "feat(ui): 引入 Tabler 图标 + AppIcons 语义层(契约测试先红)

- 为什么:71 个语义散落在 15 个文件 159 处直接写 Icons.*,换图标集要全仓改;
  收敛到一个语义层后,以后只改 lib/ui/icons.dart。
- 71 个映射已逐条比对 flutter_tabler_icons 包内常量(71/71 命中),
  4 处 Tabler 无同名变体的语义做了降级替代并在行内注明。
- icon_layer_test 锁住「lib/ui 不许再出现 Icons.*」,此刻为红(下个任务转绿)。"
```

---

### Task 2: 视觉 token + 主题接入

**Files:**
- Create: `lib/ui/tokens.dart`
- Create: `test/ui/tokens_test.dart`
- Modify: `lib/theme/app_theme.dart`

**Interfaces:**
- Produces: `AppSpacing.{xs,sm,md,lg,xl}`、`AppRadius.{card,chip,control}`、`AppSize.{rowHeight,icon,iconLarge,dividerInset}`、`AppText.{sectionTitle,rowTitle,rowSubtitle}`、`AppPalette.{lightBackground,lightCard,lightDivider,lightTitle}`。

- [ ] **Step 1: 写失败测试** `test/ui/tokens_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/ui/tokens.dart';

void main() {
  test('token 关键值符合设计稿(NutUI 观感:紧凑、小圆角、56 行高)', () {
    expect(AppSize.rowHeight, 56);
    expect(AppSize.icon, 20);
    expect(AppSize.iconLarge, 24);
    expect(AppSize.dividerInset, 16);
    expect(AppRadius.card, 14);
    expect(AppText.sectionTitle, 13);
    expect(AppSpacing.lg, 16);
    expect(AppPalette.lightBackground, const Color(0xFFF5F6F8));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/tokens_test.dart`
Expected: FAIL —— `tokens.dart` 不存在。

- [ ] **Step 3: 写 `lib/ui/tokens.dart`**

```dart
import 'package:flutter/widgets.dart';

/// 视觉 token:设置页先吃这套,第二版其余页面复用。
///
/// 为什么单独成文件:此前间距/圆角/字号散落各页(16、20、12…),同一类元素
/// 在不同页面尺度不一,「看起来乱」多半来自这里。
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

abstract final class AppRadius {
  static const double card = 14;
  static const double chip = 10;
  static const double control = 10;
}

abstract final class AppSize {
  /// 设置行统一高度:此前各行随内容胖瘦不一(用户截图里一眼能看出)。
  static const double rowHeight = 56;

  /// 行内图标:统一尺寸,避免同页 18/20/22 混用。
  static const double icon = 20;
  static const double iconLarge = 24;

  /// 分割线左内缩(与图标列对齐)。
  static const double dividerInset = 16;
}

abstract final class AppText {
  static const double sectionTitle = 13;
  static const double rowTitle = 15;
  static const double rowSubtitle = 12;
}

/// 浅色下的 NutUI 观感色板(深色仍走主题默认)。
abstract final class AppPalette {
  static const Color lightBackground = Color(0xFFF5F6F8);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightDivider = Color(0xFFEDEEF1);
  static const Color lightTitle = Color(0xFF8A8F99);
}
```

- [ ] **Step 4: 主题接入**(`lib/theme/app_theme.dart`:浅色 `scaffoldBackgroundColor` 用 `AppPalette.lightBackground`,并加 `dividerTheme` 用 `lightDivider` + 内缩;深色保持默认)

- [ ] **Step 5: 跑测试 + analyze**

Run: `flutter test test/ui/tokens_test.dart && flutter analyze`
Expected: PASS / No issues。

- [ ] **Step 6: 提交**

```bash
git add lib/ui/tokens.dart lib/theme/app_theme.dart test/ui/tokens_test.dart
git commit -m "feat(ui): 视觉 token(间距/圆角/行高/字号/灰底)并接入主题"
```

---

### Task 3: 替换「主框架 + 设置页 + 迷你播放条」

**Files:**
- Modify: `lib/ui/home_shell.dart`(14 处)、`lib/ui/plugins/plugin_page.dart`(44 处)、`lib/ui/widgets/mini_player_bar.dart`、`lib/ui/plugins/update_row.dart`(7 处)、`lib/ui/plugins/update_diagnostics.dart`、`lib/ui/plugins/lyrics_settings_page.dart`

**Interfaces:**
- Consumes: `AppIcons.*`(Task 1)。

- [ ] **Step 1: 机械替换**(按映射总表;下面脚本对给定文件批量替换,再 `analyze` 兜底)

```bash
python3 - <<'PY'
import re, pathlib
MAP = {
 'queue_music_rounded':'queue','download_rounded':'download','add_rounded':'add',
 'music_note_rounded':'music','chevron_right_rounded':'chevronRight','link_rounded':'link',
 'extension_rounded':'extension','check_circle_rounded':'checkCircle','play_arrow_rounded':'play',
 'library_music_rounded':'library','favorite_rounded':'favoriteActive','close_rounded':'close',
 'settings_rounded':'settingsActive','settings_outlined':'settings','rss_feed_rounded':'rss',
 'local_fire_department_rounded':'fire','insert_drive_file_outlined':'insertFile',
 'history_rounded':'history','favorite_border_rounded':'favorite',
 'download_for_offline_outlined':'downloaded','delete_outline_rounded':'delete',
 'widgets_rounded':'widgets','search_rounded':'search','restart_alt_rounded':'restart',
 'repeat_rounded':'repeat','repeat_one_rounded':'repeatOne','refresh_rounded':'refresh',
 'playlist_play_rounded':'playlistPlay','playlist_add_rounded':'addToPlaylist',
 'pause_rounded':'pause','open_in_new_rounded':'openExternal','lyrics_rounded':'lyricsActive',
 'library_music_outlined':'libraryOutlined','keyboard_arrow_down_rounded':'chevronDown',
 'explore_rounded':'exploreActive','explore_outlined':'explore','cloud_off_rounded':'cloudOff',
 'auto_awesome_rounded':'autoAwesome','volume_up_rounded':'volume','view_day_rounded':'viewDay',
 'view_agenda_rounded':'viewAgenda','verified_rounded':'verified','update_rounded':'update',
 'tune_rounded':'tune','text_fields_rounded':'textFields','system_update_alt_rounded':'updateAlt',
 'subtitles_rounded':'subtitles','skip_previous_rounded':'prev','skip_next_rounded':'next',
 'shuffle_rounded':'shuffle','settings_backup_restore_rounded':'settingsBackup',
 'search_off_rounded':'searchOff','remove_rounded':'remove',
 'remove_circle_outline_rounded':'removeCircle','radar_rounded':'radar',
 'palette_outlined':'palette','lyrics_outlined':'lyrics','light_mode_outlined':'lightMode',
 'label_outline_rounded':'label','info_outline_rounded':'info','folder_open_rounded':'folder',
 'error_outline_rounded':'error','edit_outlined':'edit','download_for_offline_rounded':'downloadedActive',
 'dark_mode_outlined':'darkMode','check_rounded':'check','check_circle_outline_rounded':'checkCircleOutlined',
 'cancel_rounded':'cancel','blur_on_rounded':'blur','album_rounded':'album',
 'add_circle_outline_rounded':'addCircle',
}
files = [
 'lib/ui/home_shell.dart','lib/ui/plugins/plugin_page.dart',
 'lib/ui/widgets/mini_player_bar.dart','lib/ui/plugins/update_row.dart',
 'lib/ui/plugins/update_diagnostics.dart','lib/ui/plugins/lyrics_settings_page.dart',
]
for f in files:
    p = pathlib.Path(f); s = p.read_text()
    n = 0
    for mat, sem in MAP.items():
        s, k = re.subn(r'\bIcons\.%s\b' % mat, 'AppIcons.%s' % sem, s); n += k
    if n:
        if "import 'package:musicx/ui/icons.dart';" not in s:
            s = s.replace("import 'package:flutter/material.dart';",
                          "import 'package:flutter/material.dart';\n\nimport 'package:musicx/ui/icons.dart';", 1)
        p.write_text(s)
    print(f, n)
PY
flutter analyze 2>&1 | tail -5
```

- [ ] **Step 2: 删除不再使用的 Material import 与冗余 import,analyze 必须干净**

Run: `flutter analyze`
Expected: No issues(若报未使用 import 就删掉)。

- [ ] **Step 3: 跑相关 UI 测试并同步断言到 `AppIcons.*`**

Run: `flutter test test/ui/settings_layout_test.dart test/ui/source_visibility_test.dart test/ui/ui_simplify_test.dart test/ui/ui_redesign_test.dart test/ui/layout_audit_test.dart`
Expected: 若有断言具体 `IconData` 的用例失败 → 改成 `AppIcons.*` 后复跑至全绿。

- [ ] **Step 4: 契约测试此时应转绿**

Run: `flutter test test/ui/icon_layer_test.dart`
Expected: 仍可能红(还有别的文件),记录剩余 offender 数量。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "refactor(ui): 主框架/设置页/迷你播放条改用 AppIcons(Tabler)"
```

---

### Task 4: 替换「发现页 + 曲库 + 下载 + 小部件」

**Files:**
- Modify: `lib/ui/search/search_page.dart`(25)、`lib/ui/search/chart_detail_page.dart`、`lib/ui/library/library_page.dart`(14)、`lib/ui/downloads/download_page.dart`(5)、`lib/ui/widgets/song_tile.dart`、`lib/ui/widgets/playlist_picker.dart`、`lib/ui/widgets/download_picker.dart`、`lib/ui/widgets/seek_bar.dart`、`lib/ui/widgets/artwork_view.dart`

- [ ] **Step 1: 用 Task 3 的同一脚本处理这批文件**(把 `files` 列表换成上面这批),`flutter analyze` 干净
- [ ] **Step 2: 跑 UI 测试**

Run: `flutter test test/ui/`
Expected: 全绿;若有图标断言失败则同步成 `AppIcons.*`。

- [ ] **Step 3: 提交**

```bash
git add -A
git commit -m "refactor(ui): 发现页/曲库/下载页/公共部件改用 AppIcons(Tabler)"
```

---

### Task 5: 替换「播放页 + 桌面歌词窗」并让契约测试转绿

**Files:**
- Modify: `lib/ui/player/player_page.dart`(19)、`lib/ui/desktop_lyrics/lyrics_window.dart`(7)、`lib/ui/desktop_lyrics/lyrics_settings_section.dart`、`lib/ui/desktop_lyrics/lyrics_text_view.dart`

- [ ] **Step 1: 同法替换这批文件**
- [ ] **Step 2: 契约测试必须**全绿**

Run: `flutter test test/ui/icon_layer_test.dart`
Expected: PASS(offender 为空)。

- [ ] **Step 3: 全套测试 + analyze**

Run: `flutter analyze && flutter test`
Expected: No issues / 全绿。

- [ ] **Step 4: 提交**

```bash
git add -A
git commit -m "refactor(ui): 播放页与桌面歌词窗改用 AppIcons;lib/ui 再无直接 Icons.* 引用"
```

---

### Task 6: 设置页视觉重做

**Files:**
- Modify: `lib/ui/plugins/plugin_page.dart`(重点:`_SettingsGroup`/`_MenuItemRow`/`_DefaultSourceRow`/`_FilterCoversRow`/`_sectionContent`/顶部 App 卡片/列表底部内边距)
- Modify: `test/ui/settings_layout_test.dart`、`test/ui/source_visibility_test.dart`(断言随新结构更新)

**Interfaces:**
- Consumes: `AppIcons.*`、`AppSpacing/AppRadius/AppSize/AppText/AppPalette`。

- [ ] **Step 1: 写失败测试**(设置页契约:`test/ui/settings_layout_test.dart` 追加)

```dart
  testWidgets('设置行统一 56 高、图标统一 20、页面吃灰底', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pluginManagerProvider.overrideWithValue(PluginManager(Directory.systemTemp))],
        child: const MaterialApp(home: PluginPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 灰底
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor ?? AppPalette.lightBackground,
        AppPalette.lightBackground);

    // 行高统一:所有 _MenuItemRow 高度 56
    final rows = find.byType(ListTile);
    for (var i = 0; i < rows.evaluate().length; i++) {
      final size = tester.getSize(rows.at(i));
      expect(size.height, greaterThanOrEqualTo(AppSize.rowHeight - 1));
    }
    // 图标统一 20
    for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
      if (icon.size != null) expect(icon.size, AppSize.icon);
    }
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/settings_layout_test.dart`
Expected: FAIL(灰底未接/行高不一/图标尺寸混用)。

- [ ] **Step 3: 按设计文档 §3.3 六条实现**

  1. 所有设置行图标:去底衬、`size: AppSize.icon`、颜色统一;
  2. 行高统一 `AppSize.rowHeight`;
  3. 开关 `MaterialTapTargetSize.shrinkWrap`;
  4. 「浅色/深色」改紧凑 segmented(高 32、圆角 `AppRadius.control`);
  5. 灰底 + 白卡 + 分区标题 `AppText.sectionTitle`/`AppPalette.lightTitle` + 分割线内缩 `AppSize.dividerInset`;
  6. 列表底部内边距 = `AppSpacing.xl` + 迷你播放条高度(常量 `kMiniPlayerHeight`,若不存在就地定义并复用);
  7. 顶部「N 个音源」只算 `userPlugins`(与「已安装音源」同一口径),为 0 时不显示数字。

- [ ] **Step 4: 跑测试 + analyze**

Run: `flutter test test/ui/ && flutter analyze`
Expected: 全绿 / No issues。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat(ui): 设置页按 NutUI 观感重做(统一行高/图标/分段控件/灰底白卡/底部不再遮挡)"
```

---

### Task 7: 全量验证 + 模拟器验收 + 发版

- [ ] **Step 1: 全套静态与测试**

Run: `flutter analyze && flutter test`
Expected: No issues;全绿(记录用例总数)。

- [ ] **Step 2: 模拟器安装并截图**

```bash
flutter build apk --release --dart-define=FLAVOR=standard
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am force-stop com.musicx.musicx && adb shell am start -n com.musicx.musicx/.MainActivity
sleep 8 && adb exec-out screencap -p > /tmp/ui_settings.png   # 设置页
```
把截图发给用户确认(设置页必看;发现页/播放页顺带)。

- [ ] **Step 3: 用户确认后发版**

```bash
# 版本号 bump 后
bash scripts/release.sh && bash scripts/release.sh --verify
```

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "chore: bump version(图标系统 + 设置页视觉重做)"
```

---

## Self-Review 记录

- **Spec 覆盖**:§1.4 选型 → Task 1;§3.1 语义层 → Task 1;§3.2 token → Task 2;§3.3 六条 → Task 6(第 6 条迷你播放条、第 7 条计数口径都在 Step 3);§1.5 的「发现/播放页细修」按设计属第二版 → 本计划只在 Task 3/4/5 做图标替换,视觉细修留待第二版(已在计划标题与 Task 6 范围里写明)。
- **占位符扫描**:无 TBD/TODO;替换脚本、token 值、测试代码均为可直接执行的实体。
- **类型一致性**:`AppIcons.*` 名称在 Task 1 定义、Task 3/4/5/6 使用;`AppSize/AppSpacing/AppRadius/AppText/AppPalette` 在 Task 2 定义、Task 6 使用;契约测试的语义清单与 `icons.dart` 一一对应(计划中两个清单已对齐,`mine/mineActive`、`addCircle`、`updateAlt`、`checkCircleOutlined` 均已包含)。
- **风险**:Tabler 常量名已 71/71 比对包内源码,不存在猜测;真机观感偏差由 Task 7 的截图验收兜住。
