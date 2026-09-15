// test/e2e_update_download_test.dart
//
// 真实网络回归:**完整下载 62MB 的 release APK 并校验 SHA256**。
//
// 这条链路是国内用户能否升级的关键:直连 release 资产
// (release-assets.githubusercontent.com,实际落在 Azure Blob)经常断流,
// 需要回退到免费加速代理。测试证明:
//   ① 多源回退真的能拿到完整文件;
//   ② 通过代理拿到的字节与 GitHub 官方 digest 完全一致。
//
// 默认跳过(耗时且依赖外网);本地/发版前用 --dart-define 显式开启:
//   flutter test test/e2e_update_download_test.dart --dart-define=RUN_NET_E2E=1
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/update_service.dart';

/// 是否执行真实网络下载。
///
/// 用环境变量而非 `bool.fromEnvironment`:后者在 `flutter test --dart-define`
/// 下不可靠(实测取不到值,导致用例被静默跳过)。
final _run = Platform.environment['RUN_NET_E2E'] == '1';

void main() {
  test('e2e: 多源回退能完整下载 release APK 且 SHA256 与官方一致', () async {
    if (!_run) {
      // ignore: avoid_print
      print('SKIP: 未开启网络 E2E(用 RUN_NET_E2E=1 flutter test ...)');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('musicx_e2e_dl');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    final service = UpdateService(downloadDir: tmp);
    final info = await service.checkForUpdate();

    // ignore: avoid_print
    print('最新版本=${info.latestVersion} 资产=${info.dmgUrl}');
    // ignore: avoid_print
    print('官方 SHA256=${info.dmgSha256}');
    expect(info.dmgUrl, isNotEmpty, reason: '应能解析出安装包直链');

    final file = await service.download(
      info.dmgUrl,
      expectedSha256: info.dmgSha256,
      version: info.latestVersion,
      onProgress: (p) {
        if (p < 0) {
          // ignore: avoid_print
          print('换源重试(进度归零)');
        }
      },
    );

    expect(file.existsSync(), isTrue);
    final actual = sha256.convert(file.readAsBytesSync()).toString();
    // ignore: avoid_print
    print('实际 SHA256=$actual size=${file.lengthSync()}');
    if (info.dmgSha256 != null && info.dmgSha256!.isNotEmpty) {
      expect(actual, info.dmgSha256,
          reason: '下载内容必须与 GitHub 官方 digest 逐字节一致');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
