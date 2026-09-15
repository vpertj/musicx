// 测试夹具:按**宿主平台**构造一个能通过魔数校验的安装包字节。
// download() 现在按平台校验魔数(APK=PK / EXE=MZ / DMG=末尾 koly),
// 因此测试数据必须与宿主平台一致,否则会被正确拦下。
import 'dart:io';
import 'dart:typed_data';

List<int> hostValidPackage([List<int> payload = const [1, 2, 3]]) {
  if (Platform.isAndroid) {
    return Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, ...payload]);
  }
  if (Platform.isWindows) {
    return Uint8List.fromList([0x4D, 0x5A, 0x90, 0x00, ...payload]);
  }
  // macOS/Linux:以 koly trailer 结尾的 DMG 结构
  final size = 1024;
  final buf = Uint8List(size);
  for (var i = 0; i < payload.length && i < size - 512; i++) {
    buf[i] = payload[i];
  }
  const koly = [0x6B, 0x6F, 0x6C, 0x79];
  for (var i = 0; i < koly.length; i++) {
    buf[size - 512 + i] = koly[i];
  }
  return buf;
}
