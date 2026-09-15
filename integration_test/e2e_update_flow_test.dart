@Tags(['network'])
library;

// 真机端到端:检查更新 → 下载 → 安装前校验(完整性/格式/包名/版本)。
// 不实际调起系统安装器(那需要点系统 UI),其余路径全部真实执行。
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:musicx/core/updater/install_decision.dart';
import 'package:musicx/core/updater/update_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('升级全链路校验', (tester) async {
    final svc = UpdateService();
    final info = await svc.checkForUpdate();
    debugPrint('FLOW|检测到 最新=v${info.latestVersion} 当前=v${info.currentVersion}');
    debugPrint('FLOW|下载地址=${info.dmgUrl}');
    expect(info.dmgUrl, isNotEmpty, reason: '必须给出安装包直链');

    var lastPct = -1;
    final pkg = await svc.download(
      info.dmgUrl,
      onProgress: (p) {
        final pct = (p * 100).toInt();
        if (pct != lastPct && pct % 20 == 0) {
          lastPct = pct;
          debugPrint('FLOW|下载进度 $pct%');
        }
      },
    );
    debugPrint('FLOW|下载完成 size=${await pkg.length()}');

    final r = await svc.verifyPackageForInstall(
      path: pkg.path,
      expectedVersion: info.latestVersion,
    );
    debugPrint('FLOW|校验结果=${r.decision.name} '
        'apk=${r.apkPackageName ?? "?"}v${r.apkVersion ?? "?"}(${r.apkCode}) '
        'installed=${r.installedVersion}');
    // 目标版本比当前新时应可安装;若设备已是该版本则应判为已是最新
    expect(
      [InstallDecision.install, InstallDecision.alreadyLatest],
      contains(r.decision),
      reason: '真实安装包必须通过校验(不能是 invalid/mismatchRetry)',
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
