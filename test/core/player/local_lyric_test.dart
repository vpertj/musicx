// test/core/player/local_lyric_test.dart
//
// 用户反馈:「下载的歌曲再次播放时没有歌词」。
//
// 排查:本地(已下载)播放**只读**下载时写的旁挂 `.lrc`,不联网补词
// (commit b0da591 的设计:「本地播放应完全离线可用」)。于是两类歌永远没词:
//   - 功能上线(1.7.4x)之前下载的老歌,根本没有 `.lrc`;
//   - 下载当刻歌词源没给词(占位文案/接口失败)的歌。
// 在线播放同一首歌却有词 —— 用户看到的就是「再次播放没歌词」。
//
// 本文件锁定新行为:旁挂歌词优先(离线可用),**没有旁挂文件时才联网补一次并
// 回填 `.lrc`**,下次离线播放也有词;取不到词不写文件、不影响播放。
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/download/lyric_sidecar.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/player/player_service.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/models/music_item.dart';

class _FakeService extends PlayerService {
  final List<String> playedUrls = [];

  @override
  Future<void> playUrl(String url) async => playedUrls.add(url);
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

class _LyricManager extends PluginManager {
  _LyricManager(super.rootDir, {this.lyric = '[00:01.00]联网词'});

  /// 歌词源返回的内容;空串表示「这个源没有词」。
  final String lyric;
  final List<String> lyricRequests = [];

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
  }) async {
    lyricRequests.add('${musicItem['songId']}');
    return lyric;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MusicItem song(int i) =>
      MusicItem(id: '$i', title: '歌$i', platform: 'demo', songId: '$i');

  Future<(ProviderContainer, _FakeService, _LyricManager, Directory)> setup({
    String lyric = '[00:01.00]联网词',
  }) async {
    final tmp = Directory.systemTemp.createTempSync('mx_local_lyric');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final fake = _FakeService();
    final mgr = _LyricManager(tmp, lyric: lyric);
    final c = ProviderContainer(
      overrides: [
        pluginManagerProvider.overrideWithValue(mgr),
        playerServiceProvider.overrideWith((ref) => fake),
      ],
    );
    addTearDown(c.dispose);
    return (c, fake, mgr, tmp);
  }

  test('有旁挂 .lrc:直接显示,且不联网找词(离线可用)', () async {
    final (c, fake, mgr, tmp) = await setup();
    final audio = '${tmp.path}/a.mp3';
    File(audio).writeAsStringSync('x');
    await writeLyricSidecar(audio, '[00:01.00]旁挂词');

    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playLocal(song(1), audio, songs: [song(1)], paths: [audio]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final s = c.read(playerControllerProvider);
    expect(fake.playedUrls, ['file://$audio']);
    expect(s.lyric.map((l) => l.text), ['旁挂词']);
    expect(mgr.lyricRequests, isEmpty, reason: '有旁挂歌词就不该再联网找');
  });

  test('没有旁挂 .lrc:联网补词并回填(老下载不再永远没词)', () async {
    final (c, _, mgr, tmp) = await setup();
    final audio = '${tmp.path}/a.mp3';
    File(audio).writeAsStringSync('x');

    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playLocal(song(1), audio, songs: [song(1)], paths: [audio]);

    // 不阻塞播放:歌词还在后台取,状态已切到播放中
    expect(c.read(playerControllerProvider).isPlaying, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 100));

    final s = c.read(playerControllerProvider);
    expect(mgr.lyricRequests, ['1'], reason: '没有旁挂歌词应联网补一次');
    expect(s.lyric.map((l) => l.text), ['联网词']);
    expect(
      await readLyricSidecar(audio),
      isNotNull,
      reason: '取到的歌词要回填旁挂文件,下次离线播放也有词',
    );
  });

  test('没有旁挂 .lrc 且源上没词:不写文件、不报错、不影响播放', () async {
    final (c, _, mgr, tmp) = await setup(lyric: '');
    final audio = '${tmp.path}/a.mp3';
    File(audio).writeAsStringSync('x');

    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playLocal(song(1), audio, songs: [song(1)], paths: [audio]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final s = c.read(playerControllerProvider);
    expect(mgr.lyricRequests, ['1']);
    expect(s.lyric, isEmpty);
    expect(s.error, isNull);
    expect(s.isPlaying, isTrue);
    expect(File(lrcPathFor(audio)).existsSync(), isFalse);
  });
}
