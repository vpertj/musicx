// test/ui/playlist_manage_test.dart
//
// 用户反馈的两个歌单问题:
//   1) 新建的歌单无法删除(controller 有 deletePlaylist,界面没有入口)
//   2) 下载的歌曲无法加入指定歌单
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/library/library_controller.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/library/library_page.dart';

void main() {
  testWidgets('新建的歌单可以删除(标题栏入口 + 二次确认)', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final lib = container.read(libraryControllerProvider.notifier);
    final created = lib.createPlaylist('测试歌单');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 选中该歌单
    await tester.tap(find.text('测试歌单').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('删除歌单'), findsOneWidget,
        reason: '选中自定义歌单后应出现删除入口');

    // 确认删除
    await tester.tap(find.byTooltip('删除歌单'));
    await tester.pumpAndSettle();
    expect(find.textContaining('删除歌单「测试歌单」'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(
      container.read(libraryControllerProvider).playlists
          .where((p) => p.id == created.id),
      isEmpty,
      reason: '确认后歌单应被删除',
    );
    expect(find.text('测试歌单'), findsNothing);
  });

  testWidgets('「我喜欢的」不出现删除入口(不可删除)', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('删除歌单'), findsNothing);
  });

  testWidgets('歌单可加入歌曲(下载页复用同一选择器的前提)', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final lib = container.read(libraryControllerProvider.notifier);
    final p = lib.createPlaylist('目标歌单');
    const song = MusicItem(
      id: '1',
      title: '示例歌曲',
      platform: 'demo',
      songId: '1',
    );

    lib.addSongToPlaylist(p.id, song);

    final saved = container
        .read(libraryControllerProvider)
        .playlists
        .firstWhere((e) => e.id == p.id);
    expect(saved.songs.map((s) => s.title), contains('示例歌曲'));
    expect(saved.songs, hasLength(1));
  });
}
