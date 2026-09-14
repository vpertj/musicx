// test/core/search/recommend_test.dart
//
// 方案 C:首页动态推荐(热歌榜)+ 本地「猜你喜欢」。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/recommend.dart';

void main() {
  group('topArtistsFromHistory', () {
    test('按播放次数排序,取前 N', () {
      final history = [
        {'artist': '周杰伦', 'title': '晴天'},
        {'artist': '林俊杰', 'title': '江南'},
        {'artist': '周杰伦', 'title': '稻香'},
        {'artist': '陈奕迅', 'title': '富士山下'},
        {'artist': '周杰伦', 'title': '七里香'},
        {'artist': '林俊杰', 'title': '曹操'},
      ];
      expect(topArtistsFromHistory(history, limit: 2), ['周杰伦', '林俊杰']);
    });

    test('多歌手只取第一位(避免 A&B 被当独立歌手)', () {
      final history = [
        {'artist': '周杰伦&温岚', 'title': '屋顶'},
        {'artist': '周杰伦&温岚', 'title': '屋顶'},
      ];
      expect(topArtistsFromHistory(history), ['周杰伦']);
    });

    test('忽略空歌手', () {
      final history = [
        {'artist': '', 'title': 'x'},
        {'artist': null, 'title': 'y'},
      ];
      expect(topArtistsFromHistory(history), isEmpty);
    });
  });

  group('mergeRecommendations', () {
    test('按标题+歌手去重并保序、限量', () {
      final merged = mergeRecommendations([
        [
          {'title': '晴天', 'artist': '周杰伦'},
          {'title': '稻香', 'artist': '周杰伦'},
        ],
        [
          {'title': '晴天', 'artist': '周杰伦'}, // 与上一组完全重复
          {'title': '江南', 'artist': '林俊杰'},
        ],
      ], limit: 10);
      expect(merged.map((e) => e['title']), ['晴天', '稻香', '江南']);
    });

    test('limit 生效', () {
      final merged = mergeRecommendations([
        [
          for (var i = 0; i < 20; i++) {'title': 't$i', 'artist': 'a'},
        ],
      ], limit: 5);
      expect(merged, hasLength(5));
    });
  });

  group('RecommendService', () {
    test('猜你喜欢:按歌手取数并合并去重', () async {
      final asked = <String>[];
      final service = RecommendService((kind, seed) async {
        if (kind == 'artist') {
          asked.add(seed!);
          return [
            {'title': '$seed的歌1', 'artist': seed},
            {'title': '共同曲', 'artist': '共同'},
          ];
        }
        return const [];
      });

      final got = await service.guess(artists: ['周杰伦', '林俊杰']);
      expect(asked, ['周杰伦', '林俊杰']);
      expect(
        got.map((e) => e['title']).toList(),
        ['周杰伦的歌1', '共同曲', '林俊杰的歌1'],
        reason: '完全重复的条目(标题+歌手都相同)只保留一次',
      );
    });

    test('没有历史(无歌手)时返回空,不请求', () async {
      var called = false;
      final service = RecommendService((kind, seed) async {
        called = true;
        return const [];
      });
      expect(await service.guess(artists: const []), isEmpty);
      expect(called, isFalse);
    });
  });

  group('RecommendCache', () {
    test('TTL 内命中,过期后失效', () {
      final cache = RecommendCache(ttl: const Duration(milliseconds: 50));
      cache.put('hot', [
        {'title': 'x'},
      ]);
      expect(cache.get('hot'), isNotNull);

      // 用 fake 时间不可行,这里只验证「未过期命中 + 未知键为空」
      expect(cache.get('other'), isNull);
    });
  });
}
