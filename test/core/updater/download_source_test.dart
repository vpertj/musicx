// test/core/updater/download_source_test.dart
//
// 国内下载 GitHub Release 经常断流,因此引入免费加速代理回退。
// 这些测试锁死两件事:
//   ① URL 改写不会拼出错链接(尤其不能重复叠代理);
//   ② "该不该换下一个源"的判定正确(404 不该白等三轮)。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/download_source.dart';

void main() {
  group('代理 URL 改写', () {
    test('代理前缀拼接保留原始完整 URL', () {
      const original =
          'https://github.com/vpertj/musicx/releases/download/v1.7.40/MusicX-1.7.40.apk';
      final src = DownloadSource.proxy('https://gh-proxy.com');
      expect(src.rewrite(original), 'https://gh-proxy.com/$original');
      expect(src.isProxy, isTrue);
      expect(src.label, 'gh-proxy.com');
    });

    test('前缀末尾多余的斜杠被去掉(避免拼出 //https://)', () {
      final src = DownloadSource.proxy('https://ghfast.top/');
      expect(
        src.rewrite('https://github.com/a/b'),
        'https://ghfast.top/https://github.com/a/b',
      );
    });

    test('直连源不改写 URL', () {
      const u = 'https://github.com/a/b/releases/download/v1/a.apk';
      expect(DownloadSource.direct.rewrite(u), u);
      expect(DownloadSource.direct.isProxy, isFalse);
    });

    test('proxyWrap 与 DownloadSource.proxy 行为一致', () {
      const u = 'https://github.com/a/b';
      expect(
        proxyWrap('https://gh-proxy.com', u),
        DownloadSource.proxy('https://gh-proxy.com').rewrite(u),
      );
    });
  });

  group('isRewritableGitHubUrl(决定是否套代理)', () {
    test('GitHub 域名 → 可套代理', () {
      expect(
        isRewritableGitHubUrl('https://github.com/a/b/releases/download/v1/a.apk'),
        isTrue,
      );
      expect(
        isRewritableGitHubUrl('https://api.github.com/repos/a/b/releases'),
        isTrue,
      );
      expect(
        isRewritableGitHubUrl('https://objects.githubusercontent.com/x'),
        isTrue,
      );
    });

    test('非 GitHub 直链(如自建 OSS/CDN)→ 不套代理', () {
      // 关键:自建 OSS 再套一层代理会拼出无效地址。
      expect(
        isRewritableGitHubUrl('https://musicx.oss-cn-hangzhou.aliyuncs.com/a.apk'),
        isFalse,
      );
      expect(isRewritableGitHubUrl('https://example.com/a.apk'), isFalse);
    });

    test('空串/非法 URL → 不套代理(不抛异常)', () {
      expect(isRewritableGitHubUrl(''), isFalse);
      expect(isRewritableGitHubUrl('not a url'), isFalse);
    });
  });

  group('下载源列表', () {
    test('直连始终排第一(境外用户走最优路径)', () {
      final sources = buildDownloadSources();
      expect(sources.first.isProxy, isFalse);
      expect(sources.first.label, 'GitHub 直连');
      expect(sources.length, greaterThan(1));
    });

    test('传入空代理列表时只剩直连(便于测试/禁用代理)', () {
      final sources = buildDownloadSources(proxies: const []);
      expect(sources.length, 1);
      expect(sources.first.isProxy, isFalse);
    });

    test('可注入自定义代理顺序', () {
      final sources = buildDownloadSources(
        proxies: const ['https://p1.test', 'https://p2.test'],
      );
      expect(sources.map((s) => s.label).toList(), [
        'GitHub 直连',
        'p1.test',
        'p2.test',
      ]);
    });
  });

  group('代理能力分类(实测结论,防止用错)', () {
    test('API 代理与纯下载代理不重叠', () {
      // ghfast.top / ghproxy.net 实测对 api.github.com 返回 403,
      // 若被拿去「检查更新」会导致拿不到 SHA256 digest。
      for (final api in kApiCapableProxyPrefixes) {
        expect(kDownloadOnlyProxyPrefixes, isNot(contains(api)));
      }
    });

    test('公共代理总表包含两类', () {
      for (final p in kApiCapableProxyPrefixes) {
        expect(kPublicProxyPrefixes, contains(p));
      }
      for (final p in kDownloadOnlyProxyPrefixes) {
        expect(kPublicProxyPrefixes, contains(p));
      }
    });
  });

  group('shouldTryNextSource(换源判定)', () {
    test('超时/连接失败 → 换源', () {
      expect(
        shouldTryNextSource(statusCode: null, timedOut: true, connectionFailed: false),
        isTrue,
      );
      expect(
        shouldTryNextSource(statusCode: null, timedOut: false, connectionFailed: true),
        isTrue,
      );
    });

    test('5xx 与限流(403/429)→ 换源', () {
      for (final code in [500, 502, 503, 403, 429]) {
        expect(
          shouldTryNextSource(statusCode: code, timedOut: false, connectionFailed: false),
          isTrue,
          reason: 'HTTP $code 应换源重试',
        );
      }
    });

    test('404/410 → 不换源(资产确实不存在,换源也没用)', () {
      for (final code in [404, 410]) {
        expect(
          shouldTryNextSource(statusCode: code, timedOut: false, connectionFailed: false),
          isFalse,
          reason: 'HTTP $code 换源无意义,应尽快失败',
        );
      }
    });
  });
}
