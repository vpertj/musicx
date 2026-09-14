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
    test('用户现有 4 个源:网易云最前,腾讯次之(即使网易被改名为 网yi)', () {
      final ordered = orderAutoSourceIdentities([
        _id('腾讯音乐', srcUrl: 'https://x/tx.js'),
        _id('网yi', srcUrl: 'https://x/wy.js', fileName: '网易音乐.js'),
        _id('酷我(独家音源)', srcUrl: 'https://x/酷我_竹岑.js'),
        _id('酷我(念心音源)', srcUrl: 'https://x/酷我_念心.js'),
      ]);
      expect(ordered.first.platform, '网yi');
      expect(ordered[1].platform, '腾讯音乐');
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
