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
    String? apkSig,
    String? installedSig,
  }) => decideInstall(
    apkVersionCode: apkCode,
    apkVersionName: apkName,
    installedVersionCode: installed,
    expectedVersion: expected,
    apkPackageName: apkPkg,
    expectedPackageName: 'com.musicx.musicx',
    apkSignatureSha256: apkSig,
    installedSignatureSha256: installedSig,
  );

  // 真实指纹(取自本仓库 keystore 与 Android debug key),用于比对逻辑测试。
  const releaseSig =
      '5a373d38652c2c6b10c96c2e2451063b7db79b9796b1b11d66572bdddd46db18';
  const debugSig =
      'd09458a3f524f17118edf559df0f1195053faf951a46d9da2c9a594f0bb85a7d';

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

  group('签名校验(系统升级的硬前提)', () {
    test('签名一致 + 版本更新 → 交给安装器', () {
      expect(
        decide(apkSig: releaseSig, installedSig: releaseSig),
        InstallDecision.install,
      );
    });

    test('签名不一致 → 直接判签名不符(版本号再新也装不上)', () {
      // debug 包覆盖 release 包:versionCode 更大,但系统必然拒绝。
      // 必须在本地拦下,否则用户只看到系统那句含糊的「更新失败」。
      expect(
        decide(
          apkCode: 999,
          apkName: '9.9.9',
          expected: '9.9.9',
          apkSig: debugSig,
          installedSig: releaseSig,
        ),
        InstallDecision.signatureMismatch,
        reason: '签名不符必须优先于版本比较给出结论',
      );
    });

    test('大小写不同的同一指纹 → 仍视为一致', () {
      expect(
        decide(
          apkSig: releaseSig.toUpperCase(),
          installedSig: releaseSig.toLowerCase(),
        ),
        InstallDecision.install,
      );
    });

    test('读不到签名 → 不据此拦截(交给版本校验兜底)', () {
      expect(decide(apkSig: null, installedSig: releaseSig),
          InstallDecision.install);
      expect(decide(apkSig: releaseSig, installedSig: null),
          InstallDecision.install);
      expect(decide(apkSig: '', installedSig: ''),
          InstallDecision.install);
    });
  });

  group('InstallFacts.describe(失败原因必须能自证)', () {
    const facts = InstallFacts(
      apkVersionCode: 55,
      apkVersionName: '1.7.36',
      apkPackageName: 'com.musicx.musicx',
      apkSignatureSha256: releaseSig,
      installedVersionCode: 59,
      installedSignatureSha256: releaseSig,
      expectedVersion: '1.7.40',
    );

    test('包含版本号、versionCode 与签名结论', () {
      final text = facts.describe();
      expect(text, contains('1.7.36'));
      expect(text, contains('code 55'));
      expect(text, contains('code 59'));
      expect(text, contains('签名一致'));
      expect(text, contains('5a373d38'), reason: '展示短指纹便于比对');
    });

    test('签名不一致时明确指出两边指纹', () {
      const mismatch = InstallFacts(
        apkVersionCode: 60,
        apkVersionName: '1.7.41',
        apkPackageName: 'com.musicx.musicx',
        apkSignatureSha256: debugSig,
        installedVersionCode: 59,
        installedSignatureSha256: releaseSig,
        expectedVersion: '1.7.41',
      );
      expect(mismatch.describe(), contains('签名不一致'));
      expect(mismatch.describe(), contains('d09458a3'));
    });

    test('读不到签名时说明无法比对,而不是谎报一致', () {
      const unknown = InstallFacts(
        apkVersionCode: null,
        apkVersionName: null,
        apkPackageName: null,
        apkSignatureSha256: null,
        installedVersionCode: null,
        installedSignatureSha256: null,
        expectedVersion: '1.7.40',
      );
      expect(unknown.signatureMatches, isNull);
      expect(unknown.describe(), contains('无法比对'));
    });

    test('signatureMatches 对读不到的情况返回 null', () {
      expect(facts.signatureMatches, isTrue);
      expect(InstallFacts.shortSha(null), isNull);
      expect(InstallFacts.shortSha(releaseSig), '5a373d38');
    });
  });
}
