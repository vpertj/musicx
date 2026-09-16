// test/core/updater/flavor_isolation_test.dart
//
// 两个发行版本(吴玫静版 / 标准版)必须**各自独立升级**,绝不能串版。
//
// 背景:GitHub 的 `/releases/latest` 返回全仓库最新 release,不区分变体。
// 若两个版本都用它,标准版用户会收到吴玫静版的更新提示 —— 轻则莫名多出
// 寄语卡片,重则被系统以包名/版本冲突拒绝安装。因此改为拉列表 + 按 tag
// 前缀筛选。这里把这个契约锁死。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/app_flavor.dart';
import 'package:musicx/core/updater/update_service.dart';

Map<String, dynamic> _release(
  String tag, {
  String asset = 'MusicX-1.7.50.apk',
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
    test('吴玫静版只认 v 前缀', () {
      expect(versionFromTag('v1.7.46', AppFlavor.blessing), '1.7.46');
      expect(versionFromTag('std-v1.7.46', AppFlavor.blessing), isNull);
    });

    test('标准版只认 std-v 前缀', () {
      expect(versionFromTag('std-v1.7.46', AppFlavor.standard), '1.7.46');
      expect(versionFromTag('v1.7.46', AppFlavor.standard), isNull);
    });

    test('前缀后必须是数字,避免误收无关 tag', () {
      expect(versionFromTag('v-next', AppFlavor.blessing), isNull);
      expect(versionFromTag('v', AppFlavor.blessing), isNull);
      expect(versionFromTag('', AppFlavor.blessing), isNull);
    });

    test('tagBelongsTo 与 versionFromTag 口径一致', () {
      expect(tagBelongsTo('std-v2.0.0', AppFlavor.standard), isTrue);
      expect(tagBelongsTo('std-v2.0.0', AppFlavor.blessing), isFalse);
    });
  });

  group('变体属性', () {
    test('只有吴玫静版显示寄语卡片', () {
      expect(AppFlavor.blessing.showsBlessingCard, isTrue);
      expect(AppFlavor.standard.showsBlessingCard, isFalse);
    });

    test('displayName 可用于界面提示', () {
      expect(AppFlavor.blessing.displayName, '吴玫静版');
      expect(AppFlavor.standard.displayName, '标准版');
    });

    test('FLAVOR 环境变量解析;未知值回落吴玫静版', () {
      expect(parseFlavor('standard'), AppFlavor.standard);
      expect(parseFlavor('std'), AppFlavor.standard);
      expect(parseFlavor('STANDARD'), AppFlavor.standard);
      expect(parseFlavor('blessing'), AppFlavor.blessing);
      expect(parseFlavor(''), AppFlavor.blessing);
      expect(parseFlavor('garbage'), AppFlavor.blessing);
    });
  });

  group('pickLatestForFlavor:两条升级线互不干扰', () {
    // 混在一起的 release 列表(模拟真实仓库:两个变体都有)
    final releases = [
      _release('v1.7.50'), // 吴玫静版较新
      _release('std-v1.7.49'), // 标准版稍旧
      _release('v1.7.48'),
      _release('std-v1.7.47'),
    ];

    test('吴玫静版拿到 v1.7.50(而不是标准版的线)', () {
      final info = pickLatestForFlavor(
        releases,
        assetSuffix: '.apk',
        flavor: AppFlavor.blessing,
      );
      expect(info, isNotNull);
      expect(info!.latestVersion, '1.7.50');
      expect(info.dmgUrl, contains('/download/v1.7.50/'));
    });

    test('标准版拿到 std-v1.7.49(而不是更新的吴玫静版 1.7.50)', () {
      final info = pickLatestForFlavor(
        releases,
        assetSuffix: '.apk',
        flavor: AppFlavor.standard,
      );
      expect(info, isNotNull);
      expect(
        info!.latestVersion,
        '1.7.49',
        reason: '标准版绝不能升级到吴玫静版(串版)',
      );
      expect(info.dmgUrl, contains('/download/std-v1.7.49/'));
    });

    test('只存在另一个变体的 release 时返回 null(不误报有更新)', () {
      final onlyBlessing = [_release('v1.7.50')];
      expect(
        pickLatestForFlavor(
          onlyBlessing,
          assetSuffix: '.apk',
          flavor: AppFlavor.standard,
        ),
        isNull,
      );
      final onlyStd = [_release('std-v1.7.50')];
      expect(
        pickLatestForFlavor(
          onlyStd,
          assetSuffix: '.apk',
          flavor: AppFlavor.blessing,
        ),
        isNull,
      );
    });

    test('两条线可以各自独立发版,版本号互不影响', () {
      // 场景:吴玫静版发了 1.7.48,标准版仍停在 1.7.47。
      // 标准版用户不应因为「吴玫静版发了新版」而收到更新提示。
      final list = [_release('v1.7.48'), _release('std-v1.7.47')];
      final b = pickLatestForFlavor(
        list,
        assetSuffix: '.apk',
        flavor: AppFlavor.blessing,
      );
      final s = pickLatestForFlavor(
        list,
        assetSuffix: '.apk',
        flavor: AppFlavor.standard,
      );
      expect(b!.latestVersion, '1.7.48');
      expect(s!.latestVersion, '1.7.47');
      expect(s.dmgUrl, contains('std-v1.7.47'));
    });

    test('当前已发布的两个真实 tag 组合:各取各的', () {
      // 仓库里真实同时存在 v1.7.47 与 std-v1.7.47(同一版本号、不同线)。
      // 若前缀解析有误会取到同一个包 —— 这里锁死必须各自命中。
      final real = [_release('std-v1.7.47'), _release('v1.7.47')];
      final b = pickLatestForFlavor(
        real,
        assetSuffix: '.apk',
        flavor: AppFlavor.blessing,
      );
      final s = pickLatestForFlavor(
        real,
        assetSuffix: '.apk',
        flavor: AppFlavor.standard,
      );
      expect(b!.dmgUrl, contains('/download/v1.7.47/'));
      expect(b.dmgUrl, isNot(contains('std-')));
      expect(s!.dmgUrl, contains('/download/std-v1.7.47/'));
      expect(s.dmgUrl, isNot(contains('/download/v1.7.47/')));
    });

    test('草稿与预发布不作为更新来源', () {
      final list = [
        _release('std-v2.0.0', draft: true),
        _release('std-v1.9.0', prerelease: true),
        _release('std-v1.8.0'),
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
        _release('std-v1.7.1'),
        _release('std-v1.10.0'), // 数值更大
        _release('std-v1.9.9'),
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
    test('不属于本变体 → null', () {
      expect(
        parseReleaseEntry(
          _release('std-v1.7.50'),
          assetSuffix: '.apk',
          flavor: AppFlavor.blessing,
        ),
        isNull,
      );
    });

    test('属于本变体 → 正确解析版本与资产', () {
      final info = parseReleaseEntry(
        _release('v1.7.50'),
        assetSuffix: '.apk',
        flavor: AppFlavor.blessing,
      );
      expect(info!.latestVersion, '1.7.50');
      expect(info.dmgUrl, endsWith('MusicX-1.7.50.apk'));
      expect(info.dmgSha256, 'abc123');
    });
  });
}
