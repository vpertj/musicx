import 'package:flutter/material.dart';

/// MusicX 主题:深色沉浸优先,紫→粉渐变强调色。
class AppTheme {
  AppTheme._();

  /// 品牌紫罗兰
  static const Color violet = Color(0xFF8B5CF6);
  /// 强调粉
  static const Color pink = Color(0xFFEC4899);
  /// 辅助橙
  static const Color orange = Color(0xFFF59E0B);

  static const Color bgDark = Color(0xFF0D0A16);
  static const Color surfaceDark = Color(0xFF171226);
  static const Color surfaceDarkHi = Color(0xFF1F1930);

  static const Color bgLight = Color(0xFFF7F5FC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceLightHi = Color(0xFFF0ECF9);

  /// 主题渐变(播放键、进度条、徽标等)
  static const LinearGradient accentGradient = LinearGradient(
    colors: [violet, pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 柔和品牌渐变(封面占位、插件图标等)
  static const LinearGradient softGradient = LinearGradient(
    colors: [Color(0xFF5B3FB8), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        background: bgDark,
        surface: surfaceDark,
        surfaceHi: surfaceDarkHi,
        onSurface: const Color(0xFFEDE9F6),
        muted: const Color(0xFF8B84A3),
        outline: const Color(0xFF3E3557),
      );

  static ThemeData get light => _build(
        brightness: Brightness.light,
        background: bgLight,
        surface: surfaceLight,
        surfaceHi: surfaceLightHi,
        onSurface: const Color(0xFF1C1630),
        muted: const Color(0xFF6B6591),
        outline: const Color(0xFFD5CFE8),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceHi,
    required Color onSurface,
    required Color muted,
    required Color outline,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: violet,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? const Color(0xFFB39DFF) : const Color(0xFF6D28D9),
      onPrimary: isDark ? const Color(0xFF1E0B46) : Colors.white,
      secondary: pink,
      onSurface: onSurface,
      surface: surface,
      surfaceContainer: surfaceHi,
      surfaceContainerHigh: isDark ? const Color(0xFF241D38) : const Color(0xFFEAE5F5),
      surfaceContainerHighest: isDark ? const Color(0xFF2A2242) : const Color(0xFFE2DCF1),
      outline: outline,
      error: isDark ? const Color(0xFFFF6B81) : const Color(0xFFD63A5B),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? surface.withValues(alpha: .92)
            : surface.withValues(alpha: .95),
        indicatorColor: violet.withValues(alpha: .26),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? onSurface : muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? onSurface : muted,
            size: 23,
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: isDark ? .06 : .5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHi,
        hintStyle: TextStyle(color: muted),
        prefixIconColor: muted,
        suffixIconColor: muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: violet, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? const Color(0xFF241D38)
            : const Color(0xFFEAE5F5),
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: onSurface),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHi,
        contentTextStyle: TextStyle(color: onSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: muted.withValues(alpha: .5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceHi,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: onSurface.withValues(alpha: .8),
          fontSize: 14,
          height: 1.5,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: isDark ? .07 : .12),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: onSurface,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2242) : const Color(0xFF35305C),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: violet,
        linearTrackColor: surfaceHi,
      ),
    );
  }
}
