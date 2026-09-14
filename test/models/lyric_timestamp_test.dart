// test/models/lyric_timestamp_test.dart
//
// 酷我(念心音源) 返回的 LRC 用「纯秒」时间戳([2.25] 表示 2.25 秒),
// 而解析器只认 [mm:ss.xx],导致该源歌词一行都显示不出来(parsedLines=0)。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/models/lyric_line.dart';

void main() {
  group('parseLrcTimestamp', () {
    test('标准 [mm:ss] 与 [mm:ss.xx]', () {
      expect(parseLrcTimestamp('01:23'), const Duration(minutes: 1, seconds: 23));
      expect(
        parseLrcTimestamp('01:23.45'),
        const Duration(minutes: 1, seconds: 23, milliseconds: 450),
      );
      expect(
        parseLrcTimestamp('00:00.000'),
        Duration.zero,
      );
    });

    test('纯秒 [ss] 与 [ss.xx](酷我念心音源格式)', () {
      expect(parseLrcTimestamp('0.0'), Duration.zero);
      expect(parseLrcTimestamp('2.25'), const Duration(milliseconds: 2250));
      expect(parseLrcTimestamp('20.25'), const Duration(milliseconds: 20250));
      expect(parseLrcTimestamp('123'), const Duration(seconds: 123));
      expect(parseLrcTimestamp('12.345'), const Duration(milliseconds: 12345));
    });

    test('元信息与非时间戳返回 null', () {
      expect(parseLrcTimestamp('ti:晴天'), isNull);
      expect(parseLrcTimestamp('ar:周杰伦'), isNull);
      expect(parseLrcTimestamp('offset:0'), isNull);
      expect(parseLrcTimestamp(''), isNull);
      expect(parseLrcTimestamp('abc'), isNull);
    });
  });

  group('parseLrc 兼容两种格式', () {
    test('纯秒格式能解析出行(酷我念心)', () {
      const lrc = '[0.0]晴天 - 周杰伦\n'
          '[2.25]词：周杰伦\n'
          '[4.5]曲：周杰伦\n'
          '[20.25]故事的小黄花\n';
      final lines = parseLrc(lrc);
      expect(lines, hasLength(4));
      expect(lines[1].time, const Duration(milliseconds: 2250));
      expect(lines[1].text, '词：周杰伦');
      expect(lines[3].text, '故事的小黄花');
    });

    test('标准格式不受影响(腾讯/网易)', () {
      const lrc = '[ti:晴天]\n[00:00.00]晴天 - 周杰伦\n[00:02.25]词：周杰伦\n';
      final lines = parseLrc(lrc);
      expect(lines, hasLength(2));
      expect(lines[1].time, const Duration(milliseconds: 2250));
    });

    test('同一行多时间戳仍展开', () {
      final lines = parseLrc('[00:01.00][00:05.50]重复句\n');
      expect(lines.map((e) => e.time).toList(), const [
        Duration(seconds: 1),
        Duration(milliseconds: 5500),
      ]);
      expect(lines.every((e) => e.text == '重复句'), isTrue);
    });

    test('纯元信息行不产生歌词行', () {
      expect(parseLrc('[ti:晴天]\n[ar:周杰伦]\n'), isEmpty);
    });
  });

  test('LyricLine.fromLrc 也支持纯秒', () {
    final line = LyricLine.fromLrc('[2.25]词：周杰伦');
    expect(line.time, const Duration(milliseconds: 2250));
    expect(line.text, '词：周杰伦');
  });
}
