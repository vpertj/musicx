// test/core/updater/install_decision_test.dart
//
// 用户反复遇到「更新后系统提示已安装相同版本」。这里锁死安装前的决策:
// 只有确凿更新才交给安装器,其余情况都给可读原因。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/install_decision.dart';

void main() {
  InstallDecision decide({
    int? apkCode = 48,
    String? apkName = '1.7.29',
    int? installed = 47,
    String expected = '1.7.29',
    String? apkPkg = 'com.musicx.musicx',
  }) => decideInstall(
    apkVersionCode: apkCode,
    apkVersionName: apkName,
    installedVersionCode: installed,
    expectedVersion: expected,
    apkPackageName: apkPkg,
    expectedPackageName: 'com.musicx.musicx',
  );

  test('确实更新 → 交给安装器', () {
    expect(decide(), InstallDecision.install);
  });

  test('安装包不高于已装版本 → 判为已是最新(不再调起安装器)', () {
    expect(decide(apkCode: 47, installed: 47), InstallDecision.alreadyLatest);
    expect(decide(apkCode: 46, installed: 47), InstallDecision.alreadyLatest);
  });

  test('下到的版本名与目标不一致 → 重下一次(防串版本)', () {
    expect(
      decide(apkName: '1.7.28', expected: '1.7.29'),
      InstallDecision.mismatchRetry,
    );
  });

  test('读不到版本号 → 判为无效(fail-closed,不交给安装器)', () {
    expect(decide(apkCode: null), InstallDecision.invalid);
    expect(decide(apkCode: -1), InstallDecision.invalid);
    expect(decide(installed: null), InstallDecision.invalid);
    expect(decide(installed: -1), InstallDecision.invalid);
  });

  test('包名不是本应用 → 判为无效(防装错应用)', () {
    expect(decide(apkPkg: 'com.evil.app'), InstallDecision.invalid);
    expect(decide(apkPkg: null), InstallDecision.install,
        reason: '读不到包名时不额外拦截(Android 安装器还会校验签名)');
  });

  test('版本名缺失但 versionCode 确凿更新 → 仍可安装', () {
    expect(decide(apkName: ''), InstallDecision.install);
  });
}
