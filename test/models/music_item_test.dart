// test/models/music_item_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/models/music_item.dart';

void main() {
  test('MusicItem fromJson → toJson roundtrip', () {
    final json = {
      'id': 'abc', 'title': '测试歌曲', 'artist': '歌手甲', 'album': '专辑乙',
      'artwork': 'http://x/a.jpg', 'duration': 210000,
      'platform': 'test-plugin', 'songId': 's1',
      'extra': {'quality': 'hq'},
    };
    final item = MusicItem.fromJson(json);
    expect(item.title, '测试歌曲');
    expect(item.platform, 'test-plugin');
    expect(item.toJson(), json);
  });

  test('MusicItem requires id/title/platform/songId', () {
    expect(() => MusicItem.fromJson({'title': 'x'}), throwsArgumentError);
  });
}
