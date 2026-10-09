// test/core/plugins/bundled_recognition_test.dart
//
// 用户反馈:「默认音源为什么那么多?以前不是只有三个还是四个」。
//
// 排查:弹窗候选 = 已装音源里**平台名不在内置清单**的那些,而内置源只靠平台名
// 识别。历史内置源改过名(网易音乐 → 网yi)、也下过线(酷我(独家音源)、netease、
// kuwo),升级是覆盖安装,老文件留在设备上 → 被当成「用户自己装的音源」列出来。
//
// 本文件锁定识别规则:按「当前清单平台名 + 上游文件同名 + 历史内置名单」三重认,
// 让这些历史遗留的内置源不再冒充用户音源(用户要求:内置源不要列出来)。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';

BundledPlugin _bundled(String platform, String asset) => BundledPlugin(
      name: platform,
      platform: platform,
      version: '1.0.0',
      assetPath: asset,
    );

void main() {
  final catalog = [
    _bundled('腾讯音乐', 'assets/plugins/tx.js'),
    _bundled('网yi', 'assets/plugins/wy.js'),
    _bundled('酷我(念心音源)', 'assets/plugins/kuwo_nianxin.js'),
  ];

  bool isBundled(String platform, {String srcUrl = ''}) => isBundledPluginSource(
        platform: platform,
        srcUrl: srcUrl,
        catalog: catalog,
      );

  test('当前清单里的平台名 → 内置', () {
    expect(isBundled('腾讯音乐'), isTrue);
    expect(isBundled('网yi'), isTrue);
  });

  test('历史遗留/已撤下的内置源 → 仍认作内置', () {
    // 平台名改成「网易音乐」但上游还是随包的 wy.js
    expect(
      isBundled(
        '网易音乐',
        srcUrl:
            'https://raw.githubusercontent.com/ThomasBy2025/musicfree/refs/heads/main/plugins/wy.js',
      ),
      isTrue,
      reason: '改名后靠上游文件名同名仍应认出来',
    );
    // 平台名就是历史名,上游也已下线
    expect(isBundled('网易音乐'), isTrue, reason: '命中已撤下名单');
    expect(isBundled('酷我(独家音源)'), isTrue, reason: '08e9431 内置过,后被下线');
    expect(isBundled('netease'), isTrue, reason: 'a9b70d7 最早内置的平台名');
    expect(isBundled('kuwo'), isTrue);
    // 1.7.56 收编、1.7.58 按用户要求撤下的 8 个
    for (final name in [
      '网易云音乐',
      'QQ音乐',
      '酷狗音乐',
      '酷我音乐',
      '咪咕音乐',
      '网易云电台',
      '哔哩哔哩',
      'youtube',
    ]) {
      expect(isBundled(name), isTrue, reason: '$name 是撤下的内置源,不该冒充用户音源');
    }
  });

  test('用户自己装的音源 → 不是内置(要照常显示)', () {
    expect(isBundled('我的自建源', srcUrl: 'https://my.example.com/foo.js'),
        isFalse);
    expect(isBundled('酷狗(独家音源)'), isFalse);
  });
}
