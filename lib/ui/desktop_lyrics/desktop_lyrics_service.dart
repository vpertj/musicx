import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'lyrics_window.dart';

/// 桌面歌词浮窗管理:创建 / 关闭 / 推送歌词(仅桌面平台)。
///
/// 浮窗是独立窗口(独立引擎),不共享主窗口状态;歌词通过
/// unidirectional [WindowMethodChannel] 推送(唯一 handler = 歌词窗口)。
class DesktopLyricsService {
  DesktopLyricsService._();

  static String? _windowId;

  /// 仅 macOS / Windows / Linux 支持多窗口浮窗。
  static bool get supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static const WindowMethodChannel _channel = WindowMethodChannel(
    kLyricsChannelName,
    mode: ChannelMode.unidirectional,
  );

  static Future<bool> isOpen() async {
    if (!supported) return false;
    if (_windowId != null) return true;
    try {
      final all = await WindowController.getAll();
      for (final c in all) {
        if (isLyricsWindowArguments(c.arguments)) {
          _windowId = c.windowId;
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static Future<void> open() async {
    if (!supported) return;
    if (await isOpen()) return;
    final controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({'type': kLyricsWindowType}),
      ),
    );
    _windowId = controller.windowId;
    await controller.show();
  }

  static Future<void> close() async {
    final id = _windowId;
    _windowId = null;
    if (id == null) return;
    try {
      // 通知歌词窗口自行关闭(它用 window_manager 控制自身窗口)。
      await _channel.invokeMethod(kLyricsCloseMethod);
    } catch (_) {}
  }

  static Future<void> toggle() async {
    if (await isOpen()) {
      await close();
    } else {
      await open();
    }
  }

  /// 推送当前歌词状态到浮窗(浮窗未开时为空操作)。
  static Future<void> push({
    required String current,
    required String next,
    required bool playing,
    required bool hasSong,
  }) async {
    if (_windowId == null) return;
    try {
      await _channel.invokeMethod(kLyricsUpdateMethod, {
        'current': current,
        'next': next,
        'playing': playing,
        'hasSong': hasSong,
      });
    } catch (_) {}
  }
}
