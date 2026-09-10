import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/core/utils/app_paths.dart';
import 'package:musicx/theme/app_theme.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化跨平台数据目录(path_provider)后再启动 UI,
  // 确保各 Controller 读取到正确的数据/插件路径。
  await AppPaths.init();
  runApp(const ProviderScope(child: MusicxApp()));
}

class MusicxApp extends ConsumerWidget {
  const MusicxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 主题偏好:默认浅色,手动切深色(持久化)。
    final themeMode = ref.watch(themePreferenceProvider);
    return MaterialApp(
      title: 'MusicX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const HomeShell(),
    );
  }
}