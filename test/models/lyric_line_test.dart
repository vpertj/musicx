// test/models/lyric_line_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/models/lyric_line.dart';

void main() {
  test('LyricLine.fromLrc parses [mm:ss.xx]text', () {
    final line = LyricLine.fromLrc('[01:23.45]你好世界');
    expect(line.time, const Duration(milliseconds: 83450));
    expect(line.text, '你好世界');
  });

  test('LyricLine.fromLrc ignores metadata lines', () {
    final line = LyricLine.fromLrc('[ar:歌手]');
    expect(line.text, isEmpty);
  });
}
