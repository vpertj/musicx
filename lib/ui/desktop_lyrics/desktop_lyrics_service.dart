import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'package:musicx/core/settings/desktop_lyrics_settings.dart';

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
    final style = _lastStyle;
    if (style != null) {
      try {
        await _channel.invokeMethod(kLyricsStyleMethod, {
          'style': style.toJson(),
        });
      } catch (_) {}
    }
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
}
