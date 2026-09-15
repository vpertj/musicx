// test/ui/favorite_toggle_test.dart
//
// 用户反馈:播放页进度条右上角的「❤️ 我喜欢」点了没反应,收藏不上。
//
// 根因不是收藏逻辑(数据其实写进去了),而是**界面不重建**:
//     ref.watch(libraryControllerProvider.notifier).isFavorite(song)
// 监听 `.notifier` 拿到的是控制器实例本身,它的引用不随 state 变化而改变,
// 因此 Riverpod 不会触发重建 —— 图标永远停在初始状态。
// 正确做法是 watch state,再基于 state 判断。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/library/library_controller.dart';
import 'package:musicx/models/music_item.dart';

MusicItem _song(String id) => MusicItem(
  id: id,
  title: '测试歌曲',
  artist: '测试歌手',
  platform: 'kuwo',
  songId: id,
);

/// 复刻播放页收藏按钮的判定方式(与 player_page.dart 保持一致)。
class _FavoriteIcon extends ConsumerWidget {
  const _FavoriteIcon({required this.song});
  final MusicItem song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 必须 watch state(而非 .notifier),否则收藏后图标不刷新。
    final isFav = ref
        .watch(libraryControllerProvider)
        .favorites
        .any((f) => f.id == song.id && f.platform == song.platform);
    return IconButton(
      icon: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded),
      onPressed: () =>
          ref.read(libraryControllerProvider.notifier).toggleFavorite(song),
    );
  }
}

void main() {
  Future<void> pumpIcon(WidgetTester tester, MusicItem song) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Center(child: _FavoriteIcon(song: song))),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('点❤️后图标立即变为已收藏(界面要重建)', (tester) async {
    final song = _song('fav-toggle-1');
    await pumpIcon(tester, song);

    // 保证从"未收藏"开始(避免历史数据干扰)
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_FavoriteIcon)),
    );
    if (container.read(libraryControllerProvider.notifier).isFavorite(song)) {
      container.read(libraryControllerProvider.notifier).toggleFavorite(song);
      await tester.pump();
    }
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();

    expect(
      find.byIcon(Icons.favorite_rounded),
      findsOneWidget,
      reason: '点击后必须立即显示实心❤️;若仍渲染空心,说明 watch 用错了对象',
    );
  });

  testWidgets('再点一次取消收藏,图标回到空心', (tester) async {
    final song = _song('fav-toggle-2');
    await pumpIcon(tester, song);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_FavoriteIcon)),
    );
    final notifier = container.read(libraryControllerProvider.notifier);
    if (notifier.isFavorite(song)) {
      notifier.toggleFavorite(song);
      await tester.pump();
    }

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget,
        reason: '取消收藏后应回到空心');

    // 清理,避免污染其他用例
    if (notifier.isFavorite(song)) notifier.toggleFavorite(song);
  });

  test('收藏数据确实写入 state(isFavorite 判重正确)', () {
    final song = _song('fav-state-1');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(libraryControllerProvider.notifier);
    if (n.isFavorite(song)) n.toggleFavorite(song);
    expect(n.isFavorite(song), isFalse);
    n.toggleFavorite(song);
    expect(n.isFavorite(song), isTrue);
    // 同 id 不同平台应视为不同歌曲
    final other = MusicItem(
      id: 'fav-state-1',
      title: '同名',
      platform: 'netease',
      songId: 'fav-state-1',
    );
    expect(n.isFavorite(other), isFalse, reason: '判重必须带上 platform');
    n.toggleFavorite(song); // 清理
  });
}
