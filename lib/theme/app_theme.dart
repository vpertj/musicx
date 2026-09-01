import 'package:flutter/material.dart';

/// MusicX 主题:「月光极简」——黑白灰骨架 + 品牌红点缀。
///
/// 浅色为默认,深色可手动切换。所有颜色经语义常量引用,不散落硬编码。
/// 旧紫粉渐变常量(accentGradient/softGradient/violet/pink/orange)为
/// 过渡占位,待全项目替换为品牌红后删除(见实现计划 Task 6)。
class AppTheme {
  AppTheme._();

  // ---- 品牌红(唯一彩色点缀)----
  static const Color accent = Color(0xFFFA3B4D); // 浅色品牌红
  static const Color accentDark = Color(0xFFFF4559); // 深色品牌红
  static const Color accentSoft = Color(0xFFFFEDEE); // 浅色红底
  static const Color accentSoftDark = Color(0xFF3A2225); // 深色红底

  // ---- 渐变(现为品牌红单色系,移除紫粉;用于装饰背景)----
  // 深→浅品牌红,视觉统一为品牌红点缀。
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFC4343F), Color(0xFFFA3B4D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient softGradient = LinearGradient(
    colors: [Color(0xFFFA3B4D), Color(0xFFC4343F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ---- 语义色 Token(按亮度取色)----
  static Color _bg(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF121212) : const Color(0xFFFAFBFC);
  static Color _surface(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  static Color _surfaceHi(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF242629) : const Color(0xFFF2F3F5);
  static Color _text(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFF3F4F6) : const Color(0xFF1A1C1E);
  static Color _muted(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF9AA1AB) : const Color(0xFF8A8F98);
  static Color _divider(Brightness b) => b == Brightness.dark
      ? const Color(0xFF2C2F33)
      : const Color(0xFFE7E9EC);
  static Color _accent(Brightness b) => b == Brightness.dark ? accentDark : accent;
  static Color _accentSoft(Brightness b) =>
      b == Brightness.dark ? accentSoftDark : accentSoft;

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme(
      brightness: b,
      primary: _accent(b),
      onPrimary: Colors.white,
      secondary: _accent(b),
      onSecondary: Colors.white,
      surface: _surface(b),
      onSurface: _text(b),
      error: isDark ? const Color(0xFFFF6B81) : const Color(0xFFD63A5B),
      onError: Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
      scaffoldBackgroundColor: _bg(b),
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: _text(b),
        displayColor: _text(b),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _text(b),
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
        ),
        iconTheme: IconThemeData(color: _text(b)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surface(b).withValues(alpha: .95),
        indicatorColor: _accentSoft(b),
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
            color: selected ? _text(b) : _muted(b),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? _accent(b) : _muted(b), size: 23);
        }),
      ),
      cardTheme: CardThemeData(
        color: _surface(b),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceHi(b),
        hintStyle: TextStyle(color: _muted(b)),
        prefixIconColor: _muted(b),
        suffixIconColor: _muted(b),
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
          borderSide: BorderSide(color: _accent(b), width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _surfaceHi(b),
        side: BorderSide.none,
        labelStyle: TextStyle(color: _text(b), fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: _text(b)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _surfaceHi(b),
        contentTextStyle: TextStyle(color: _text(b)),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _surface(b),
        modalBackgroundColor: _surface(b),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: _muted(b).withValues(alpha: .5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _surfaceHi(b),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(color: _text(b), fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: _text(b).withValues(alpha: .8), fontSize: 14, height: 1.5),
      ),
      dividerTheme: DividerThemeData(color: _divider(b), thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(iconColor: _muted(b), textColor: _text(b)),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _accent(b),
        linearTrackColor: _surfaceHi(b),
      ),
    );
  }
}
