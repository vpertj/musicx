// test/core/updater/update_fallback_test.dart
//
// 桌面升级失败的根因回归:GitHub API 未认证会 403 限流,必须靠网页降级;
// 而降级里的正则曾把后缀二次转义成 \\.dmg(要求 href 含真实反斜杠),
// 永远匹配不到 → 报「最新 Release 中没有找到 DMG 安装包」。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/update_service.dart';

/// 取自 2026-09-14 真实 GitHub expanded_assets 页面片段。
const _realHtml = '''
<div class="Box-row">
  <a href="/vpertj/musicx/releases/download/v1.7.3/MusicX-1.7.3-setup.exe" rel="nofollow">setup</a>
  <a href="/vpertj/musicx/releases/download/v1.7.3/MusicX-1.7.3.apk" rel="nofollow">apk</a>
  <a href="/vpertj/musicx/releases/download/v1.7.3/MusicX-1.7.3.dmg" rel="nofollow">dmg</a>
</div>
''';

void main() {
  group('parseAssetUrlFromExpandedAssets', () {
    test('能解析出 dmg 直链(此前因二次转义匹配失败)', () {
      expect(
        parseAssetUrlFromExpandedAssets(_realHtml, '.dmg'),
        'https://github.com/vpertj/musicx/releases/download/v1.7.3/MusicX-1.7.3.dmg',
      );
    });

    test('能解析出 apk 直链(安卓)与 exe(Windows)', () {
      expect(
        parseAssetUrlFromExpandedAssets(_realHtml, '.apk'),
        endsWith('MusicX-1.7.3.apk'),
      );
      expect(
        parseAssetUrlFromExpandedAssets(_realHtml, '.exe'),
        endsWith('MusicX-1.7.3-setup.exe'),
      );
    });

    test('没有匹配后缀时返回 null', () {
      expect(parseAssetUrlFromExpandedAssets(_realHtml, '.tar.gz'), isNull);
      expect(parseAssetUrlFromExpandedAssets('', '.dmg'), isNull);
    });
  });

  group('conventionalAssetUrl', () {
    test('按 CI 命名约定拼直链,不依赖抓页面', () {
      expect(
        conventionalAssetUrl(
          repo: 'vpertj/musicx',
          tag: 'v1.7.3',
          version: '1.7.3',
          suffix: '.dmg',
        ),
        'https://github.com/vpertj/musicx/releases/download/v1.7.3/MusicX-1.7.3.dmg',
      );
      expect(
        conventionalAssetUrl(
          repo: 'vpertj/musicx',
          tag: 'v1.7.4',
          version: '1.7.4',
          suffix: '.apk',
        ),
        endsWith('/v1.7.4/MusicX-1.7.4.apk'),
      );
    });
  });

  test('Windows 也支持应用内自动安装,且安装包后缀为 .exe', () {
    expect(
      canAutoInstallFor(isMacOS: false, isAndroid: false, isWindows: true),
      isTrue,
    );
    expect(
      updateAssetSuffixFor(isMacOS: false, isWindows: true, isAndroid: false),
      '.exe',
    );
    // Linux 等仍走手动下载
    expect(
      canAutoInstallFor(isMacOS: false, isAndroid: false, isWindows: false),
      isFalse,
    );
  });

  test('下载文件名按平台区分(Windows 不能叫 .dmg)', () {
    expect(updateDownloadFileNameFor(isAndroid: true), 'musicx_update.apk');
    expect(
      updateDownloadFileNameFor(isAndroid: false, isWindows: true),
      'musicx_update.exe',
    );
    expect(
      updateDownloadFileNameFor(isAndroid: false, isMacOS: true),
      'musicx_update.dmg',
    );
  });

  test('文件名可带目标版本(便于区分残留旧包)', () {
    expect(
      updateDownloadFileNameFor(isAndroid: true, version: '1.7.39'),
      'musicx_update_v1.7.39.apk',
    );
    expect(
      updateDownloadFileNameFor(isAndroid: false, isMacOS: true, version: '1.7.39'),
      'musicx_update_v1.7.39.dmg',
    );
  });
}
