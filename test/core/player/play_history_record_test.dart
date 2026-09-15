// test/core/player/play_history_record_test.dart
//
// 「最近播放」的数据来源:在线播放与本地(已下载)播放都必须记录,
// 否则只播下载歌曲的用户首页永远没有最近播放(实测缺口)。
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/player/player_service.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/core/search/recommend.dart';
import 'package:musicx/models/music_item.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const song = MusicItem(
    id: '1',
    title: '示例歌曲',
    artist: '歌手',
    platform: 'demo',
    songId: '1',
  );

  ProviderContainer makeContainer(Directory tmp) => ProviderContainer(
        overrides: [
          pluginManagerProvider.overrideWithValue(_FakeManager(tmp)),
          playerServiceProvider.overrideWith((ref) => _FakeService()),
        ],
      );

  test('在线播放会记入播放历史', () async {
    final tmp = Directory.systemTemp.createTempSync('mx_hist_online');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final c = makeContainer(tmp);
    addTearDown(c.dispose);

    await c.read(playerControllerProvider.notifier).playFromList([song], 0);
    final history = c.read(playHistoryProvider);
    expect(history.map((e) => e['title']), contains('示例歌曲'));
  });

  test('本地(已下载)播放也记入播放历史', () async {
    final tmp = Directory.systemTemp.createTempSync('mx_hist_local');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final c = makeContainer(tmp);
    addTearDown(c.dispose);

    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playLocal(song, '${tmp.path}/a.mp3', songs: [song]);
    final history = c.read(playHistoryProvider);
    expect(history.map((e) => e['title']), contains('示例歌曲'),
        reason: '只播下载歌曲的用户,首页也应有最近播放');
  });
}
