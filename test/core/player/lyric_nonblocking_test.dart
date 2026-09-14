// test/core/player/lyric_nonblocking_test.dart
//
// 用户反馈:列表里点击歌曲切歌非常慢、歌词也慢。
// 根因:_playCurrent 里 await 歌词解析后才把状态置为「播放中」,而歌词解析包含
// 重试与跨源兜底(要再发搜索请求)。本用例锁住「歌词不阻塞播放」。
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/player/player_service.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/models/music_item.dart';

/// 媒体解析瞬间完成、歌词很慢(300ms),用于验证阻塞关系。
class _SlowLyricManager extends PluginManager {
  _SlowLyricManager(super.rootDir);

  @override
  Future<Map<String, dynamic>> resolveMediaSource(
    Map<String, dynamic> musicItem, {
    String quality = 'standard',
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      {'url': 'https://example.com/a.mp3'};

  @override
  Future<String> resolveLyric(
    Map<String, dynamic> musicItem, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return '[00:01.00]第一句';
  }
}

void main() {
  // PlayerService 构造会创建 just_audio 播放器,需要先初始化绑定
  TestWidgetsFlutterBinding.ensureInitialized();

  test('歌词解析不阻塞「播放中」状态(切歌体感)', () async {
    final tmp = Directory.systemTemp.createTempSync('mx_lyric_nonblock');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        pluginManagerProvider.overrideWithValue(_SlowLyricManager(tmp)),
        // 播放服务在单测里不可用(just_audio 无插件),用假的替换
        playerServiceProvider.overrideWith((ref) => _FakePlayerService()),
      ],
    );
    addTearDown(container.dispose);

    final ctrl = container.read(playerControllerProvider.notifier);
    const song = MusicItem(
      id: '1',
      title: '示例歌曲',
      artist: '歌手',
      platform: 'demo',
      songId: '1',
    );

    // 播放(不 await:歌词仍在后台)
    final playing = ctrl.playFromList([song], 0);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final midway = container.read(playerControllerProvider);
    expect(midway.current?.title, '示例歌曲', reason: '当前曲目应已切换');
    expect(midway.lyric, isEmpty, reason: '此刻歌词还没到(后台仍在取)');

    await playing;
    // 等歌词后台完成
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(
      container.read(playerControllerProvider).lyric,
      isNotEmpty,
      reason: '歌词应在后台完成后写入状态',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}

class _FakePlayerService extends PlayerService {
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
