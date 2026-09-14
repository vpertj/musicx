import 'dart:ui' show Color, Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:musicx/core/settings/settings_providers.dart';

/// 桌面歌词浮窗外观设置。持久化到 settings.json 的 `desktopLyrics` 键。
class DesktopLyricsSettings {
  const DesktopLyricsSettings({
    this.textColor = defaultTextColor,
    this.nextColor = defaultNextColor,
    this.fontSize = 34,
    this.autoScale = true,
    this.showNext = true,
    this.showArtwork = true,
    this.glassTint = 45,
    this.blurSigma = 38,
    this.cornerRadius = 26,
    this.bounds,
  });

  static const Color defaultTextColor = Color(0xFFFF5A76);
  static const Color defaultNextColor = Color(0xB8FFFFFF); // 白 72%

  static const double minFontSize = 12;
  static const double maxFontSize = 120;
  static const int minGlassTint = 0;
  static const int maxGlassTint = 100;
  static const double minBlurSigma = 0;
  static const double maxBlurSigma = 60;
  static const double minCornerRadius = 0;
  static const double maxCornerRadius = 60;

  /// 当前句颜色。
  final Color textColor;

  /// 下一句颜色。
  final Color nextColor;

  /// 基准字号;[autoScale] 开启时按窗口高度等比缩放。
  final double fontSize;
  final bool autoScale;

  /// 是否显示下一句(窗口高度不足时布局会强制隐藏)。
  final bool showNext;

  /// 是否用专辑封面做模糊背景(关掉退化为纯彩色玻璃)。
  final bool showArtwork;

  /// 暗色遮罩浓度 0–100。
  final int glassTint;

  /// 封面模糊强度 0–60。
  final double blurSigma;

  /// 卡片圆角基准值 0–60(布局会再按窗口缩放并夹取)。
  final double cornerRadius;

  /// 上次窗口几何(逻辑坐标);null 表示从未记录。
  final Rect? bounds;

