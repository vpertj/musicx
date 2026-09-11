import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 窗口类型标识(写入 WindowConfiguration.arguments)。
const kLyricsWindowType = 'lyrics';

/// 主窗口 ⇄ 歌词窗口 的跨引擎通道名(unidirectional:歌词窗口注册 handler)。
const kLyricsChannelName = 'musicx_desktop_lyrics';

/// 主窗口 → 歌词窗口:更新当前歌词。
const kLyricsUpdateMethod = 'update';

/// 主窗口 → 歌词窗口:关闭浮窗。
const kLyricsCloseMethod = 'close';

/// 浮窗尺寸(由主窗口/自身按需调整)。
const Size kLyricsWindowSize = Size(880, 190);

const Color _kAccent = Color(0xFFFF5A76);

/// 桌面歌词浮窗(磨砂玻璃风):独立窗口 + 无边框 + 置顶 + 透明 + 可拖动。
///
/// 玻璃质感:半透明渐变底 + 背景模糊(BackdropFilter)+ 高光描边 + 柔和投影。
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

  Future<void> _configureWindow() async {
    try {
      await windowManager.ensureInitialized();
      const options = WindowOptions(
        size: kLyricsWindowSize,
        backgroundColor: Colors.transparent,
        skipTaskbar: true,
        titleBarStyle: TitleBarStyle.hidden,
        alwaysOnTop: true,
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.setAsFrameless();
        await windowManager.setAlwaysOnTop(true);
        // 自绘投影,关闭系统窗口阴影以免与圆角冲突。
        await windowManager.setHasShadow(false);
        await windowManager.setPosition(const Offset(180, 160));
        await windowManager.show();
      });
    } catch (_) {}
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
        : 'MusicX · 桌面歌词';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            try {
              windowManager.startDragging();
            } catch (_) {}
          },
          child: Padding(
            // 留出投影空间,避免被窗口裁掉
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            child: _GlassCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _AccentBar(),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kAccent,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: 0.5,
                            shadows: [
                              Shadow(
                                color: Color(0x66FF5A76),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                        ),
                        if (_next.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _next,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 19,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 毛玻璃卡片:背景模糊 + 半透明渐变 + 高光描边 + 柔和投影 + 大圆角。
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(26));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 34,
            spreadRadius: -4,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              // 玻璃底:左上偏亮、右下偏深的半透明渐变
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.18),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 18,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 左侧律动感竖条(品牌红渐变),提升“大气”质感。
class _AccentBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kAccent, Color(0x33FF5A76)],
        ),
        boxShadow: [
          BoxShadow(
            color: _kAccent.withValues(alpha: 0.55),
            blurRadius: 14,
          ),
        ],
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
