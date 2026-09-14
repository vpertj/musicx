import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/player/player_service.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/models/music_item.dart';

/// 切歌提速:媒体地址缓存 + 下一首预取 + 本地队列直读。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MusicItem song(int i) =>
      MusicItem(id: '$i', title: '歌$i', platform: 'demo', songId: '$i');

  test('resolveMediaSource 二次调用命中缓存(同一对象),TTL 内不再解析', () async {
    final tmp = Directory.systemTemp.createTempSync('musicx_media_cache');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/demo.js').writeAsStringSync('''
module.exports = { platform: "demo", version: "0.1.0",
  getMediaSource: function (m) {
    return { url: "https://x/" + m.songId + ".mp3" };
  }
};
''');
    final manager = PluginManager(
      tmp,
      // CDN 探测在单测环境不可用,注入「未知」探针:不影响缓存语义
      audioTotalBytesProbe: (_) async => -1,
    );
    final item = song(1).toJson();
    final r1 = await manager.resolveMediaSource(item);
    final r2 = await manager.resolveMediaSource(item);
    // 命中缓存返回同一结果对象(未命中则每次重新解析产生新实例)
    expect(identical(r1, r2), isTrue);

    // 不同歌曲不共享缓存
    final r3 = await manager.resolveMediaSource(song(2).toJson());
    expect(identical(r1, r3), isFalse);
    expect(r3['url'], 'https://x/2.mp3');
  });

  test('在线队列播放成功后预取下一首地址', () async {
    final fakeManager = _RecordingManager();
    final fakeService = _FakePlayerService();
    final container = ProviderContainer(
      overrides: [
        pluginManagerProvider.overrideWithValue(fakeManager),
        playerServiceProvider.overrideWith((ref) => fakeService),
      ],
    );
    addTearDown(container.dispose);

    final ctrl = container.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2)], 0);
    // _playCurrent 在 playUrl 后 fire-and-forget 预取;让微任务落地
    await Future<void>.delayed(Duration.zero);

    expect(fakeService.lastUrl, 'https://x/1.mp3');
    expect(fakeManager.prefetched, contains('2'));
  });

  test('本地下载队列连播:切换直接读本地文件,不走插件解析', () async {
    final fakeManager = _RecordingManager();
    final fakeService = _FakePlayerService();
    final container = ProviderContainer(
      overrides: [
        pluginManagerProvider.overrideWithValue(fakeManager),
        playerServiceProvider.overrideWith((ref) => fakeService),
      ],
    );
    addTearDown(container.dispose);

    final ctrl = container.read(playerControllerProvider.notifier);
    await ctrl.playLocal(
      song(1),
      '/downloads/a.mp3',
      songs: [song(1), song(2)],
      paths: ['/downloads/a.mp3', '/downloads/b.mp3'],
    );
    expect(fakeService.lastUrl, 'file:///downloads/a.mp3');

    await ctrl.next();
    expect(container.read(playerControllerProvider).currentIndex, 1);
    expect(fakeService.lastUrl, 'file:///downloads/b.mp3');
    // 本地队列全程不做网络解析/预取
    expect(fakeManager.resolved, isEmpty);
    expect(fakeManager.prefetched, isEmpty);

    // 之后从搜索页播放在线歌单,应退出本地模式正常解析
    await ctrl.playFromList([song(1)], 0);
    expect(fakeService.lastUrl, 'https://x/1.mp3');
    expect(fakeManager.resolved, isNotEmpty);
  });
}

/// 记录型假 PluginManager:解析返回固定 url,记录解析与预取目标。
class _RecordingManager extends PluginManager {
  _RecordingManager() : super(Directory(''));

  final List<String> resolved = [];
  final List<String> prefetched = [];

  @override
  Future<Map<String, dynamic>> resolveMediaSource(
    Map<String, dynamic> musicItem, {
    String quality = 'standard',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    resolved.add('${musicItem['songId']}');
    return {'url': 'https://x/${musicItem['songId']}.mp3'};
  }

  @override
  Future<void> prefetchMediaSource(
    Map<String, dynamic> musicItem, {
    String quality = 'standard',
  }) async {
    prefetched.add('${musicItem['songId']}');
  }
}

/// 假 PlayerService:只记录 url。
class _FakePlayerService extends PlayerService {
  String? lastUrl;
  @override
  Future<void> playUrl(String url) async {
    lastUrl = url;
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
