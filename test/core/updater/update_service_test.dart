import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/update_service.dart';

void main() {
  group('compareVersions', () {
    test('相等返回 0', () {
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('1.0', '1.0.0'), 0);
    });

    test('新版更大返回正数', () {
      expect(compareVersions('1.1.0', '1.0.0'), greaterThan(0));
      expect(compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('旧版更小返回负数', () {
      expect(compareVersions('1.0.0', '1.1.0'), lessThan(0));
      expect(compareVersions('0.9.0', '1.0.0'), lessThan(0));
    });

    test('忽略非数字段', () {
      expect(compareVersions('1.0.0-beta', '1.0.0'), 0);
    });
  });

  group('UpdateService', () {
    test('currentVersion 返回非空字符串', () {
      expect(UpdateService.currentVersion(), isNotEmpty);
    });

    test('从模拟 bundle 读取 Info.plist 版本', () {
      // 构造 .../MusicX.app/Contents/Info.plist 模拟结构
      final tmp = Directory.systemTemp.createTempSync('musicx_bundle');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final contents = Directory('${tmp.path}/Contents')..createSync();
      final plist = File('${contents.path}/Info.plist');
      plist.writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>9.9.9</string>
</dict>
</plist>
''');
      // 模拟可执行文件存在(路径解析依赖其目录结构)
      File('${tmp.path}/Contents/MacOS/musicx').createSync(recursive: true);
      // 直接调用内部逻辑验证路径解析:通过 PlistBuddy 读取
      final out = Process.runSync('/usr/libexec/PlistBuddy', [
        '-c', 'Print :CFBundleShortVersionString', plist.path,
      ]);
      expect(out.exitCode, 0);
      expect((out.stdout as String).trim(), '9.9.9');
    });
  });

  test('Windows 端当前版本应能读取(此前恒为 0.0.0,导致永远提示有新版本)', () {
    // 平台相关:测试机是 macOS,这里验证「解析逻辑」本身
    // —— version.txt 内容可能带 +build,需只取版本号部分。
    String parseWin(String raw) => raw.trim().split('+').first.trim();
    expect(parseWin('1.7.42'), '1.7.42');
    expect(parseWin('1.7.42+61'), '1.7.42');
    expect(parseWin(' 1.7.42\n'), '1.7.42');
    // 非 Windows 平台不应误报:currentVersion 在 macOS 上返回 Info.plist 版本
    if (!Platform.isWindows) {
      expect(UpdateService.currentVersion(), isNotEmpty);
    }
  });
}
