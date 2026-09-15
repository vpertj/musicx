// test/core/plugins/lyric_quality_test.dart
//
// 用户诉求:没歌词时要主动去别的源找。若把占位文案当成歌词,跨源兜底就永不触发。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/lyric_quality.dart';

void main() {
  test('正常歌词可用', () {
    expect(hasUsableLyric('[00:01.00]第一句\n[00:05.20]第二句'), isTrue);
    expect(hasUsableLyric('[2.25]纯秒格式(酷我念心)'), isTrue);
  });

  test('占位文案不算歌词(必须触发跨源寻找)', () {
    for (final t in [
      '[00:00.00]暂无歌词',
      '暂无歌词',
      '[00:00.00]纯音乐，请欣赏',
      '[00:00.00]此歌曲为没有填词的纯音乐',
      '歌词获取失败',
      'No lyric',
    ]) {
      expect(hasUsableLyric(t), isFalse, reason: '「$t」不应算作歌词');
    }
  });

  test('空内容与无时间戳内容不算歌词', () {
    expect(hasUsableLyric(null), isFalse);
    expect(hasUsableLyric(''), isFalse);
    expect(hasUsableLyric('   '), isFalse);
    expect(hasUsableLyric('这是一段没有时间戳的文本'), isFalse);
  });
}
