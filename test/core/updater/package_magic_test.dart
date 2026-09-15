// test/core/updater/package_magic_test.dart
//
// 回归:ZIP 魔数不能用来校验 DMG(上一版就是因此让桌面端升级必失败)。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/package_magic.dart';

void main() {
  List<int> bytes(String s) => Uint8List.fromList(s.codeUnits);

  test('平台 → 安装包类型', () {
    expect(packageKindFor(isAndroid: true, isMacOS: false, isWindows: false),
        PackageKind.apk);
    expect(packageKindFor(isAndroid: false, isMacOS: true, isWindows: false),
        PackageKind.dmg);
    expect(packageKindFor(isAndroid: false, isMacOS: false, isWindows: true),
        PackageKind.exe);
  });

  test('APK:PK 开头通过,HTML 错误页拦下', () {
    expect(
      looksLikePackage(kind: PackageKind.apk, head: bytes('PK\u0003\u0004')),
      isTrue,
    );
    expect(
      looksLikePackage(kind: PackageKind.apk, head: bytes('<!DOCTYPE h')),
      isFalse,
    );
  });

  test('DMG:koly trailer 通过,PK 开头也**不该**被当成 DMG 校验', () {
    expect(
      looksLikePackage(kind: PackageKind.dmg, head: bytes('xx'), tail: bytes('koly')),
      isTrue,
    );
    expect(
      looksLikePackage(kind: PackageKind.dmg, head: bytes('PK\u0003\u0004'),
          tail: bytes('none')),
      isFalse,
      reason: 'DMG 必须按 koly 校验,不能用 ZIP 魔数(这正是上一版的 bug)',
    );
  });

  test('Windows EXE:MZ 开头通过', () {
    expect(looksLikePackage(kind: PackageKind.exe, head: bytes('MZ\x90\x00')),
        isTrue);
    expect(looksLikePackage(kind: PackageKind.exe, head: bytes('PK\u0003\u0004')),
        isFalse);
  });

  test('未知平台不判断(不误拦)', () {
    expect(
      looksLikePackage(kind: PackageKind.unknown, head: bytes('anything')),
      isTrue,
    );
  });
}
