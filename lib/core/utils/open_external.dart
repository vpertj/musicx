import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// 用系统文件管理器打开目录 / 用默认应用打开文件(跨平台)。
///
/// - macOS:`open`
/// - Windows:`explorer`
/// - Linux:`xdg-open`
/// - Android/iOS:无等效命令行(返回 false,由调用方兜底)。
///
/// 返回是否成功发起打开操作。
Future<bool> openPath(String path) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
      return true;
    }
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
      return true;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
      return true;
    }
  } catch (_) {
    return false;
  }
  return false;
}

/// 用系统默认方式打开外部 URL(如 GitHub Release 页)。
///
/// 桌面平台走系统命令,移动端用 url_launcher 拉起浏览器。
Future<bool> openExternalUrl(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
      return true;
    }
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
      return true;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
      return true;
    }
  } catch (_) {
    // 落到 url_launcher 兜底
  }
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
