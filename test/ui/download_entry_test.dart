// test/ui/download_entry_test.dart
//
// 用户诉求:方便下载「正在听」的歌 —— 播放页进度条上方要有下载按钮;
// 另外补齐「我的」页歌单行、首页最近播放行、播放队列行的下载入口。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/library/library_controller.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/player/player_service.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/library/library_page.dart';
import 'package:musicx/ui/player/player_page.dart';
import 'package:musicx/ui/widgets/seek_bar.dart';

class _FakeService extends PlayerService {
  @override
  Future<void> playUrl(String url) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  void dispose() {}
}

class _FakeManager extends PluginManager {
  _FakeManager(super.rootDir);
  @override
  Future<Map<String, dynamic>> resolveMediaSource(
    Map<String, dynamic> musicItem, {
    String quality = 'standard',
    Duration timeout = const Duration(seconds: 10),
  }) async => {'url': 'https://example.com/a.mp3'};
  @override
  Future<String> resolveLyric(
    Map<String, dynamic> musicItem, {
    Duration timeout = const Duration(seconds: 8),
  }) async => '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const song = MusicItem(
    id: '1',
    title: '示例歌曲',
    artist: '歌手',
    platform: 'demo',
    songId: '1',
  );

  testWidgets('播放页:进度条上方有下载按钮(正在听的歌)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tmp = Directory.systemTemp.createTempSync('mx_dl_entry');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        pluginManagerProvider.overrideWithValue(_FakeManager(tmp)),
        playerServiceProvider.overrideWith((ref) => _FakeService()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(playerControllerProvider.notifier).playFromList([song], 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PlayerPage()),
      ),
    );
    await tester.pump();

    expect(find.text('下载'), findsOneWidget, reason: '播放页应有下载按钮');
    // 位置:在进度条上方(下载按钮的底边不高于 SeekBar 的顶边)
    final dl = tester.getRect(find.text('下载'));
    // 进度条不是 Material Slider,而是自定义 SeekBar
    final seek = tester.getRect(find.byType(SeekBar).first);
    expect(dl.bottom, lessThanOrEqualTo(seek.top + 1),
        reason: '下载按钮应位于进度条上方');

    // 播放页同时提供收藏与加入歌单
    expect(find.byTooltip('加入歌单'), findsOneWidget);
  });

  testWidgets('「我的」页歌单内的歌曲行有下载入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tmp = Directory.systemTemp.createTempSync('mx_dl_lib');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [pluginManagerProvider.overrideWithValue(_FakeManager(tmp))],
    );
    addTearDown(container.dispose);
    final lib = container.read(libraryControllerProvider.notifier);
    for (final p in [...container.read(libraryControllerProvider).playlists]) {
      lib.deletePlaylist(p.id);
    }
    final pl = lib.createPlaylist('下载测试歌单');
    lib.addSongToPlaylist(pl.id, song);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载测试歌单').first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('下载'), findsWidgets,
        reason: '歌单内歌曲行此前没有下载入口');
  });
}
