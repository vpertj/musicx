// test/core/updater/flavor_isolation_test.dart
//
// 标准版(唯一发布线)的更新检查契约:只认 std-v* tag,绝不把历史
// 吴玫静版(v* tag)的 release 当成自己的更新(串版)。
//
// 背景:仓库历史上同时存在 v*(吴玫静版)与 std-v*(标准版)两条升级线。
// 已合并为标准版单一发布线后,标准版客户端仍会通过 /releases 列表
// 看到历史 v* tag,必须按前缀过滤。这里把这个契约锁死。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/app_flavor.dart';
import 'package:musicx/core/updater/update_service.dart';

Map<String, dynamic> _release(
  String tag, {
  String asset = 'MusicX-1.7.50-standard.apk',
  String? digest = 'sha256:abc123',
  bool draft = false,
  bool prerelease = false,
}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/vpertj/musicx/releases/tag/$tag',
  'body': 'notes for $tag',
  'draft': draft,
  'prerelease': prerelease,
  'assets': [
    {
      'name': asset,
      'browser_download_url':
          'https://github.com/vpertj/musicx/releases/download/$tag/$asset',
      'digest': ?digest,
    },
  ],
};

void main() {
  group('tag 前缀解析', () {
    test('标准版只认 std-v 前缀,历史 v* tag 一律不认', () {
      expect(versionFromTag('std-v1.7.46', AppFlavor.standard), '1.7.46');
      expect(versionFromTag('v1.7.46', AppFlavor.standard), isNull,
          reason: '历史吴玫静版 tag 不属于标准版升级线');
      expect(versionFromTag('v1.7.54', AppFlavor.standard), isNull);
    });

    test('前缀后必须是数字,避免误收无关 tag', () {
      expect(versionFromTag('std-v-next', AppFlavor.standard), isNull);
      expect(versionFromTag('std-v', AppFlavor.standard), isNull);
      expect(versionFromTag('', AppFlavor.standard), isNull);
    });

    test('tagBelongsTo 与 versionFromTag 口径一致', () {
      expect(tagBelongsTo('std-v2.0.0', AppFlavor.standard), isTrue);
      expect(tagBelongsTo('v2.0.0', AppFlavor.standard), isFalse);
    });
  });

  group('变体属性', () {
    test('标准版不显示寄语卡片(历史卡片随吴玫静版停发)', () {
      expect(AppFlavor.standard.showsBlessingCard, isFalse);
    });

    test('displayName 可用于界面提示', () {
      expect(AppFlavor.standard.displayName, '标准版');
    });

    test('FLAVOR 环境变量解析;历史 blessing 值归入标准版', () {
      expect(parseFlavor('standard'), AppFlavor.standard);
      expect(parseFlavor('std'), AppFlavor.standard);
      expect(parseFlavor('STANDARD'), AppFlavor.standard);
      expect(parseFlavor('blessing'), AppFlavor.standard,
          reason: '旧吴玫静版构建不再发布,统一归入标准版升级线');
      expect(parseFlavor(''), AppFlavor.standard);
      expect(parseFlavor('garbage'), AppFlavor.standard);
    });
  });

  group('pickLatestForFlavor:标准版升级线', () {
    // 模拟真实仓库:历史 v* tag(吴玫静版)与 std-v* tag 混在一起。
    final releases = [
      _release('v1.7.50', asset: 'MusicX-1.7.50.apk'), // 历史吴玫静版
      _release('std-v1.7.49'), // 标准版
      _release('v1.7.48', asset: 'MusicX-1.7.48.apk'),
      _release('std-v1.7.47'),
    ];

    test('标准版拿到 std-v1.7.49(不会被历史 v* tag 干扰)', () {
      final info = pickLatestForFlavor(
        releases,
        assetSuffix: '.apk',
        flavor: AppFlavor.standard,
      );
      expect(info, isNotNull);
      expect(
        info!.latestVersion,
        '1.7.49',
        reason: '标准版绝不能把历史吴玫静版(v* tag)当成自己的更新',
      );
      expect(info.dmgUrl, contains('/download/std-v1.7.49/'));
      expect(info.dmgUrl, isNot(contains('/download/v1.7.50/')));
    });

    test('只存在历史 v* tag 时返回 null(不误报有更新)', () {
      final onlyLegacy = [
        _release('v1.7.50', asset: 'MusicX-1.7.50.apk'),
      ];
      expect(
        pickLatestForFlavor(
          onlyLegacy,
          assetSuffix: '.apk',
          flavor: AppFlavor.standard,
        ),
        isNull,
        reason: '历史 v* tag 不属于标准版升级线',
      );
    });

    test('标准版各版本独立发版,版本号互不影响', () {
      final list = [
        _release('std-v1.7.47'),
        _release('std-v1.7.48', asset: 'MusicX-1.7.48-standard.apk'),
      ];
      final s = pickLatestForFlavor(
        list,
        assetSuffix: '.apk',
        flavor: AppFlavor.standard,
      );
      expect(s!.latestVersion, '1.7.48');
      expect(s.dmgUrl, contains('std-v1.7.48'));
    });

    test('草稿与预发布不作为更新来源', () {
      final list = [
        _release('std-v2.0.0', draft: true),
        _release('std-v1.9.0', prerelease: true),
        _release('std-v1.8.0', asset: 'MusicX-1.8.0-standard.apk'),
      ];
      final info = pickLatestForFlavor(
        list,
        assetSuffix: '.apk',
        flavor: AppFlavor.standard,
      );
      expect(info!.latestVersion, '1.8.0');
    });

    test('挑最大版本号而非列表顺序(列表可能乱序)', () {
      final list = [
        _release('std-v1.7.1', asset: 'MusicX-1.7.1-standard.apk'),
        _release('std-v1.10.0', asset: 'MusicX-1.10.0-standard.apk'),
        _release('std-v1.9.9', asset: 'MusicX-1.9.9-standard.apk'),
      ];
      final info = pickLatestForFlavor(
        list,
        assetSuffix: '.apk',
        flavor: AppFlavor.standard,
      );
      expect(info!.latestVersion, '1.10.0',
          reason: '1.10.0 应大于 1.9.9(按数字段比较,不是字符串)');
    });

    test('保留 SHA256 digest(引入代理后仍可校验)', () {
      final info = pickLatestForFlavor(
        [_release('std-v1.8.0', digest: 'sha256:deadbeef')],
        assetSuffix: '.apk',
        flavor: AppFlavor.standard,
      );
      expect(info!.dmgSha256, 'deadbeef');
    });
  });

  group('parseReleaseEntry', () {
    test('历史吴玫静版 tag(v*)不属于标准版 → null', () {
      expect(
        parseReleaseEntry(
          _release('v1.7.50', asset: 'MusicX-1.7.50.apk'),
          assetSuffix: '.apk',
          flavor: AppFlavor.standard,
        ),
        isNull,
      );
    });

    test('属于本变体 → 正确解析版本与资产', () {
      final info = parseReleaseEntry(
        _release('std-v1.7.50'),
        assetSuffix: '.apk',
        flavor: AppFlavor.standard,
      );
      expect(info!.latestVersion, '1.7.50');
      expect(info.dmgUrl, endsWith('MusicX-1.7.50-standard.apk'));
      expect(info.dmgSha256, 'abc123');
    });
  });
}
