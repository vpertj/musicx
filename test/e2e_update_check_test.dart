// test/e2e_update_check_test.dart
//
// 真实网络回归:GitHub API 未认证必然频繁 403 限流,所以更新检查**必须**
// 能靠网页降级拿到安装包直链。此前的二次转义 bug 让降级路径永远失败,
// 用户看到「检查更新失败:最新 Release 中没有找到 DMG 安装包」。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/update_service.dart';

void main() {
  test('e2e: checkForUpdate 能在 API 限流的情况下拿到安装包直链', () async {
    final info = await UpdateService().checkForUpdate();

    expect(info.latestVersion, isNotEmpty);
    // 至少要有 Release 页链接;安装包直链必须是 GitHub 下载地址。
    expect(info.releaseUrl, contains('github.com'));
    if (UpdateService.canAutoInstall) {
      expect(
        info.dmgUrl,
        contains('/releases/download/'),
        reason: '降级或约定直链都必须给出可下载的安装包地址',
      );
      expect(
        info.dmgUrl.endsWith('.dmg') || info.dmgUrl.endsWith('.apk'),
        isTrue,
        reason: '当前平台应为 .dmg(macOS)或 .apk(Android)',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
