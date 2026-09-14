import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemMouseCursor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart' hide ResizeEdge;

import 'package:musicx/core/settings/desktop_lyrics_settings.dart';

import 'lyrics_glass.dart';
import 'lyrics_layout.dart';
import 'lyrics_text_view.dart';
import 'lyrics_resize.dart';

/// 窗口类型标识(写入 WindowConfiguration.arguments)。
const kLyricsWindowType = 'lyrics';

/// 主窗口 ⇄ 歌词窗口 的跨引擎通道名(unidirectional:歌词窗口注册 handler)。
const kLyricsChannelName = 'musicx_desktop_lyrics';

/// 主窗口 → 歌词窗口:更新当前歌词。
const kLyricsUpdateMethod = 'update';

/// 主窗口 → 歌词窗口:推送外观设置。
const kLyricsStyleMethod = 'style';

/// 浮窗 → 主窗口通道(unidirectional,handler = 主窗口)。
/// unidirectional 通道只允许一个引擎注册 handler,反向通信须独立建通道。
const kLyricsUpChannelName = 'musicx_desktop_lyrics_up';

/// 浮窗 → 主窗口:回传工具条改动(主窗口负责持久化)。
const kLyricsStyleUpMethod = 'styleChanged';

/// 浮窗 → 主窗口:把主程序唤到前台(双击歌词 / 工具条按钮)。
const kLyricsShowMainUpMethod = 'showMain';

/// 主窗口 → 歌词窗口:关闭浮窗。
const kLyricsCloseMethod = 'close';

/// 纯文字样式下的窗口内边距:没有卡片/投影,留白只为不裁切字形阴影。
const EdgeInsets kLyricsPlainPadding = EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 8,
);

/// 浮窗默认尺寸与默认位置(未记录几何时使用)。
const Size kLyricsWindowSize = Size(880, 190);
const Offset kLyricsDefaultPosition = Offset(180, 160);

/// 窗口内边距:既留出投影空间,也是缩放热区所在。
const EdgeInsets kLyricsWindowPadding = EdgeInsets.fromLTRB(18, 14, 18, 22);

/// 缩放热区厚度。
const double kLyricsResizeHotSize = 8;

/// 桌面歌词浮窗:独立窗口 + 无边框 + 置顶 + 透明 + 可拖动 + 可自由缩放。
class LyricsWindow extends ConsumerStatefulWidget {
  const LyricsWindow({super.key});

  @override
  ConsumerState<LyricsWindow> createState() => _LyricsWindowState();
}

class _LyricsWindowState extends ConsumerState<LyricsWindow> {
  static const WindowMethodChannel _channel = WindowMethodChannel(
    kLyricsChannelName,
    mode: ChannelMode.unidirectional,
  );

  static const WindowMethodChannel _upChannel = WindowMethodChannel(
    kLyricsUpChannelName,
    mode: ChannelMode.unidirectional,
  );

  String _current = '';
  String _next = '';
  bool _hasSong = false;
  String? _artwork;

  /// 生效中的外观:首帧取自 settings.json,此后以主窗口推送为准。
  DesktopLyricsSettings _style = const DesktopLyricsSettings();

  bool _hovering = false;
  bool _toolbarVisible = false;
  Timer? _toolbarTimer;
  Timer? _boundsSaveTimer;

  /// 缩放节流:单次在途,新目标覆盖旧目标。
  bool _resizeInFlight = false;
  Rect? _pendingResize;
  Rect? _liveResizeRect;

  @override
  void initState() {
    super.initState();
    _style = ref.read(desktopLyricsSettingsProvider);
    _configureWindow();
    _listenToMain();
  }

