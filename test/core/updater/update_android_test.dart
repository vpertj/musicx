// test/core/updater/update_android_test.dart
//
// 安卓应用内更新:平台分支、下载文件名、版本解析。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicx/core/updater/update_service.dart';

void main() {
  group('canAutoInstallFor', () {
    test('macOS 与 Android 支持应用内更新', () {
      expect(canAutoInstallFor(isMacOS: true, isAndroid: false), isTrue);
      expect(canAutoInstallFor(isMacOS: false, isAndroid: true), isTrue);
    });

    test('Windows/Linux 仍走「前往下载」', () {
      expect(canAutoInstallFor(isMacOS: false, isAndroid: false), isFalse);
    });
  });

  group('updateAssetSuffixFor', () {
    test('按平台挑对应安装包', () {
      expect(updateAssetSuffixFor(isMacOS: true, isWindows: false, isAndroid: false), '.dmg');
      expect(updateAssetSuffixFor(isMacOS: false, isWindows: true, isAndroid: false), '.exe');
      expect(updateAssetSuffixFor(isMacOS: false, isWindows: false, isAndroid: true), '.apk');
    });
  });

  group('updateDownloadFileNameFor', () {
    test('安卓下载 .apk,桌面下载 .dmg', () {
      expect(updateDownloadFileNameFor(isAndroid: true), 'musicx_update.apk');
      expect(updateDownloadFileNameFor(isAndroid: false), 'musicx_update.dmg');
    });
  });

  group('parseMacVersionFromPlist', () {
    test('取出 CFBundleShortVersionString', () {
      const plist = '''
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>1.7.2</string>
</dict>
</plist>''';
      expect(parseMacVersionFromPlist(plist), '1.7.2');
    });

    test('缺失时返回空串(调用方回落 0.0.0)', () {
      expect(parseMacVersionFromPlist('<plist><dict></dict></plist>'), '');
    });
  });

  test('安卓安装包 MIME 固定为 package-archive', () {
    expect(kApkMimeType, 'application/vnd.android.package-archive');
  });

  test('download 写入注入的目录(安卓用应用 cache 目录才能交给 FileProvider)', () async {
    final tmp = Directory.systemTemp.createTempSync('musicx_update_dir');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    // 需要 ZIP 魔数:非 ZIP 内容会被判为无效安装包并删除(新契约)
    final client = MockClient(
      (req) async => http.Response.bytes([0x50, 0x4B, 0x03, 0x04, 1, 2, 3], 200),
    );
    final service = UpdateService(client: client, downloadDir: tmp);

    final file = await service.download('https://example.com/musicx.apk');

    expect(file.parent.path, tmp.path);
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), [0x50, 0x4B, 0x03, 0x04, 1, 2, 3]);
  });
}
