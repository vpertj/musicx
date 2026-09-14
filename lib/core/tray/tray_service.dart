// lib/core/tray/tray_service.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'tray_menu.dart';

/// 托盘刷新所需的应用状态快照。
class TrayStateInput {
  const TrayStateInput({
    required this.playing,
    required this.lyricsOpen,
    this.windowVisible = true,
    this.songTitle,
  });

  final bool playing;
  final bool lyricsOpen;
  final bool windowVisible;
  final String? songTitle;

  String get _signature =>
      '$playing|$lyricsOpen|$windowVisible|$songTitle';
}

/// 托盘菜单动作(由宿主注入,服务不依赖 riverpod)。
class TrayActions {
  const TrayActions({
    required this.playPause,
    required this.previous,
    required this.next,
    required this.showHide,
    required this.toggleLyrics,
    required this.quit,
  });

  final VoidCallback playPause;
  final VoidCallback previous;
  final VoidCallback next;
  final VoidCallback showHide;
  final VoidCallback toggleLyrics;
  final VoidCallback quit;
}

/// 系统托盘(macOS 菜单栏 / Windows 通知区)。
///
/// 服务只做原生通道与事件分发;菜单内容由纯函数 [buildTrayMenuItems]
/// 生成,应用状态由宿主经 [refresh] 注入。状态未变化时跳过重建,
/// 因此宿主可以放心地高频调用(如 250ms 定时器)。
class TrayService with TrayListener {
  TrayService._();

  static final TrayService instance = TrayService._();

  /// 仅 macOS / Windows 提供托盘。
  static bool get supported => Platform.isMacOS || Platform.isWindows;

  TrayActions? _actions;
  String? _lastSignature;

  /// 初始化托盘图标与菜单。宿主在主窗口启动时调用一次。
  Future<void> init({
    required TrayStateInput Function() state,
    required TrayActions actions,
  }) async {
    if (!supported) return;
    _state = state;
    _actions = actions;
    _lastSignature = null;
    trayManager.addListener(this);
    try {
      await trayManager.setIcon(
        'assets/tray_icon.png',
        isTemplate: true, // macOS:黑色 + alpha,菜单栏自动适配深浅色
      );
      await trayManager.setToolTip('MusicX');
      await refresh(force: true);
    } catch (_) {}
  }

  TrayStateInput Function()? _state;

  /// 按当前状态重建菜单;签名未变则跳过。
  Future<void> refresh({bool force = false}) async {
    if (!supported) return;
    final input = _state?.call();
    if (input == null) return;
    final sig = input._signature;
    if (!force && sig == _lastSignature) return;
    _lastSignature = sig;
    try {
      await trayManager.setContextMenu(
        Menu(
          items: buildTrayMenuItems(
            playing: input.playing,
            lyricsOpen: input.lyricsOpen,
            windowVisible: input.windowVisible,
            songTitle: input.songTitle,
          ).map(_toNativeItem).toList(),
        ),
      );
    } catch (_) {}
  }

  MenuItem _toNativeItem(TrayMenuItemSpec spec) {
    if (spec.isSeparator) return MenuItem.separator();
    return MenuItem(
      key: spec.key,
      label: spec.label,
      disabled: spec.disabled,
      checked: spec.checked ?? false,
    );
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final a = _actions;
    if (a == null) return;
    switch (menuItem.key) {
      case kTrayItemPlayPause:
        a.playPause();
      case kTrayItemPrevious:
        a.previous();
      case kTrayItemNext:
        a.next();
      case kTrayItemShowHide:
        a.showHide();
      case kTrayItemToggleLyrics:
        a.toggleLyrics();
      case kTrayItemQuit:
        a.quit();
    }
  }

  /// 左键点图标 = 弹出菜单。
  ///
  /// macOS 上 [TrayManager.setContextMenu] 只缓存菜单,不挂到 statusItem;
  /// 必须主动 [TrayManager.popUpContextMenu] 才能显示(与插件官方示例一致)。
  @override
  void onTrayIconMouseDown() {
    try {
      trayManager.popUpContextMenu();
    } catch (_) {}
  }
}
