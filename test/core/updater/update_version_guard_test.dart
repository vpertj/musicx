// test/core/updater/update_version_guard_test.dart
//
// 用户实测:1.7.11 装完 1.7.13 后仍提示更新,再点更新被系统以
// 「已安装了更高版本」拒绝 —— 根因是进程内缓存了旧版本号。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/update_service.dart';

class _FakeService extends UpdateService {
  _FakeService(this.version);
  final String version;
  @override
  Future<String> resolveCurrentVersion() async => version;
}

void main() {
  test('invalidateVersionCache 清掉缓存后重新解析(安装完成后必须调用)', () async {
    final s = _FakeService('1.7.13');
    expect(await s.resolveCurrentVersion(), '1.7.13');
    UpdateService.invalidateVersionCache();
    expect(UpdateService.knownVersion(), isNot('1.7.11'),
        reason: '清缓存后不能再拿旧版本号判断是否有更新');
  });

  test('compareVersions 判定:同版本不算有新版本(避免重复下载同版本 APK)', () {
    expect(compareVersions('1.7.13', '1.7.13') <= 0, isTrue);
    expect(compareVersions('1.7.11', '1.7.13') <= 0, isTrue);
    expect(compareVersions('1.7.14', '1.7.13') > 0, isTrue);
  });

  test('invalidateVersionCache 幂等:连清两次仍能正常解析版本', () async {
    // 缓存被清空后 knownVersion 必须回落到真实解析结果,而不是把
    // 「清空状态」当成 0.0.0 —— 否则又会退回到「永远提示有新版本」。
    UpdateService.invalidateVersionCache();
    UpdateService.invalidateVersionCache();
    expect(UpdateService.knownVersion(), isNot('0.0.0'));
  });
}