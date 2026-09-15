// 真机探针:验证新增的签名指纹读取在**实际设备**上是否可用。
//
// 为什么需要这个探针:release APK 只用了 v2 签名方案(apksigner 显示
// "Verified using v1 scheme: false"),而 PackageManager.GET_SIGNATURES
// 是 v1 时代的 API。如果它在 v2-only 包上返回 null,整个签名校验就等于
// 没做,用户仍会看到含糊的「更新失败」。必须实证而不是假设。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:musicx/core/updater/apk_installer.dart';
import 'package:musicx/core/updater/update_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probe signature reading on device', (tester) async {
    final name = await ApkInstaller.versionName();
    final code = await ApkInstaller.versionCode();
    debugPrint('RESULT: versionName=$name versionCode=$code');

    final installedSig = await ApkInstaller.installedSignatureSha256();
    debugPrint('RESULT: installedSignatureSha256=$installedSig');

    // 用**自己已安装的 base.apk** 当作「下载到的安装包」来验证文件侧读取:
    // 期望两侧指纹一致(同一个包),这同时证明了读取路径可用。
    final selfApk = await ApkInstaller.installedApkPath();
    debugPrint('RESULT: selfApk=$selfApk');
    if (selfApk != null) {
      final apkSig = await ApkInstaller.signatureSha256Of(selfApk);
      debugPrint('RESULT: apkSignatureSha256=$apkSig');
      debugPrint('RESULT: signaturesMatch=${installedSig == apkSig}');
    }

    // 决策自检:同一个包 versionCode 不高于已装 → 应为 alreadyLatest
    if (selfApk != null) {
      final result = await UpdateService().verifyPackageForInstall(
        path: selfApk,
        expectedVersion: name ?? '',
      );
      debugPrint('RESULT: decision=${result.decision.name}');
      debugPrint('RESULT: describe=${result.facts.describe()}');
    }

    // 端到端反差验证:拿一个**签名不同**的 release APK(adb push 到 /data/local/tmp)
    // 走真实校验链路,期望得到 signatureMismatch —— 而不是含糊的 alreadyLatest。
    // 这正是用户「更新失败:已安装最新版本」背后被掩盖的真实原因。
    final foreign = await _pushTargetPath();
    if (foreign != null) {
      final sig = await ApkInstaller.signatureSha256Of(foreign);
      debugPrint('RESULT: foreignSig=$sig installedSig=$installedSig');
      final r = await UpdateService().verifyPackageForInstall(
        path: foreign,
        expectedVersion: '1.7.41',
      );
      debugPrint('RESULT: foreignDecision=${r.decision.name}');
      debugPrint('RESULT: foreignDescribe=${r.facts.describe()}');
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}

/// 由测试前 adb push 准备好的、**签名不同**的 release APK 路径。
/// 设备上应用只能读自己的私有目录与 /data/local/tmp 之外的受限路径,
/// 因此这里探测几个可能位置,读不到就跳过该项验证。
Future<String?> _pushTargetPath() async {
  for (final p in const [
    '/data/local/tmp/foreign.apk',
    '/sdcard/Download/foreign.apk',
  ]) {
    final exists = await File(p).exists();
    if (exists) return p;
  }
  return null;
}
