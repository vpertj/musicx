import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/theme/app_theme.dart';
import 'ui/home_shell.dart';

void main() {
  runApp(const ProviderScope(child: MusicxApp()));
}

class MusicxApp extends StatelessWidget {
  const MusicxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MusicX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // 音乐 App 默认深色沉浸体验,系统浅色时仍可用浅色主题
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}