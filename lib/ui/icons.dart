import 'package:flutter/widgets.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

/// 全局图标**语义层**:页面只认这里的名字,换图标集只改这一个文件。
///
/// 设计见 `docs/superpowers/specs/2026-10-09-ui-icon-system-design.md`。
///
/// 约定:
/// - `xxx` = 常态(线性图标);`xxxActive` = 选中/激活(filled)。
/// - 尺寸与颜色**不写在这里**:统一由 `lib/ui/tokens.dart` 与调用点决定。
/// - Tabler 没有同名变体的语义做了降级替代,行内已注明原因。
/// - 页面禁止直接写 `Icons.*`,由 `test/ui/icon_layer_test.dart` 锁住。
abstract final class AppIcons {
  // ---- 底部导航 ----
  static const IconData explore = TablerIcons.compass;
  static const IconData exploreActive = TablerIcons.compass_filled;
  static const IconData mine = TablerIcons.user;
  static const IconData mineActive = TablerIcons.user_filled;
  static const IconData settings = TablerIcons.settings;
  static const IconData settingsActive = TablerIcons.settings_filled;

  // ---- 播放控制 ----
  static const IconData play = TablerIcons.player_play;
  static const IconData pause = TablerIcons.player_pause;
  static const IconData prev = TablerIcons.player_skip_back;
  static const IconData next = TablerIcons.player_skip_forward;
  static const IconData repeat = TablerIcons.repeat;
  static const IconData repeatOne = TablerIcons.repeat_once;
  static const IconData shuffle = TablerIcons.arrows_shuffle;
  static const IconData volume = TablerIcons.volume;

  // ---- 队列 / 曲库 / 下载 ----
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

  // ---- 发现 / 搜索 / 榜单 ----
  static const IconData search = TablerIcons.search;
  static const IconData searchOff = TablerIcons.search_off;
  static const IconData fire = TablerIcons.flame;
  static const IconData chart = TablerIcons.chart_bar; // 排行榜
  static const IconData radar = TablerIcons.radar_2;
  static const IconData history = TablerIcons.history;
  static const IconData rss = TablerIcons.rss;
  static const IconData autoAwesome = TablerIcons.sparkles;

  // ---- 收藏 / 状态 ----
  static const IconData favorite = TablerIcons.heart;
  static const IconData favoriteActive = TablerIcons.heart_filled;
  static const IconData checkCircle = TablerIcons.circle_check;
  static const IconData checkCircleOutlined = TablerIcons.circle_check;
  static const IconData cancel = TablerIcons.circle_x;
  static const IconData removeCircle = TablerIcons.circle_minus;
  static const IconData addCircle = TablerIcons.circle_plus;
  static const IconData verified = TablerIcons.rosette_discount_check;
  static const IconData cloudOff = TablerIcons.cloud_off;

  // ---- 通用动作 ----
  static const IconData add = TablerIcons.plus;
  static const IconData remove = TablerIcons.minus;
  static const IconData close = TablerIcons.x;
  static const IconData check = TablerIcons.check;
  static const IconData chevronRight = TablerIcons.chevron_right;
  static const IconData chevronDown = TablerIcons.chevron_down;
  static const IconData refresh = TablerIcons.refresh;
  static const IconData restart = TablerIcons.reload; // Tabler 无 restart
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

  // ---- 外观 / 歌词 ----
  static const IconData palette = TablerIcons.palette;
  static const IconData lightMode = TablerIcons.sun;
  static const IconData darkMode = TablerIcons.moon;
  static const IconData lyrics = TablerIcons.microphone_2;
  static const IconData lyricsActive = TablerIcons.microphone_2;
  static const IconData subtitles = TablerIcons.letter_case; // Tabler 无 subtitles
  static const IconData textFields = TablerIcons.text_size;
  static const IconData viewAgenda = TablerIcons.layout_list;
  static const IconData viewDay = TablerIcons.layout_rows;
  static const IconData blur = TablerIcons.blur;

  // ---- 音乐 ----
  static const IconData music = TablerIcons.music;
}
