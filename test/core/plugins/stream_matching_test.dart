// test/core/plugins/stream_matching_test.dart
//
// 跨源取流的核心风险是「串歌」,这里锁住严格校验的边界。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/stream_matching.dart';

void main() {
  group('normalizeTitle', () {
    test('去掉括号内容(版本标注)与装饰符', () {
      expect(normalizeTitle('晴天 (Live)'), '晴天');
      expect(normalizeTitle('晴天【伴奏】'), '晴天');
      expect(normalizeTitle(' 晴天 '), '晴天');
      expect(normalizeTitle('Try (Kung Fu Panda 3)'), 'try');
    });
  });

  group('primaryArtist', () {
    test('多歌手取第一位', () {
      expect(primaryArtist('周杰伦&温岚'), '周杰伦');
      expect(primaryArtist('蔡依林/周杰伦'), '蔡依林');
      expect(primaryArtist('王以太 & 艾热 AIR'), '王以太');
    });
  });

  group('isSameSongStrict', () {
    test('同名同歌手同时长 → 同一首', () {
      expect(
        isSameSongStrict(
          title: '晴天',
          artist: '周杰伦',
          durationMs: 269000,
          otherTitle: '晴天',
          otherArtist: '周杰伦',
          otherDurationMs: 269500,
        ),
        isTrue,
      );
    });

    test('歌名不同 → 拒绝(绝不串歌)', () {
      expect(
        isSameSongStrict(
          title: '晴天',
          artist: '周杰伦',
          otherTitle: '晴天娃娃',
          otherArtist: '周杰伦',
        ),
        isFalse,
      );
    });

    test('歌手不同 → 拒绝(挡住翻唱)', () {
      expect(
        isSameSongStrict(
          title: '晴天',
          artist: '周杰伦',
          otherTitle: '晴天',
          otherArtist: 'Lucky小爱',
        ),
        isFalse,
      );
    });

    test('时长差超过 3 秒 → 拒绝(挡住试听片段/错版)', () {
      expect(
        isSameSongStrict(
          title: '晴天',
          artist: '周杰伦',
          durationMs: 269000,
          otherTitle: '晴天',
          otherArtist: '周杰伦',
          otherDurationMs: 45000,
        ),
        isFalse,
      );
    });

    test('候选带版本标注但歌名主体相同 → 允许(规范化后相等)', () {
      expect(
        isSameSongStrict(
          title: '晴天',
          artist: '周杰伦',
          otherTitle: '晴天 (Live)',
          otherArtist: '周杰伦',
        ),
        isTrue,
      );
    });

    test('时长未知 → 不做时长判断(其余条件仍需满足)', () {
      expect(
        isSameSongStrict(
          title: '晴天',
          artist: '周杰伦',
          otherTitle: '晴天',
          otherArtist: '周杰伦',
        ),
        isTrue,
      );
    });
  });

  group('isTrustedFastRelay', () {
    test('念心等中转源可信(跳过体积探测),官方源不可信', () {
      expect(isTrustedFastRelay('酷我(念心音源)'), isTrue);
      expect(isTrustedFastRelay('念心'), isTrue);
      expect(isTrustedFastRelay('腾讯音乐'), isFalse);
      expect(isTrustedFastRelay('网yi'), isFalse);
      expect(isTrustedFastRelay(null), isFalse);
    });
  });

  group('streamSpeedScore', () {
    test('快源优先:念心 < 网易 < 其它酷我 < 未知', () {
      expect(streamSpeedScore('酷我(念心音源)'), 0);
      expect(streamSpeedScore('网yi'), 1);
      expect(streamSpeedScore('酷我(独家音源)'), 2);
      expect(streamSpeedScore('腾讯音乐'), 10);
    });
  });
}
