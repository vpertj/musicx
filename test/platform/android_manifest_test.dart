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
  // ---- 后台播放(just_audio_background / audio_service) ----
  // 用户反馈「息屏就停」。修好它依赖三样**只在打包后生效**的东西,
  // 任何一样丢了都退回原 bug(而且 Dart 测试与 analyze 都发现不了),
  // 所以在这里静态锁死。

  test('声明前台服务的权限(没有它们 Android 10+/14+ 起不了媒体前台服务)', () {
    for (final p in [
      'android.permission.WAKE_LOCK',
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
      'android.permission.POST_NOTIFICATIONS',
    ]) {
      expect(xml, contains(p), reason: '缺少 $p,息屏后播放会被系统冻结');
    }
  });

  test('注册 audio_service 前台服务(mediaPlayback)与媒体按键接收器', () {
    expect(xml, contains('com.ryanheise.audioservice.AudioService'));
    expect(
      xml,
      contains('android:foregroundServiceType="mediaPlayback"'),
      reason: 'Android 14+ 必须声明前台服务类型,否则启动即抛异常',
    );
    expect(xml, contains('com.ryanheise.audioservice.MediaButtonReceiver'));
    expect(xml, contains('android.intent.action.MEDIA_BUTTON'));
  });

  test('MainActivity 继承 AudioServiceActivity(否则媒体会话拿不到 Activity)', () {
    final kt = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('MainActivity.kt'));
    final src = kt.readAsStringSync();
    expect(src, contains('AudioServiceActivity'));
    expect(src, isNot(contains('class MainActivity : FlutterActivity()')));
  });

  test('keep.xml 保留 audio_service_* 图标(release 资源压缩会按名字裁掉它们)', () {
    // 实测事故:release 构建把 audio_service_stop 等通知图标裁掉 → AudioService
    // 构建 STOP 的 CustomAction 时 iconId=0 → IllegalArgumentException
    // 「You must specify an icon resource id to build a CustomAction」
    // → 媒体通知与前台服务起不来 → 息屏仍然停播。
    final keep = File('android/app/src/main/res/raw/keep.xml');
    expect(keep.existsSync(), isTrue, reason: '缺少 keep.xml,通知图标会被裁掉');
    expect(keep.readAsStringSync(), contains('audio_service_'));
  });
}
