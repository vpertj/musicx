// test/core/player/now_playing_metadata_test.dart
//
// 用户反馈:手机听歌息屏就停。修复靠 just_audio_background(前台服务 + 媒体通知),
// 而它要求每个音源都挂 MediaItem 元数据 —— 本文件锁住「控制层把曲目信息交给
// 播放服务」这条接线,否则通知栏没标题/锁屏没法控制,后台播放也就形同虚设。
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/player/player_service.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/models/music_item.dart';

class _RecordingService extends PlayerService {
  final List<String> playedUrls = [];
  NowPlaying? lastNowPlaying;

  @override
  Future<void> playUrl(String url, {NowPlaying? nowPlaying}) async {
    playedUrls.add(url);
    lastNowPlaying = nowPlaying;
  }

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
  }) async => {'url': 'https://example.com/${musicItem['songId']}.mp3'};

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
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    artwork: 'https://example.com/cover.jpg',
    duration: 269000,
    platform: 'demo',
    songId: 's1',
  );

  Future<(ProviderContainer, _RecordingService)> setup() async {
    final tmp = Directory.systemTemp.createTempSync('mx_now_playing');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final fake = _RecordingService();
    final c = ProviderContainer(
      overrides: [
        pluginManagerProvider.overrideWithValue(_FakeManager(tmp)),
        playerServiceProvider.overrideWith((ref) => fake),
      ],
    );
    addTearDown(c.dispose);
    return (c, fake);
  }

  test('在线播放:把标题/歌手/专辑/封面/时长交给播放服务', () async {
    final (c, fake) = await setup();
    await c.read(playerControllerProvider.notifier).playFromList([song], 0);

    final meta = fake.lastNowPlaying;
    expect(meta, isNotNull, reason: '没有元数据,通知栏/锁屏就是空白');
    expect(meta!.title, '晴天');
    expect(meta.artist, '周杰伦');
    expect(meta.album, '叶惠美');
    expect(meta.artwork, 'https://example.com/cover.jpg');
    expect(meta.duration, const Duration(milliseconds: 269000));

    // MediaItem 是 just_audio_background 的硬要求:封面要是带 scheme 的绝对 URI
    final item = meta.toMediaItem();
    expect(item.id, isNotEmpty);
    expect(item.title, '晴天');
    expect(item.artUri, Uri.parse('https://example.com/cover.jpg'));
  });

  test('本地(已下载)播放:同样带元数据', () async {
    final (c, fake) = await setup();
    final tmp = Directory.systemTemp.createTempSync('mx_now_playing_local');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final path = '${tmp.path}/a.mp3';
    File(path).writeAsStringSync('x');

    await c
        .read(playerControllerProvider.notifier)
        .playLocal(song, path, songs: [song], paths: [path]);

    expect(fake.playedUrls.single, 'file://$path');
    expect(fake.lastNowPlaying?.title, '晴天');
    expect(fake.lastNowPlaying?.artist, '周杰伦');
  });
}
