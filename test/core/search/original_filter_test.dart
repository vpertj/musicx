// test/core/search/original_filter_test.dart
//
// 用户诉求:内置音源里不要翻唱,尽量给正版原唱。
// 各音源(尤其网易)搜索结果前排常混入用户上传的翻唱/伴奏/纯音乐版本,
// 用标题/专辑/歌手的强特征词识别并降权/过滤。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/original_filter.dart';

void main() {
  group('looksLikeCover', () {
    test('标题带翻唱/cover 特征词', () {
      expect(looksLikeCover(title: '晴天 (翻唱版)', artist: '某某'), isTrue);
      expect(looksLikeCover(title: '晴天 cover', artist: '某某'), isTrue);
      expect(looksLikeCover(title: '晴天（女声版）', artist: '某某'), isTrue);
      expect(looksLikeCover(title: '晴天 DJ版', artist: '某某'), isTrue);
      expect(looksLikeCover(title: '晴天 伴奏', artist: '某某'), isTrue);
      expect(looksLikeCover(title: '晴天 纯音乐', artist: '某某'), isTrue);
      expect(looksLikeCover(title: '晴天 钢琴版', artist: '某某'), isTrue);
      expect(looksLikeCover(title: '晴天 抖音版', artist: '某某'), isTrue);
      expect(looksLikeCover(title: '晴天 片段', artist: '某某'), isTrue);
    });

    test('专辑带特征词也算', () {
      expect(
        looksLikeCover(title: '晴天', artist: '周杰伦', album: '翻唱合集'),
        isTrue,
      );
      expect(
        looksLikeCover(title: '晴天', artist: '周杰伦', album: 'Cover Songs'),
        isTrue,
      );
    });

    test('歌手名本身是翻唱号', () {
      expect(looksLikeCover(title: '晴天', artist: '翻唱小王子'), isTrue);
      expect(looksLikeCover(title: '晴天', artist: 'Cover Nation'), isTrue);
    });

    test('混音/DJ/Live/变速等「其它版本」一律过滤(用户只要原版)', () {
      expect(looksLikeNonOriginal(title: '晴天 (Remix)', artist: '周杰伦'), isTrue);
      expect(looksLikeNonOriginal(title: '晴天 混音版', artist: '周杰伦'), isTrue);
      expect(looksLikeNonOriginal(title: '晴天 DJ版', artist: '周杰伦'), isTrue);
      expect(looksLikeNonOriginal(title: '晴天 (Live)', artist: '周杰伦'), isTrue);
      expect(looksLikeNonOriginal(title: '晴天 现场版', artist: '周杰伦'), isTrue);
      expect(looksLikeNonOriginal(title: '晴天 演唱会版', artist: '周杰伦'), isTrue);
      expect(looksLikeNonOriginal(title: '晴天 加速版', artist: '周杰伦'), isTrue);
      expect(looksLikeNonOriginal(title: '晴天 8D环绕', artist: '周杰伦'), isTrue);
      expect(looksLikeNonOriginal(title: '晴天 铃声', artist: '周杰伦'), isTrue);
      expect(looksLikeNonOriginal(title: '晴天 (不插电)', artist: '周杰伦'), isFalse,
          reason: '不插电是官方常见版本,暂不误杀');
    });

    test('正常原唱不误杀', () {
      expect(
        looksLikeCover(title: '晴天', artist: '周杰伦', album: '叶惠美'),
        isFalse,
      );
      expect(
        looksLikeCover(title: '起风了', artist: '买辣椒也用券'),
        isFalse,
      );
      // 「合唱」是正常合作形式,不当翻唱
      expect(
        looksLikeCover(title: '屋顶', artist: '周杰伦&温岚'),
        isFalse,
      );
      // Live 属于「其它版本」,用户只要原版 → 现在会过滤(见上一条用例)
    });
  });

  group('rankSearchResults', () {
    test('歌手命中查询的排前面,翻唱排后面', () {
      final ranked = rankSearchResults([
        (title: '晴天 (翻唱版)', artist: '小透明', album: '翻唱合集'),
        (title: '晴天', artist: '周杰伦', album: '叶惠美'),
        (title: '晴天', artist: '周杰伦', album: '演唱会'),
      ], query: '晴天 周杰伦');
      expect(ranked.first.artist, '周杰伦');
      expect(ranked.last.title, contains('翻唱'));
    });

    test('偏好有专辑信息的条目(野生上传常缺专辑)', () {
      final ranked = rankSearchResults([
        (title: '晴天', artist: '周杰伦', album: ''),
        (title: '晴天', artist: '周杰伦', album: '叶惠美'),
      ], query: '晴天 周杰伦');
      expect(ranked.first.album, '叶惠美');
    });

    test('Live/remix 等非原版降权但不隐藏', () {
      final ranked = rankSearchResults([
        (title: '晴天 (Live)', artist: '周杰伦', album: '演唱会'),
        (title: '晴天', artist: '周杰伦', album: '叶惠美'),
      ], query: '晴天 周杰伦');
      expect(ranked.first.title, '晴天');
      expect(ranked.length, 2, reason: 'Live 不应被过滤掉');
    });
  });

  group('filterOriginals', () {
    test('只留原版:翻唱、Live、Remix 都被过滤(用户只要原版)', () {
      final kept = filterOriginals([
        (title: '晴天 (翻唱版)', artist: '小透明', album: '翻唱合集'),
        (title: '晴天', artist: '周杰伦', album: '叶惠美'),
        (title: '晴天 (Live)', artist: '周杰伦', album: '演唱会'),
        (title: '晴天 (Remix)', artist: '周杰伦', album: ''),
      ]);
      expect(kept.map((e) => e.title).toList(), ['晴天']);
    });

    test('全是翻唱时不过滤到空(否则用户什么都搜不到)', () {
      final kept = filterOriginals([
        (title: '晴天 翻唱', artist: 'a', album: ''),
        (title: '晴天 cover', artist: 'b', album: ''),
      ]);
      expect(kept, isNotEmpty);
    });
  });
}
