import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 窗口类型标识(写入 WindowConfiguration.arguments)。
const kLyricsWindowType = 'lyrics';

/// 主窗口 ⇄ 歌词窗口 的跨引擎通道名(uni directional:歌词窗口注册 handler)。
const kLyricsChannelName = 'musicx_desktop_lyrics';

/// 主窗口 → 歌词窗口:更新当前歌词。
const kLyricsUpdateMethod = 'update';

/// 主窗口 → 歌词窗口:关闭浮窗。
const kLyricsCloseMethod = 'close';

/// 桌面歌词浮窗:独立窗口(独立 Flutter 引擎),无边框 + 置顶 + 半透明 + 可拖动。
///
/// 数据来源:主窗口通过 unidirectional [WindowMethodChannel] 推送当前/下一句歌词。
class LyricsWindow extends StatefulWidget {
  const LyricsWindow({super.key});

  @override
  State<LyricsWindow> createState() => _LyricsWindowState();
}

class _LyricsWindowState extends State<LyricsWindow> {
  static const WindowMethodChannel _channel = WindowMethodChannel(
    kLyricsChannelName,
    mode: ChannelMode.unidirectional,
  );

  String _current = '';
  String _next = '';
  bool _hasSong = false;

  @override
  void initState() {
    super.initState();
    _configureWindow();
    _listenToMain();
  }

  /// 无边框 + 置顶 + 透明 + 初始位置/尺寸(子窗口的 window_manager 控制自身)。
  Future<void> _configureWindow() async {
    try {
      await windowManager.ensureInitialized();
      const options = WindowOptions(
        size: Size(760, 140),
        backgroundColor: Colors.transparent,
        skipTaskbar: true,
        titleBarStyle: TitleBarStyle.hidden,
        alwaysOnTop: true,
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.setAsFrameless();
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setHasShadow(false);
        await windowManager.setPosition(const Offset(160, 140));
        await windowManager.show();
      });
    } catch (_) {
      // 平台不支持窗口控制时静默降级(仍显示歌词)。
    }
  }

  Future<void> _listenToMain() async {
    try {
      await _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case kLyricsUpdateMethod:
            final arg = call.arguments;
            if (arg is Map && mounted) {
              setState(() {
                _current = (arg['current'] as String?) ?? '';
                _next = (arg['next'] as String?) ?? '';
                _hasSong = (arg['hasSong'] as bool?) ?? false;
              });
            }
          case kLyricsCloseMethod:
            try {
              await windowManager.close();
            } catch (_) {}
        }
        return null;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final line = _hasSong
        ? (_current.isEmpty ? '♪ 前奏…' : _current)
        : 'MusicX 桌面歌词';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 拖动:按住歌词条移动窗口。
          onPanStart: (_) {
            try {
              windowManager.startDragging();
            } catch (_) {}
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFF5A76),
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_next.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _next,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 解析窗口参数,判断是否歌词窗口。
bool isLyricsWindowArguments(String? arguments) {
  if (arguments == null || arguments.isEmpty) return false;
  try {
    final map = jsonDecode(arguments) as Map<String, dynamic>;
    return map['type'] == kLyricsWindowType;
  } catch (_) {
    return false;
  }
}
