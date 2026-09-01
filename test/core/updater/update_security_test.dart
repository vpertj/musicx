import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicx/core/updater/update_service.dart';

void main() {
  group('UpdateService.download SHA256 校验', () {
    // 固定一段测试内容,计算其 sha256
    final content = utf8.encode('fake dmg bytes for musicx update test');
    final hash = sha256.convert(content).toString();

    test('download 下载后 SHA256 匹配则返回文件', () async {
      final client = MockClient((req) async {
        return http.Response.bytes(content, 200);
      });
      final service = UpdateService(client: client);
      final file = await service.download(
        'https://example.com/musicx.dmg',
        expectedSha256: hash,
      );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      expect(file.existsSync(), isTrue);
      expect(sha256.convert(file.readAsBytesSync()).toString(), hash);
    });

    test('download 下载后 SHA256 不匹配则抛异常并删除文件', () async {
      final client = MockClient((req) async {
        return http.Response.bytes(content, 200);
      });
      final service = UpdateService(client: client);
      final wrongHash = '0' * 64; // 不匹配的哈希
      await expectLater(
        service.download(
          'https://example.com/musicx.dmg',
          expectedSha256: wrongHash,
        ),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('完整性校验失败'),
          ),
        ),
      );
      // 文件应被删除
      expect(
        File('${Directory.systemTemp.path}/musicx_update.dmg').existsSync(),
        isFalse,
      );
    });

    test('download 不提供 expectedSha256 则跳过校验', () async {
      final client = MockClient((req) async {
        return http.Response.bytes(content, 200);
      });
      final service = UpdateService(client: client);
      final file = await service.download('https://example.com/musicx.dmg');
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      expect(file.existsSync(), isTrue);
    });
  });
}
