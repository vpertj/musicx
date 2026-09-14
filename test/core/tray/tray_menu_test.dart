// test/core/tray/tray_menu_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/tray/tray_menu.dart';

void main() {
  test('播放中显示「暂停」,未播放显示「播放」', () {
    expect(
      buildTrayMenuItems(playing: true, lyricsOpen: false)
          .firstWhere((e) => e.key == kTrayItemPlayPause)
          .label,
      '暂停',
    );
    expect(
      buildTrayMenuItems(playing: false, lyricsOpen: false)
          .firstWhere((e) => e.key == kTrayItemPlayPause)
          .label,
      '播放',
    );
  });

  test('桌面歌词开关反映勾选状态', () {
    final on = buildTrayMenuItems(playing: false, lyricsOpen: true);
    expect(
      on.firstWhere((e) => e.key == kTrayItemToggleLyrics).checked,
      isTrue,
    );
    final off = buildTrayMenuItems(playing: false, lyricsOpen: false);
    expect(
      off.firstWhere((e) => e.key == kTrayItemToggleLyrics).checked,
      isFalse,
    );
  });

  test('歌名为空时标题项显示应用名且禁用', () {
    final items = buildTrayMenuItems(playing: false, lyricsOpen: false);
    final title = items.first;
    expect(title.disabled, isTrue);
    expect(title.label, 'MusicX');
    final withSong = buildTrayMenuItems(
      playing: false,
      lyricsOpen: false,
      songTitle: '花海 - 周杰伦',
    );
    expect(withSong.first.label, '花海 - 周杰伦');
    expect(withSong.first.disabled, isTrue);
  });

  test('菜单结构:标题 / 控制区 / 分隔 / 显示隐藏与歌词 / 分隔 / 退出', () {
    final items = buildTrayMenuItems(
      playing: true,
      lyricsOpen: true,
      songTitle: '花海',
    );
    expect(items.map((e) => e.key).toList(), [
      kTrayItemTitle,
      kTrayItemPrevious,
      kTrayItemPlayPause,
      kTrayItemNext,
      null, // separator
      kTrayItemShowHide,
      kTrayItemToggleLyrics,
      null, // separator
      kTrayItemQuit,
    ]);
    expect(
      items.firstWhere((e) => e.key == kTrayItemShowHide).label,
      '隐藏主窗口',
    );
    final hidden =
        buildTrayMenuItems(playing: true, lyricsOpen: true, windowVisible: false);
    expect(
      hidden.firstWhere((e) => e.key == kTrayItemShowHide).label,
      '显示主窗口',
    );
  });
}
