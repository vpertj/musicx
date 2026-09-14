// test/platform/android_manifest_test.dart
//
// 安卓清单契约测试:这些配置只在真机/打包后生效,代码里看不出来,
// 我们已经因此踩过两次坑(Windows 托盘图标、安卓明文 HTTP),故用测试锁死。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final xml = manifest.readAsStringSync();

  test('声明 INTERNET(release 构建默认不会自动加)', () {
    expect(xml, contains('android.permission.INTERNET'));
  });

  test('允许明文 HTTP:内置音源(酷我/QQ/网易)都是 http 接口,'
      'Android 9+ 默认禁止会直接导致搜不到歌', () {
    expect(
      xml,
      contains('android:usesCleartextTraffic="true"'),
      reason: '缺少该属性时,所有 http:// 音源接口在安卓上都会失败',
    );
  });

  test('声明 REQUEST_INSTALL_PACKAGES(应用内更新需要)', () {
    expect(xml, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
  });

  test('声明 FileProvider 并指向 file_paths(把 APK 交给系统安装器)', () {
    expect(xml, contains('androidx.core.content.FileProvider'));
    expect(xml, contains(r'${applicationId}.fileprovider'));
    expect(xml, contains('@xml/file_paths'));
    expect(
      File('android/app/src/main/res/xml/file_paths.xml').existsSync(),
      isTrue,
    );
  });
}
