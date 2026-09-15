import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:musicx/core/updater/apk_installer.dart';
import 'package:musicx/core/updater/install_decision.dart';
import 'package:musicx/core/updater/update_service.dart';

/// 更新诊断面板:把「检查更新」每一步实际拿到的原始数据摊开显示。
///
/// 为什么需要它:真机上出现「明明有新版本却提示已是最新版本」时,
/// 从错误提示无法判断到底哪一环出了问题 —— 是网络走了降级路径、
/// 还是解析出了旧版本号、还是本机版本号读错。这个面板把三者同时列出,
/// 用户截一张图就能定位,不需要连电脑看日志。
class UpdateDiagnostics {
  /// 采集全部诊断信息。
  static Future<String> collect() async {
    final buf = StringBuffer();
    final service = UpdateService();

    // ① 本机信息(应用读到的,而非用户以为的)
    buf.writeln('【本机】');
    buf.writeln('  平台: ${Platform.operatingSystem}');
    if (Platform.isAndroid) {
      final name = await ApkInstaller.versionName();
      final code = await ApkInstaller.versionCode();
      final sig = await ApkInstaller.installedSignatureSha256();
      final allowed = await ApkInstaller.canInstallPackages();
      final apkPath = await ApkInstaller.installedApkPath();
      buf.writeln('  已装 versionName: ${name ?? "读取失败"}');
      buf.writeln('  已装 versionCode: ${code ?? "读取失败"}');
      buf.writeln('  签名指纹: ${InstallFacts.shortSha(sig) ?? "读取失败"}');
      buf.writeln('  允许安装未知应用: $allowed');
      buf.writeln('  APK 路径: ${apkPath ?? "读取失败"}');
    }
    buf.writeln('  resolveCurrentVersion(): ${await service.resolveCurrentVersion()}');
    buf.writeln('  knownVersion(): ${UpdateService.knownVersion() ?? "null"}');

    // ② 检查更新:分别记录"直连"与"降级"各自拿到什么
    buf.writeln('');
    buf.writeln('【检查更新】');
    try {
      final info = await service.checkForUpdate();
      buf.writeln('  latestVersion: ${info.latestVersion}');
      buf.writeln('  currentVersion: ${info.currentVersion}');
      buf.writeln('  hasUpdate: ${info.hasUpdate}');
      buf.writeln('  compareVersions(latest, current) = '
          '${compareVersions(info.latestVersion, info.currentVersion)}');
      buf.writeln('  资产直链: ${info.dmgUrl}');
      buf.writeln('  SHA256: ${info.dmgSha256 ?? "未提供(走了降级路径)"}');
      buf.writeln('  Release 页: ${info.releaseUrl}');
    } catch (e) {
      buf.writeln('  检查失败: $e');
    }
    return buf.toString();
  }
}

/// 诊断信息展示对话框(可滚动 + 可选中复制)。
Future<void> showUpdateDiagnostics(BuildContext context) async {
  // 只采集一次:复制按钮复用同一份文本,避免再跑一次网络检查
  // (既慢又可能拿到不一致的结果)。
  final future = UpdateDiagnostics.collect();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('更新诊断信息'),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<String>(
          future: future,
          builder: (c, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return SingleChildScrollView(
              child: SelectableText(
                snap.data!,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            // 一键复制:真机排查时用户不方便逐行念,直接粘贴发回来最快。
            final text = await future;
            await Clipboard.setData(ClipboardData(text: text));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('诊断信息已复制,可直接粘贴发送'),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },
          child: const Text('复制'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
