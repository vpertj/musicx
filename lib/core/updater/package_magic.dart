/// 安装包文件头/尾的魔数校验(纯函数,便于单测)。
///
/// 教训:上一版把「ZIP 魔数(PK)」校验放进了公共下载路径,结果 **macOS 的 DMG
/// 永远过不了**(DMG 不是 ZIP),桌面端与安卓端都报「不是有效的安装包」。
/// 不同平台的安装包格式不同,必须各按各的魔数判断。
library;

/// 安装包类型。
enum PackageKind { apk, dmg, exe, unknown }

/// 按平台判断安装包类型。
PackageKind packageKindFor({
  required bool isAndroid,
  required bool isMacOS,
  required bool isWindows,
}) {
  if (isAndroid) return PackageKind.apk;
  if (isMacOS) return PackageKind.dmg;
  if (isWindows) return PackageKind.exe;
  return PackageKind.unknown;
}

/// [head] 为文件开头若干字节,[tail] 为文件结尾若干字节(可空)。
///
/// - APK/ZIP:开头 `PK`(0x50 0x4B)
/// - Windows PE:开头 `MZ`(0x4D 0x5A)
/// - DMG:结尾 512 字节的 trailer 以 `koly` 开头
/// - 未知平台:不判断(返回 true,避免误拦)
bool looksLikePackage({
  required PackageKind kind,
  required List<int> head,
  List<int>? tail,
}) {
  switch (kind) {
    case PackageKind.apk:
      return head.length >= 2 && head[0] == 0x50 && head[1] == 0x4B;
    case PackageKind.exe:
      return head.length >= 2 && head[0] == 0x4D && head[1] == 0x5A;
    case PackageKind.dmg:
      final t = tail;
      if (t == null || t.length < 4) return false;
      // DMG 的 koly trailer 位于文件最后 512 字节的起始处
      return t[0] == 0x6B && t[1] == 0x6F && t[2] == 0x6C && t[3] == 0x79;
    case PackageKind.unknown:
      return true;
  }
}
