import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/core/updater/apk_installer.dart';
import 'package:musicx/core/utils/app_paths.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_window.dart';
import 'ui/home_shell.dart';

/// 升级自愈:记录启动时的版本号,回到前台时若发现应用已被新版本替换
/// (versionCode 变了)就自动重启,避免用户停在旧版本界面。
/// 用户反馈:装完新版本,应用里还是旧版本 —— 根因是旧进程仍在运行。
Future<void> _watchForUpgrade() async {
  if (!Platform.isAndroid) return;
  final atLaunch = await ApkInstaller.versionCode();
  if (atLaunch == null || atLaunch <= 0) return;
  ApkInstaller.listenResume(() async {
    final now = await ApkInstaller.versionCode();
    if (now != null && now != atLaunch) {
      await ApkInstaller.restartApp();
    }
  });
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面歌词浮窗是独立窗口(独立引擎):先判断当前引擎是否歌词窗口。
  String? windowArguments;
  try {
    final controller = await WindowController.fromCurrentEngine();
    windowArguments = controller.arguments;
  } catch (_) {
    // 非桌面平台或插件不可用:按主窗口处理。
  }
  if (isLyricsWindowArguments(windowArguments)) {
    // 浮窗也要能读 settings.json(首帧样式),先初始化数据目录。
    await AppPaths.init();
    runApp(const ProviderScope(child: LyricsWindow()));
    return;
  }

  // 初始化跨平台数据目录(path_provider)后再启动 UI,
  // 确保各 Controller 读取到正确的数据/插件路径。
  await AppPaths.init();
  unawaited(_watchForUpgrade());

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