// test/core/plugins/auto_source_order_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/auto_source_order.dart';

SourceIdentity _id(String platform, {String srcUrl = '', String fileName = ''}) =>
    SourceIdentity(platform: platform, srcUrl: srcUrl, fileName: fileName);

void main() {
  group('classifySource', () {
    test('平台名被改成无法识别(网yi)时,靠上游/文件名仍能归类', () {
      expect(
        classifySource(_id('网yi', srcUrl: 'https://x/wy.js', fileName: '网易音乐.js')),
        SourceKind.netease,
      );
      expect(
        classifySource(_id('腾讯音乐', srcUrl: 'https://x/tx.js')),
        SourceKind.tencent,
      );
      expect(
        classifySource(_id('酷我(独家音源)', srcUrl: 'https://x/酷我_竹岑.js', fileName: '酷我_独家音源.js')),
        SourceKind.kuwo,
      );
    });

    test('平台名关键词也能归类', () {
      expect(classifySource(_id('网易云音乐')), SourceKind.netease);
      expect(classifySource(_id('QQ音乐')), SourceKind.tencent);
      expect(classifySource(_id('酷狗音乐')), SourceKind.kugou);
      expect(classifySource(_id('netEase')), SourceKind.netease);
    });

    test('僵尸源单独归类', () {
      expect(classifySource(_id('喜马拉雅(公开API)')), SourceKind.dead);
      expect(classifySource(_id('酷狗(独家音源)')), SourceKind.dead);
    });

    test('未知源归为 other', () {
      expect(classifySource(_id('某个小众源')), SourceKind.other);
    });
  });

  group('orderAutoSourceIdentities', () {
    test('自动源正版优先:腾讯第一、网易次之(网易改名 网yi 也认得出)', () {
      // 实测(2026-09,「晴天 周杰伦」,过滤后原版率):腾讯 22/30 且封面 30/30,
      // 网易 9/20 且首条常是翻唱 —— 用户要「正版+封面+歌词」,故腾讯排第一。
      final ordered = orderAutoSourceIdentities([
        _id('腾讯音乐', srcUrl: 'https://x/tx.js'),
        _id('网yi', srcUrl: 'https://x/wy.js', fileName: '网易音乐.js'),
        _id('酷我(独家音源)', srcUrl: 'https://x/酷我_竹岑.js'),
        _id('酷我(念心音源)', srcUrl: 'https://x/酷我_念心.js'),
      ]);
      expect(ordered.first.platform, '腾讯音乐');
      expect(ordered[1].platform, '网yi',
          reason: '网易改名后仍应被识别为第二顺位(靠 wy.js 归类)');
    });

    test('同档次按固定次序,与插件目录顺序无关', () {
      // 同档次可能撞上多个源(用户自装的与随包的同档)。此前先后等于输入顺序,
      // 而输入顺序来自插件目录遍历顺序(文件系统决定)—— 升级后首页热歌榜会莫名
      // 换源。这里锁死:同一组源,任何输入顺序都得到同一个结果。
      final a = [
        _id('腾讯音乐', srcUrl: 'https://x/tx.js', fileName: 'plugin_1.js'),
        _id('我的酷我', srcUrl: 'https://x/mykuwo.js', fileName: 'plugin_2.js'),
        _id('酷我(念心音源)', srcUrl: 'https://x/kuwo_nianxin.js'),
      ];
      final b = a.reversed.toList();
      final o1 = orderAutoSourceIdentities(a).map((e) => e.platform).toList();
      final o2 = orderAutoSourceIdentities(b).map((e) => e.platform).toList();
      expect(o1.first, '腾讯音乐', reason: '腾讯系整体排第一(实测质量最好)');
      expect(
        o1.indexOf('酷我(念心音源)'),
        lessThan(o1.indexOf('我的酷我')),
        reason: '同档次内随包源按内置次序排在自装源前面',
      );
      expect(o2, o1, reason: '同一组源无论目录顺序如何,结果必须一致');
    });

    test('已撤下的老内置源不参与自动选源(只保留随包的三个)', () {
      // 用户要求「我就要腾讯音乐、网yi、酷我(念心音源)三个源」:1.7.56 收编的
      // 8 个 + 更早改名/下线的老内置源,即使还装在设备上,也不许再进自动线路。
      final ordered = orderAutoSourceIdentities([
        _id('腾讯音乐', srcUrl: 'https://x/tx.js'),
        _id('QQ音乐', srcUrl: 'https://x/qqmusic.js'),
        _id('网易云音乐', srcUrl: 'https://x/netease.js'),
        _id('酷我音乐', srcUrl: 'https://x/kuwo.js'),
        _id('哔哩哔哩', srcUrl: 'https://x/bilibili.js'),
        _id('酷我(独家音源)', srcUrl: 'https://x/kuwo_dujia.js'),
        _id('网yi', srcUrl: 'https://x/wy.js'),
        _id('酷我(念心音源)', srcUrl: 'https://x/kuwo_nianxin.js'),
      ]);
      expect(
        ordered.map((e) => e.platform).toList(),
        ['腾讯音乐', '网yi', '酷我(念心音源)'],
      );
    });

    test('内置源与用户自装源混排时,顺序也只由内容决定', () {
      final set = [
        _id('网yi', srcUrl: 'https://x/wy.js'),
        _id('网易音乐', srcUrl: 'https://x/wy.js', fileName: '网易音乐.js'),
        _id('我的自建源', srcUrl: 'https://my.example.com/foo.js'),
        _id('腾讯音乐', srcUrl: 'https://x/tx.js'),
      ];
      final forward = orderAutoSourceIdentities(set).map((e) => e.platform);
      final backward =
          orderAutoSourceIdentities(set.reversed.toList()).map((e) => e.platform);
      expect(forward.toList(), backward.toList());
    });

    test('同主名只保留一个,代理型(念心)变体优先', () {
      final ordered = orderAutoSourceIdentities([
        _id('酷我(独家音源)'),
        _id('酷我(念心音源)'),
      ]);
      expect(ordered.map((e) => e.platform), ['酷我(念心音源)']);
    });

    test('僵尸源被过滤,不参与自动搜索', () {
      final ordered = orderAutoSourceIdentities([
        _id('网yi'),
        _id('喜马拉雅(公开API)'),
      ]);
      expect(ordered.map((e) => e.platform), ['网yi']);
    });

    test('空输入安全', () {
      expect(orderAutoSourceIdentities(const []), isEmpty);
      expect(orderAutoSources(const []), isEmpty);
    });
  });

  test('proxyScore:代理型变体得分高于官方变体', () {
    expect(
      proxyScore('酷我(念心音源)'),
      greaterThan(proxyScore('酷我(独家音源)')),
    );
  });
}
