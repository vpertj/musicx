import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/library/library_controller.dart';
import 'package:musicx/models/music_item.dart';

MusicItem song(String id) => MusicItem(
      id: id,
      title: '歌$id',
      platform: 'test',
      songId: id,
    );

void main() {
  test('歌单:新建/加歌/喜欢/持久化', () {
    // 清理可能存在的历史数据
    final f = LibraryController.dataFile();
    if (f.existsSync()) f.deleteSync();
    addTearDown(() {
      if (f.existsSync()) f.deleteSync();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(libraryControllerProvider.notifier);

    // 喜欢
    ctrl.toggleFavorite(song('1'));
    ctrl.toggleFavorite(song('2'));
    expect(container.read(libraryControllerProvider).favorites.length, 2);
    ctrl.toggleFavorite(song('1'));
    expect(container.read(libraryControllerProvider).favorites.length, 1,
        reason: '重复点击取消喜欢');

    // 新建歌单 + 加歌
    final p = ctrl.createPlaylist('我的最爱');
    ctrl.addSongToPlaylist(p.id, song('1'));
    ctrl.addSongToPlaylist(p.id, song('2'));
    ctrl.addSongToPlaylist(p.id, song('1')); // 重复忽略
    final saved = container.read(libraryControllerProvider);
    expect(saved.playlists.single.name, '我的最爱');
    expect(saved.playlists.single.songs.length, 2);

    // 删除歌单
    ctrl.deletePlaylist(p.id);
    expect(container.read(libraryControllerProvider).playlists, isEmpty);

    // 持久化:新建后新容器应能读到
    ctrl.createPlaylist('持久化歌单');
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    expect(container2.read(libraryControllerProvider).playlists.length, 1);
    expect(container2.read(libraryControllerProvider).playlists.single.name,
        '持久化歌单');
  });
}
