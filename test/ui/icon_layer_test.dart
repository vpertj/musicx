// test/ui/icon_layer_test.dart
//
// 图标层契约(设计:docs/superpowers/specs/2026-10-09-ui-icon-system-design.md)
//
// 背景:71 个语义散落在 15 个文件、159 处直接写 `Icons.*`,换图标集就得全仓改。
// 收敛到 `lib/ui/icons.dart` 语义层后,以后只改一处。本文件锁住两件事:
//   1. 页面**不许**直接引用 Material 图标(迁移期间用白名单逐任务收缩);
//   2. 语义层常量齐备(缺一个就是编译错,这里再兜一层)。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/ui/icons.dart';

/// 迁移白名单:这些文件还写着 `Icons.*`,按计划 Task 3/4/5 逐批替换。
///
/// **Task 5 完成后本集合必须为空**(空集合 = 严格锁死),这是本次改动的验收条件之一。
const Set<String> kMigratingFiles = {
  'lib/ui/home_shell.dart',
  'lib/ui/plugins/plugin_page.dart',
  'lib/ui/plugins/update_row.dart',
  'lib/ui/widgets/mini_player_bar.dart',
  'lib/ui/search/search_page.dart',
  'lib/ui/search/chart_detail_page.dart',
  'lib/ui/library/library_page.dart',
  'lib/ui/downloads/download_page.dart',
  'lib/ui/widgets/song_tile.dart',
  'lib/ui/widgets/playlist_picker.dart',
  'lib/ui/widgets/download_picker.dart',
  'lib/ui/widgets/artwork_view.dart',
  'lib/ui/player/player_page.dart',
  'lib/ui/desktop_lyrics/lyrics_window.dart',
  'lib/ui/desktop_lyrics/lyrics_settings_section.dart',
};

void main() {
  test('页面不许直接引用 Icons.*:必须走 AppIcons 语义层', () {
    final offenders = <String>[];
    for (final f in Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('ui/icons.dart')) continue; // 语义层自己
      if (kMigratingFiles.contains(f.path)) continue; // 迁移中
      final text = f.readAsStringSync();
      for (final m in RegExp(r'\bIcons\.[a-zA-Z_]+').allMatches(text)) {
        offenders.add('${f.path}: ${m.group(0)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '这些地方还在直接引用 Material 图标,请改用 AppIcons:\n${offenders.join('\n')}',
    );
  });

  test('语义层常量齐备(缺失会在编译期就暴露,这里再兜一层)', () {
    const icons = <IconData>[
      AppIcons.explore, AppIcons.exploreActive, AppIcons.mine, AppIcons.mineActive,
      AppIcons.settings, AppIcons.settingsActive, AppIcons.play, AppIcons.pause,
      AppIcons.prev, AppIcons.next, AppIcons.repeat, AppIcons.repeatOne,
      AppIcons.shuffle, AppIcons.volume, AppIcons.playlistPlay, AppIcons.queue,
      AppIcons.addToPlaylist, AppIcons.library, AppIcons.libraryOutlined,
      AppIcons.album, AppIcons.download, AppIcons.downloaded,
      AppIcons.downloadedActive, AppIcons.delete, AppIcons.insertFile,
      AppIcons.search, AppIcons.searchOff, AppIcons.fire, AppIcons.radar,
      AppIcons.history, AppIcons.rss, AppIcons.autoAwesome, AppIcons.favorite,
      AppIcons.favoriteActive, AppIcons.checkCircle, AppIcons.checkCircleOutlined,
      AppIcons.cancel, AppIcons.removeCircle, AppIcons.addCircle,
      AppIcons.verified, AppIcons.cloudOff, AppIcons.add, AppIcons.remove,
      AppIcons.close, AppIcons.check, AppIcons.chevronRight, AppIcons.chevronDown,
      AppIcons.refresh, AppIcons.restart, AppIcons.update, AppIcons.updateAlt,
      AppIcons.info, AppIcons.error, AppIcons.edit, AppIcons.link,
      AppIcons.openExternal, AppIcons.folder, AppIcons.extension,
      AppIcons.widgets, AppIcons.tune, AppIcons.settingsBackup, AppIcons.label,
      AppIcons.palette, AppIcons.lightMode, AppIcons.darkMode, AppIcons.lyrics,
      AppIcons.lyricsActive, AppIcons.subtitles, AppIcons.textFields,
      AppIcons.viewAgenda, AppIcons.viewDay, AppIcons.blur, AppIcons.music,
    ];
    // 73 个语义与 lib/ui/icons.dart 一一对应(改了语义层就要同步这份清单)
    expect(icons, hasLength(73));
    // 选中/未选中必须成对存在(底部导航与收藏用到),且不能是同一个字形。
    expect(AppIcons.explore, isNot(AppIcons.exploreActive));
    expect(AppIcons.favorite, isNot(AppIcons.favoriteActive));
    expect(AppIcons.settings, isNot(AppIcons.settingsActive));
  });
}
