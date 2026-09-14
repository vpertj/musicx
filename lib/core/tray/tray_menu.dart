// lib/core/tray/tray_menu.dart

/// 托盘菜单项 key(事件分发用,与文案解耦)。
const kTrayItemTitle = 'title';
const kTrayItemPrevious = 'previous';
const kTrayItemPlayPause = 'playPause';
const kTrayItemNext = 'next';
const kTrayItemShowHide = 'showHide';
const kTrayItemToggleLyrics = 'toggleLyrics';
const kTrayItemQuit = 'quit';

/// 托盘菜单项描述:纯数据,由 [buildTrayMenuItems] 生成,
/// TrayService 负责翻译成原生菜单并分发点击事件。
class TrayMenuItemSpec {
  const TrayMenuItemSpec({
    required this.key,
    required this.label,
    this.disabled = false,
    this.checked,
    this.isSeparator = false,
  });

  /// 分隔线。
  const TrayMenuItemSpec.separator()
      : key = null,
        label = '',
        disabled = false,
        checked = null,
        isSeparator = true;

  /// 事件分发 key;分隔线为 null。
  final String? key;

  /// 显示文案。
  final String label;

  /// 灰色不可点(如标题项)。
  final bool disabled;

  /// 勾选态(null = 普通项,不显示 checkbox)。
  final bool? checked;

  final bool isSeparator;
}

/// 根据应用状态生成托盘菜单项(纯函数,便于单测)。
List<TrayMenuItemSpec> buildTrayMenuItems({
  required bool playing,
  required bool lyricsOpen,
  bool windowVisible = true,
  String? songTitle,
}) {
  final title = (songTitle == null || songTitle.isEmpty) ? 'MusicX' : songTitle;
  return [
    TrayMenuItemSpec(key: kTrayItemTitle, label: title, disabled: true),
    const TrayMenuItemSpec(
      key: kTrayItemPrevious,
      label: '上一首',
    ),
    TrayMenuItemSpec(
      key: kTrayItemPlayPause,
      label: playing ? '暂停' : '播放',
    ),
    const TrayMenuItemSpec(key: kTrayItemNext, label: '下一首'),
    const TrayMenuItemSpec.separator(),
    TrayMenuItemSpec(
      key: kTrayItemShowHide,
      label: windowVisible ? '隐藏主窗口' : '显示主窗口',
    ),
    TrayMenuItemSpec(
      key: kTrayItemToggleLyrics,
      label: '桌面歌词',
      checked: lyricsOpen,
    ),
    const TrayMenuItemSpec.separator(),
    const TrayMenuItemSpec(key: kTrayItemQuit, label: '退出 MusicX'),
  ];
}
