import 'package:flutter/services.dart';

/// 安卓原生能力:读版本号 + 调起系统安装器。
///
/// 通道名与 `android/app/src/main/kotlin/.../MainActivity.kt` 保持一致。
/// 非安卓平台上调用会抛 MissingPluginException,调用方需自行 try/catch。
class ApkInstaller {
  ApkInstaller._();

  static const MethodChannel channel = MethodChannel('musicx/installer');

  /// 读取安卓 versionName(如 "1.7.2")。
  static Future<String?> versionName() async {
    final v = await channel.invokeMethod<String>('getVersionName');
    return v;
  }

  /// 是否允许安装未知来源应用(Android 8+ 必须,否则安装会静默失败)。
  static Future<bool> canInstallPackages() async {
    try {
      return await channel.invokeMethod<bool>('canInstallPackages') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 打开「安装未知应用」授权页。
  static Future<void> openInstallPermissionSettings() async {
    try {
      await channel.invokeMethod<bool>('openInstallPermissionSettings');
    } catch (_) {}
  }

  /// 监听「回到前台」:用于检测应用是否已被新版本替换,进而自动重启。
  static void listenResume(void Function() onResume) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onResume') onResume();
      return null;
    });
  }

  /// 重启应用(加载刚安装的新版本代码)。安卓实现;其它平台忽略。
  static Future<void> restartApp() async {
    try {
      await channel.invokeMethod<bool>('restartApp');
    } catch (_) {}
  }

  /// 已安装应用的 versionCode(安卓);非安卓或失败返回 null。
  static Future<int?> versionCode() async {
    try {
      return await channel.invokeMethod<int>('getVersionCode');
    } catch (_) {
      return null;
    }
  }

  /// 读取某个 APK 文件的 versionCode(安装前核对用);失败返回 null。
  static Future<int?> versionCodeOf(String path) async {
    try {
      return await channel.invokeMethod<int>('apkVersionCode', {'path': path});
    } catch (_) {
      return null;
    }
  }

  /// 把下载好的 APK 交给系统安装器。返回是否成功调起。
  static Future<bool> installApk(String path) async {
    final ok = await channel.invokeMethod<bool>('installApk', {'path': path});
    return ok ?? false;
  }
}
