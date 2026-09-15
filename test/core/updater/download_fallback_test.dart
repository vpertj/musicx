// test/core/updater/download_fallback_test.dart
//
// 国内用户下载 GitHub Release 经常超时/断流。这里锁死"多源回退"这条链路:
// 直连失败必须自动换代理,且**换源后仍然做完整校验** —— 引入第三方代理
// 绝不能变成无校验过境。
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicx/core/updater/download_source.dart';
import 'package:musicx/core/updater/update_service.dart';

import '_pkg_fixture.dart';

void main() {
  final pkg = hostValidPackage();
  final goodSha = sha256.convert(pkg).toString();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('musicx_fallback'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  UpdateService svc(http.Client client) =>
      UpdateService(client: client, downloadDir: tmp);

  const original =
      'https://github.com/vpertj/musicx/releases/download/v1.7.40/MusicX-1.7.40.apk';

  test('直连成功时不碰任何代理', () async {
    final requested = <String>[];
    final client = MockClient((req) async {
      requested.add(req.url.toString());
      return http.Response.bytes(pkg, 200);
    });

    final f = await svc(client).download(original);

    expect(f.existsSync(), isTrue);
    expect(requested.length, 1, reason: '直连成功就不该再请求代理');
    expect(requested.single, original);
  });

  test('直连超时 → 自动换代理并成功下载', () async {
    final requested = <String>[];
    final client = MockClient((req) async {
      final url = req.url.toString();
      requested.add(url);
      if (url == original) {
        // 模拟国内直连超时
        throw TimeoutException('直连超时', const Duration(seconds: 30));
      }
      return http.Response.bytes(pkg, 200);
    });

    final f = await svc(client).download(original);

    expect(f.existsSync(), isTrue);
    expect(requested.length, 2, reason: '第一次直连失败,第二次应换代理');
    expect(requested[1], startsWith('https://gh-proxy.com/'));
    expect(requested[1], endsWith(original));
  });

  test('直连与第一个代理都 500 → 继续换下一个代理直到成功', () async {
    final requested = <String>[];
    final client = MockClient((req) async {
      final url = req.url.toString();
      requested.add(url);
      if (url == original) return http.Response('boom', 500);
      if (url.startsWith('https://gh-proxy.com/')) {
        return http.Response('bad gateway', 502);
      }
      return http.Response.bytes(pkg, 200);
    });

    final f = await svc(client).download(original);

    expect(f.existsSync(), isTrue);
    expect(requested.length, 3);
    expect(requested[2], startsWith('https://gh.llkk.cc/'));
  });

  test('所有源都失败 → 报错里列出每个源的原因(便于用户反馈)', () async {
    final client = MockClient((req) async => http.Response('nope', 503));

    await expectLater(
      svc(client).download(original),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('所有下载源都失败了'),
            contains('GitHub 直连'),
            contains('503'),
          ),
        ),
      ),
    );
  });

  test('换源后 SHA256 仍必须校验通过(代理被篡改 → 拒绝安装)', () async {
    // 直连超时 → 代理返回**内容被篡改**的包(长度合法、魔数合法)。
    final tampered = hostValidPackage([9, 9, 9, 9]);
    expect(tampered.length, pkg.length, reason: '构造等长但内容不同的包');

    final requested = <String>[];
    final client = MockClient((req) async {
      requested.add(req.url.toString());
      if (req.url.toString() == original) {
        throw TimeoutException('直连超时', const Duration(seconds: 30));
      }
      return http.Response.bytes(tampered, 200);
    });

    await expectLater(
      svc(client).download(original, expectedSha256: goodSha),
      throwsA(
        isA<FatalUpdateException>().having(
          (e) => e.message,
          'message',
          contains('SHA256 不匹配'),
        ),
      ),
    );
    // 安全性失败必须**立即终止**:直连 + 第一个代理共 2 次,不再往下撞。
    expect(
      requested.length,
      2,
      reason: 'SHA256 不符属于安全性失败,不应继续换源重下 60MB',
    );
  });

  test('代理返回错误文件(魔数不对)→ 换下一个源,不当作最终失败', () async {
    final requested = <String>[];
    final client = MockClient((req) async {
      final url = req.url.toString();
      requested.add(url);
      // 第一个代理返回 HTML 错误页(不是安装包)
      if (url.startsWith('https://gh-proxy.com/')) {
        return http.Response('<html>error</html>', 200);
      }
      if (url == original) throw TimeoutException('t', Duration.zero);
      return http.Response.bytes(pkg, 200);
    });

    final f = await svc(client).download(original);
    expect(f.existsSync(), isTrue);
    expect(requested.length, 3);
  });

  test('非 GitHub 直链(自建 OSS)不套代理', () async {
    final requested = <String>[];
    const oss = 'https://musicx.oss-cn-hangzhou.aliyuncs.com/MusicX-1.7.40.apk';
    final client = MockClient((req) async {
      requested.add(req.url.toString());
      return http.Response.bytes(pkg, 200);
    });

    await svc(client).download(oss);

    expect(requested.single, oss, reason: '自建 CDN 不该被再套一层代理');
  });

  test('换源时回调负数通知 UI 重置进度', () async {
    final progress = <double>[];
    final client = MockClient((req) async {
      if (req.url.toString() == original) {
        throw TimeoutException('t', Duration.zero);
      }
      return http.Response.bytes(pkg, 200);
    });

    await svc(client).download(original, onProgress: progress.add);

    expect(progress.any((p) => p < 0), isTrue,
        reason: '换源必须通知 UI 进度归零,否则进度条会倒着走');
  });

  test('可注入自定义源列表(便于未来接入自建 OSS 主源)', () async {
    final requested = <String>[];
    final client = MockClient((req) async {
      requested.add(req.url.toString());
      return http.Response.bytes(pkg, 200);
    });

    await svc(client).download(
      original,
      sources: [
        DownloadSource.direct,
        DownloadSource.proxy('https://my-own-cdn.test'),
      ],
    );

    expect(requested.single, original);
  });

  group('传输停滞检测(免费代理实测会「连上但卡死」)', () {
    test('传输中途卡死 → 换源,不永久挂起', () async {
      // 造一个「先给一部分数据,然后永远不再产出」的流:
      // 模拟代理连上了却卡住。没有停滞检测时,这里会一直挂到测试超时。
      final requested = <String>[];
      final client = MockClient.streaming((req, bodyStream) async {
        final url = req.url.toString();
        requested.add(url);
        if (url == original) {
          final controller = StreamController<List<int>>();
          // 只发一点点,然后不关闭 —— 永远停滞
          controller.add([0x50, 0x4B]);
          return http.StreamedResponse(controller.stream, 200);
        }
        return http.StreamedResponse(
          Stream.value(pkg),
          200,
          contentLength: pkg.length,
        );
      });

      final f = await svc(client)
          .download(original)
          .timeout(const Duration(seconds: 180));

      expect(f.existsSync(), isTrue, reason: '卡死的源应被跳过,由下一个源完成');
      expect(requested.length, 2);
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('停滞超时常量取值合理(不能短到误杀慢速正常下载)', () {
      // 国内 60MB 慢速下载可能只有 ~50KB/s,但仍持续有数据。
      // 停滞判定必须明显长于「单个数据块的到达间隔」。
      expect(kDownloadStallTimeoutSeconds, greaterThanOrEqualTo(30));
      expect(kDownloadStallTimeoutSeconds, lessThanOrEqualTo(120));
    });
  });
}