  DesktopLyricsSettings copyWith({
    Color? textColor,
    Color? nextColor,
    double? fontSize,
    bool? autoScale,
    bool? showNext,
    bool? showArtwork,
    int? glassTint,
    double? blurSigma,
    double? cornerRadius,
    Rect? bounds,
    bool clearBounds = false,
  }) {
    return DesktopLyricsSettings(
      textColor: textColor ?? this.textColor,
      nextColor: nextColor ?? this.nextColor,
      fontSize: fontSize ?? this.fontSize,
      autoScale: autoScale ?? this.autoScale,
      showNext: showNext ?? this.showNext,
      showArtwork: showArtwork ?? this.showArtwork,
      glassTint: glassTint ?? this.glassTint,
      blurSigma: blurSigma ?? this.blurSigma,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      bounds: clearBounds ? null : (bounds ?? this.bounds),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DesktopLyricsSettings &&
        other.textColor == textColor &&
        other.nextColor == nextColor &&
        other.fontSize == fontSize &&
        other.autoScale == autoScale &&
        other.showNext == showNext &&
        other.showArtwork == showArtwork &&
        other.glassTint == glassTint &&
        other.blurSigma == blurSigma &&
        other.cornerRadius == cornerRadius &&
        other.bounds == bounds;
  }

  @override
  int get hashCode => Object.hash(
        textColor,
        nextColor,
        fontSize,
        autoScale,
        showNext,
        showArtwork,
        glassTint,
        blurSigma,
        cornerRadius,
        bounds,
      );

  /// 把所有数值收敛到合法区间,防止手改配置导致界面异常。
  DesktopLyricsSettings clamp() {
    return DesktopLyricsSettings(
      textColor: textColor,
      nextColor: nextColor,
      fontSize: fontSize.clamp(minFontSize, maxFontSize),
      autoScale: autoScale,
      showNext: showNext,
      showArtwork: showArtwork,
      glassTint: glassTint.clamp(minGlassTint, maxGlassTint),
      blurSigma: blurSigma.clamp(minBlurSigma, maxBlurSigma),
      cornerRadius: cornerRadius.clamp(minCornerRadius, maxCornerRadius),
      bounds: bounds,
    );
  }

  Map<String, dynamic> toJson() {
    final b = bounds;
    return <String, dynamic>{
      'textColor': textColor.toARGB32(),
      'nextColor': nextColor.toARGB32(),
      'fontSize': fontSize,
      'autoScale': autoScale,
      'showNext': showNext,
      'showArtwork': showArtwork,
      'glassTint': glassTint,
      'blurSigma': blurSigma,
      'cornerRadius': cornerRadius,
      if (b != null)
        'bounds': {
          'x': b.left,
          'y': b.top,
          'w': b.width,
          'h': b.height,
        },
    };
  }

  factory DesktopLyricsSettings.fromJson(Map<String, dynamic> json) {
    return DesktopLyricsSettings(
      textColor: _color(json['textColor'], defaultTextColor),
      nextColor: _color(json['nextColor'], defaultNextColor),
      fontSize: _double(json['fontSize'], 34),
      autoScale: _bool(json['autoScale'], true),
      showNext: _bool(json['showNext'], true),
      showArtwork: _bool(json['showArtwork'], true),
      glassTint: _int(json['glassTint'], 45),
      blurSigma: _double(json['blurSigma'], 38),
      cornerRadius: _double(json['cornerRadius'], 26),
      bounds: _rect(json['bounds']),
    ).clamp();
  }

  static Color _color(Object? raw, Color fallback) {
    final v = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (v == null || v < 0 || v > 0xFFFFFFFF) return fallback;
    return Color(v);
  }

  static double _double(Object? raw, double fallback) {
    if (raw is num) {
      final v = raw.toDouble();
      return v.isFinite ? v : fallback;
    }
    final v = double.tryParse('$raw');
    return v ?? fallback;
  }

  /// 容错读取 double:接受 num 或可解析的字符串;NaN/Infinity 与垃圾值都返回 null。
  static double? _doubleOrNull(Object? raw) {
    if (raw is num) {
      final v = raw.toDouble();
      return v.isFinite ? v : null;
    }
    final v = double.tryParse('$raw');
    return (v != null && v.isFinite) ? v : null;
  }

  static int _int(Object? raw, int fallback) {
    if (raw is num) return raw.round();
    return int.tryParse('$raw') ?? fallback;
  }

  static bool _bool(Object? raw, bool fallback) =>
      raw is bool ? raw : fallback;

  static Rect? _rect(Object? raw) {
    if (raw is! Map) return null;
    final x = _doubleOrNull(raw['x']);
    final y = _doubleOrNull(raw['y']);
    final w = _doubleOrNull(raw['w']);
    final h = _doubleOrNull(raw['h']);
    if (x == null || y == null || w == null || h == null) return null;
    if (w <= 0 || h <= 0) return null;
    return Rect.fromLTWH(x, y, w, h);
  }
}

/// 歌词外观设置控制器:主窗口是唯一写者(浮窗只读 + 接收推送)。
class DesktopLyricsSettingsController extends Notifier<DesktopLyricsSettings> {
  @override
  DesktopLyricsSettings build() {
    try {
      final map = ref.watch(settingsStoreProvider).readAll();
      final raw = map['desktopLyrics'];
      return DesktopLyricsSettings.fromJson(
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{},
      );
    } catch (_) {
      return const DesktopLyricsSettings();
    }
  }

  /// 更新并持久化(经合并写,不影响其它设置)。
  void update(DesktopLyricsSettings next) {
    final value = next.clamp();
    state = value;
    ref.read(settingsStoreProvider).merge({'desktopLyrics': value.toJson()});
  }
}

final desktopLyricsSettingsProvider =
    NotifierProvider<DesktopLyricsSettingsController, DesktopLyricsSettings>(
      DesktopLyricsSettingsController.new,
    );
