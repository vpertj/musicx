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

  group('歌手一致性(翻唱歌名与正版相同,只能靠歌手区分)', () {
    // 真机实测网易云「晴天 周杰伦」首屏:正版歌手是周杰伦,
    // 其余是 Lucky小爱 / 梦里啥都有 / Asasblue / 用户30223775 等翻唱号。
    final neteaseLike = <SongView>[
      (title: '晴天', artist: '周杰伦', album: '叶惠美'),
      (title: '晴天(深情版)', artist: 'Lucky小爱', album: '晴天(深情版)'),
      (title: '晴天', artist: '梦里啥都有', album: '晴天'),
      (title: '晴天', artist: 'Asasblue', album: '晴天'),
      (title: '晴天', artist: '用户30223775', album: '晴天'),
      (title: '晴天', artist: '周杰伦', album: '周杰伦地表最强世界巡回演唱会'),
      (title: '晴天', artist: '周杰伦&林俊杰', album: ''),
    ];

    test('能从查询里识别出歌手词(周杰伦)', () {
      final tokens = detectArtistTokens(neteaseLike, '晴天 周杰伦');
      expect(tokens, contains('周杰伦'));
      expect(tokens, isNot(contains('晴天')));
    });

    test('隐藏歌手完全不含查询歌手的翻唱条目', () {
      final kept = artistConsistentOrder(neteaseLike, '晴天 周杰伦');
      final keptArtists =
          kept.map((i) => neteaseLike[i].artist).toList();
      expect(keptArtists, isNot(contains('Lucky小爱')));
      expect(keptArtists, isNot(contains('梦里啥都有')));
      expect(keptArtists, isNot(contains('Asasblue')));
      expect(keptArtists, isNot(contains('用户30223775')));
      expect(keptArtists, contains('周杰伦'));
      expect(keptArtists, contains('周杰伦&林俊杰'));
    });

    test('正版只占少数(20%)时仍能识别歌手词 —— 网易首屏就是这种分布', () {
      final mostlyCovers = <SongView>[
        (title: '晴天', artist: '周杰伦', album: '叶惠美'),
        (title: '晴天', artist: '周杰伦', album: ''),
        (title: '晴天', artist: '周杰伦&林俊杰', album: ''),
        (title: '晴天', artist: '梦里啥都有', album: ''),
        (title: '晴天', artist: 'Asasblue', album: ''),
        (title: '晴天', artist: '安自宽', album: ''),
        (title: '晴天', artist: '夏天Alex', album: ''),
        (title: '晴天', artist: '沈幼楚', album: ''),
      ];
      expect(detectArtistTokens(mostlyCovers, '晴天 周杰伦'), contains('周杰伦'));
      final kept = artistConsistentOrder(mostlyCovers, '晴天 周杰伦');
      final artists = kept.map((i) => mostlyCovers[i].artist).toSet();
      expect(artists, isNot(contains('梦里啥都有')));
      expect(artists, isNot(contains('Asasblue')));
      expect(artists, contains('周杰伦'));
    });

    test('结果质量校验:整页翻唱(仅个别命中)判为不合格', () {
      final coverHeavy = <SongView>[
        for (var i = 0; i < 19; i++)
          (title: '晴天', artist: '翻唱号$i', album: ''),
        (title: '晴天', artist: '周杰伦', album: '叶惠美'),
      ];
      expect(isArtistMatchedResults(coverHeavy, '晴天 周杰伦'), isFalse,
          reason: '20 条里只有 1 条命中(5%),不能当成合格结果,应换源');

      final clean = <SongView>[
        for (var i = 0; i < 20; i++)
          (title: '歌$i', artist: '周杰伦', album: '专辑$i'),
      ];
      expect(isArtistMatchedResults(clean, '晴天 周杰伦'), isTrue);
    });

    test('无歌手词的查询不做质量校验(不能因此换源)', () {
      final songs = <SongView>[
        (title: '晴天', artist: '任何人', album: ''),
      ];
      expect(isArtistMatchedResults(songs, '晴天'), isTrue);
    });

    test('结果只有 1 条时不推断歌手(曾因 clamp 参数越界抛异常)', () {
      final one = <SongView>[(title: '晴天', artist: '周杰伦', album: '叶惠美')];
      expect(detectArtistTokens(one, '晴天 周杰伦'), isEmpty);
      expect(artistConsistentOrder(one, '晴天 周杰伦'), hasLength(1));
    });

    test('只搜歌名(无歌手词)时不过滤,避免误杀', () {
      final kept = artistConsistentOrder(neteaseLike, '晴天');
      expect(kept, hasLength(neteaseLike.length));
    });

    test('网易默认用户名(用户+数字)直接判为非原版', () {
      expect(
        looksLikeNonOriginal(title: '晴天', artist: '用户30223775'),
        isTrue,
      );
    });

    test('新增特征词:深情版 / R&B版 / 原唱标注 / 钢琴曲', () {
      expect(looksLikeNonOriginal(title: '晴天(深情版)', artist: 'x'), isTrue);
      expect(looksLikeNonOriginal(title: '晴天 (R&B版)', artist: 'x'), isTrue);
      expect(
        looksLikeNonOriginal(title: '晴天 (原唱 周杰伦)', artist: 'RyaVocal'),
        isTrue,
      );
      expect(looksLikeNonOriginal(title: '晴天', artist: 'x', album: '周杰伦钢琴曲集'),
          isTrue);
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