  @override
  void dispose() {
    _toolbarTimer?.cancel();
    _boundsSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _configureWindow() async {
    try {
      await windowManager.ensureInitialized();
      final restored = await _restoreBounds();
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
        if (restored != null) {
          await windowManager.setBounds(restored);
        } else {
          await windowManager.setPosition(kLyricsDefaultPosition);
        }
        await windowManager.show();
      });
    } catch (_) {}
  }

  /// 还原上次几何,并夹取到主屏工作区内(防止换显示器后窗口跑到屏幕外)。
  Future<Rect?> _restoreBounds() async {
    final saved = _style.bounds;
    if (saved == null || saved.width <= 0 || saved.height <= 0) return null;
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final origin = display.visiblePosition ?? Offset.zero;
      final visible = display.visibleSize ?? display.size;
      return clampRectToWorkArea(
        saved,
        Rect.fromLTWH(origin.dx, origin.dy, visible.width, visible.height),
      );
    } catch (_) {
      return saved;
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
                _artwork = arg['artwork'] as String?;
              });
            }
          case kLyricsStyleMethod:
            final arg = call.arguments;
            if (arg is Map && arg['style'] is Map && mounted) {
              setState(() {
                _style = DesktopLyricsSettings.fromJson(
                  Map<String, dynamic>.from(arg['style'] as Map),
                );
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

  // ── 拖动 ──────────────────────────────────────────────────────────

  void _startDrag() {
    try {
      windowManager.startDragging();
    } catch (_) {}
  }

  // ── 缩放 ──────────────────────────────────────────────────────────

  void _onResizeStart(ResizeEdge edge) {
    try {
      windowManager.getBounds().then((r) => _liveResizeRect = r);
    } catch (_) {}
  }

  void _onResizeUpdate(ResizeEdge edge, DragUpdateDetails d) {
    final base = _liveResizeRect;
    if (base == null) return; // 起始几何未取回前丢弃(几毫秒内)
    final next = resizeRect(current: base, edge: edge, delta: d.delta);
    _liveResizeRect = next;
    _applyBounds(next);
  }

  Future<void> _applyBounds(Rect rect) async {
    if (_resizeInFlight) {
      _pendingResize = rect;
      return;
    }
    _resizeInFlight = true;
    try {
      await windowManager.setBounds(rect);
    } catch (_) {}
    _resizeInFlight = false;
    final pending = _pendingResize;
    if (pending != null) {
      _pendingResize = null;
      await _applyBounds(pending);
    }
  }

  void _onResizeEnd() {
    _liveResizeRect = null;
    _scheduleBoundsSave();
  }

  /// 松手后 debounce 落盘窗口几何。
  void _scheduleBoundsSave() {
    _boundsSaveTimer?.cancel();
    _boundsSaveTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final b = await windowManager.getBounds();
        _sendStyleUp(_style.copyWith(bounds: b));
      } catch (_) {}
    });
  }

  // ── 工具条 ────────────────────────────────────────────────────────

  void _onEnter() {
    _hovering = true;
    _toolbarTimer?.cancel();
    _toolbarTimer = Timer(const Duration(milliseconds: 180), () {
      if (_hovering && mounted) setState(() => _toolbarVisible = true);
    });
  }

  void _onExit() {
    _hovering = false;
    _toolbarTimer?.cancel();
    _toolbarTimer = Timer(const Duration(milliseconds: 400), () {
      if (!_hovering && mounted) setState(() => _toolbarVisible = false);
    });
  }

  /// 应用工具条改动:本地立即生效 + 回传主窗口持久化。
  void _applyStyleChange(DesktopLyricsSettings next) {
    setState(() => _style = next);
    _sendStyleUp(next);
  }

  void _sendStyleUp(DesktopLyricsSettings next) {
    try {
      _upChannel.invokeMethod(kLyricsStyleUpMethod, {'style': next.toJson()});
    } catch (_) {}
  }

  Future<void> _resetSize() async {
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final origin = display.visiblePosition ?? Offset.zero;
      final visible = display.visibleSize ?? display.size;
      final rect = Rect.fromCenter(
        center: Offset(
          origin.dx + visible.width / 2,
          origin.dy + visible.height / 2,
        ),
        width: kLyricsWindowSize.width,
        height: kLyricsWindowSize.height,
      );
      _applyBounds(clampRectToWorkArea(rect,
          Rect.fromLTWH(origin.dx, origin.dy, visible.width, visible.height)));
    } catch (_) {}
    _applyStyleChange(_style.copyWith(clearBounds: true));
  }

  /// 唤出主程序:经上行通道请主窗口 show + focus。
  void _showMain() {
    try {
      _upChannel.invokeMethod(kLyricsShowMainUpMethod);
    } catch (_) {}
  }

  Future<void> _close() async {
    try {
      await windowManager.close();
    } catch (_) {}
  }

  // ── UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final line = _hasSong
        ? (_current.isEmpty ? '♪ 前奏…' : _current)
        : 'MusicX · 桌面歌词';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: MouseRegion(
          onEnter: (_) => _onEnter(),
          onExit: (_) => _onExit(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final windowSize = Size(constraints.maxWidth, constraints.maxHeight);
              final layout = resolveLyricsLayout(
                windowSize: windowSize,
                settings: _style,
                current: line,
                next: _next,
              );
              final content = LyricsTextView(
                layout: layout,
                settings: _style,
                current: line,
                next: _next,
              );
              final plain = _style.cardStyle == LyricsCardStyle.plain;
              return Stack(
                children: [
                  // 1) 歌词本体 + 窗口拖动(双击唤出主程序)
                  Positioned.fill(
                    child: Padding(
                      // 纯文字没有投影,窗口留白收到最小,视觉上「没有外框」
                      padding: plain ? kLyricsPlainPadding : kLyricsWindowPadding,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => _startDrag(),
                        onPanEnd: (_) => _scheduleBoundsSave(),
                        onDoubleTap: _showMain,
                        child: plain
                            ? content
                            : LyricsGlassCard(
                                settings: _style,
                                artworkUrl: _artwork,
                                radius: layout.cardRadius,
                                child: Padding(
                                  padding: layout.padding,
                                  child: content,
                                ),
                              ),
                      ),
                    ),
                  ),
                  // 2) 四边 + 四角缩放热区
                  ..._buildResizeHandles(),
                  // 3) 悬停工具条
                  if (_toolbarVisible)
                    Positioned(
                      top: 6,
                      right: 26,
                      child: _Toolbar(
                        settings: _style,
                        onFontSizeDelta: (d) => _applyStyleChange(
                          _style.copyWith(fontSize: _style.fontSize + d),
                        ),
                        onColor: (c) => _applyStyleChange(
                          _style.copyWith(textColor: c),
                        ),
                        onToggleNext: () => _applyStyleChange(
                          _style.copyWith(showNext: !_style.showNext),
                        ),
                        onShowMain: _showMain,
                        onResetSize: _resetSize,
                        onClose: _close,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 四边 + 四角热区:透明、带对应光标,拖拽时调用原生 setBounds。
  List<Widget> _buildResizeHandles() {
    const t = kLyricsResizeHotSize;

    Widget handle({
      required ResizeEdge edge,
      double? top,
      double? left,
      double? right,
      double? bottom,
      double? width,
      double? height,
      required SystemMouseCursor cursor,
    }) {
      return Positioned(
        top: top,
        left: left,
        right: right,
        bottom: bottom,
        width: width,
        height: height,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _onResizeStart(edge),
            onPanUpdate: (d) => _onResizeUpdate(edge, d),
            onPanEnd: (_) => _onResizeEnd(),
          ),
        ),
      );
    }

    return [
      handle(
        edge: ResizeEdge.top,
        top: 0, left: t, right: t, height: t,
        cursor: SystemMouseCursors.resizeUpDown,
      ),
      handle(
        edge: ResizeEdge.bottom,
        bottom: 0, left: t, right: t, height: t,
        cursor: SystemMouseCursors.resizeUpDown,
      ),
      handle(
        edge: ResizeEdge.left,
        left: 0, top: t, bottom: t, width: t,
        cursor: SystemMouseCursors.resizeLeftRight,
      ),
      handle(
        edge: ResizeEdge.right,
        right: 0, top: t, bottom: t, width: t,
        cursor: SystemMouseCursors.resizeLeftRight,
      ),
      handle(
        edge: ResizeEdge.topLeft,
        top: 0, left: 0, width: t, height: t,
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
      ),
      handle(
        edge: ResizeEdge.bottomRight,
        bottom: 0, right: 0, width: t, height: t,
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
      ),
      handle(
        edge: ResizeEdge.topRight,
        top: 0, right: 0, width: t, height: t,
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
      ),
      handle(
        edge: ResizeEdge.bottomLeft,
        bottom: 0, left: 0, width: t, height: t,
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
      ),
    ];
  }
}

/// 悬停工具条:半透明玻璃样式,字号/颜色/下一句/重置尺寸/关闭。
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.settings,
    required this.onFontSizeDelta,
    required this.onColor,
    required this.onToggleNext,
    required this.onShowMain,
    required this.onResetSize,
    required this.onClose,
  });

  final DesktopLyricsSettings settings;
  final ValueChanged<double> onFontSizeDelta;
  final ValueChanged<Color> onColor;
  final VoidCallback onToggleNext;
  final VoidCallback onShowMain;
  final VoidCallback onResetSize;
  final VoidCallback onClose;

  static const _quickColors = <Color>[
    Color(0xFFFF5A76),
    Color(0xFFFFFFFF),
    Color(0xFF8AD4FF),
    Color(0xFFFFD76A),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarButton(
              icon: Icons.remove_rounded,
              tooltip: '缩小字号',
              onTap: () => onFontSizeDelta(-2),
            ),
            _ToolbarButton(
              icon: Icons.add_rounded,
              tooltip: '放大字号',
              onTap: () => onFontSizeDelta(2),
            ),
            const SizedBox(width: 4),
            for (final c in _quickColors)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  onTap: () => onColor(c),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: settings.textColor == c
                          ? Border.all(color: Colors.white, width: 2)
                          : Border.all(color: Colors.white24),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            _ToolbarButton(
              icon: settings.showNext
                  ? Icons.view_agenda_rounded
                  : Icons.view_day_rounded,
              tooltip: settings.showNext ? '隐藏下一句' : '显示下一句',
              onTap: onToggleNext,
            ),
            _ToolbarButton(
              icon: Icons.open_in_new_rounded,
              tooltip: '回到主程序',
              onTap: onShowMain,
            ),
            _ToolbarButton(
              icon: Icons.settings_backup_restore_rounded,
              tooltip: '重置尺寸与位置',
              onTap: onResetSize,
            ),
            _ToolbarButton(
              icon: Icons.close_rounded,
              tooltip: '关闭桌面歌词',
              onTap: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.9)),
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
