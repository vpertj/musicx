// test/core/search/play_history_remove_test.dart
//
// 用户诉求:首页「最近播放」既不能整个清空,也不能删掉某一首。
//
// 这里锁死控制器侧的三个操作:清空、按歌曲移除、按下标移除。
// 判重口径必须与 record() 一致(platform|songId|title),否则会出现
// "点删除却没删掉"或"删错歌"。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/recommend.dart';

Map<String, dynamic> _song(String id, {String platform = 'kuwo'}) => {
  'id': id,
  'songId': id,
  'platform': platform,
  'title': '歌曲 $id',
  'artist': '歌手',
};

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(playHistoryProvider.notifier).clear();
    return c;
  }

  test('clear() 清空全部播放历史', () {
    final c = makeContainer();
    final n = c.read(playHistoryProvider.notifier);
    n.record(_song('a'));
    n.record(_song('b'));
    expect(c.read(playHistoryProvider), hasLength(2));

    n.clear();
    expect(c.read(playHistoryProvider), isEmpty);
  });

  test('removeEntry() 只删掉指定那一首,其余保留', () {
    final c = makeContainer();
    final n = c.read(playHistoryProvider.notifier);
    n.record(_song('a'));
    n.record(_song('b'));
    n.record(_song('c'));
    // record 是置顶插入,顺序应为 c, b, a
    expect(
      c.read(playHistoryProvider).map((e) => e['id']).toList(),
      ['c', 'b', 'a'],
    );

    n.removeEntry(_song('b'));

    expect(
      c.read(playHistoryProvider).map((e) => e['id']).toList(),
      ['c', 'a'],
      reason: '只应移除 b',
    );
  });

  test('removeEntry() 对不存在的歌曲是空操作', () {
    final c = makeContainer();
    final n = c.read(playHistoryProvider.notifier);
    n.record(_song('a'));
    n.removeEntry(_song('zzz'));
    expect(c.read(playHistoryProvider), hasLength(1));
  });

  test('removeAt() 按下标移除,越界安全', () {
    final c = makeContainer();
    final n = c.read(playHistoryProvider.notifier);
    n.record(_song('a'));
    n.record(_song('b'));
    n.record(_song('c')); // 顺序 c,b,a

    n.removeAt(0);
    expect(c.read(playHistoryProvider).map((e) => e['id']).toList(), [
      'b',
      'a',
    ]);

    // 越界不应抛异常、也不应改变数据
    n.removeAt(99);
    n.removeAt(-1);
    expect(c.read(playHistoryProvider), hasLength(2));
  });

  test('同 id 不同平台视为不同歌(判重口径含 platform)', () {
    final c = makeContainer();
    final n = c.read(playHistoryProvider.notifier);
    n.record(_song('x', platform: 'kuwo'));
    n.record(_song('x', platform: 'netease'));
    expect(c.read(playHistoryProvider), hasLength(2));

    n.removeEntry(_song('x', platform: 'kuwo'));
    expect(
      c.read(playHistoryProvider).map((e) => e['platform']).toList(),
      ['netease'],
      reason: '删 kuwo 的那首不应连带删掉 netease 的同名歌',
    );
  });
}
