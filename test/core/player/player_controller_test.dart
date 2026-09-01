import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/player/player_service.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/models/music_item.dart';

void main() {
  // 控制器 build 会实例化 PlayerService(just_audio),需要绑定平台通道
  TestWidgetsFlutterBinding.ensureInitialized();

  MusicItem song(int i) =>
      MusicItem(id: '$i', title: '歌$i', platform: 'demo', songId: '$i');

  test('playFromList sets queue and current index', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(playerControllerProvider.notifier);
    ctrl.playFromList([song(1), song(2)], 0);
    final s = container.read(playerControllerProvider);
    expect(s.queue, hasLength(2));
    expect(s.currentIndex, 0);
    expect(s.queue[0].title, '歌1');
  });

  test('next/previous move index within bounds', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(playerControllerProvider.notifier);
    ctrl.playFromList([song(1), song(2)], 0);
    ctrl.next();
    expect(container.read(playerControllerProvider).currentIndex, 1);
    ctrl.next();
    expect(container.read(playerControllerProvider).currentIndex, 1); // 不越界
    ctrl.previous();
    ctrl.previous();
    expect(container.read(playerControllerProvider).currentIndex, 0); // 不越界
  });

  test('stale media request does not overwrite newer playback (token guard)',
      () async {
    // 可控的假 PluginManager:不同 song 的 resolveMediaSource 用不同 completer 延迟。
    final firstGate = Completer<Map<String, dynamic>>();
    final fakeManager = _FakePluginManager(firstGate: firstGate);
    final fakeService = _FakePlayerService();
    final container = ProviderContainer(
      overrides: [
        pluginManagerProvider.overrideWithValue(fakeManager),
        playerServiceProvider.overrideWith((ref) => fakeService),
      ],
    );
    addTearDown(container.dispose);

    final ctrl = container.read(playerControllerProvider.notifier);
    // 请求 A:song1,其 resolveMediaSource 被 firstGate 挂起(慢)
    final first = ctrl.playFromList([song(1), song(2)], 0);
    // 请求 B:切到 song2(快),应立即完成并播放 song2
    await ctrl.next();

    // 现在释放 A 的 resolveMediaSource 为 song1 的 url(迟到)
    await Future<void>.delayed(const Duration(milliseconds: 20));
    firstGate.complete({'url': 'http://song1'});
    await first;

    final s = container.read(playerControllerProvider);
    // A 完成后 token 已过期,不应覆盖 B;最终播放的是 song2 而非迟到的 song1
    expect(s.currentIndex, 1);
    expect(fakeService.lastUrl, 'http://song2');
  });
}

/// 假 PluginManager:首个 song(id=1)的 resolveMediaSource 等待 [firstGate],
/// 其余立即返回对应 url。
class _FakePluginManager extends PluginManager {
  final Completer<Map<String, dynamic>> firstGate;
  _FakePluginManager({required this.firstGate})
      : super(Directory(''));

  @override
  Future<Map<String, dynamic>> resolveMediaSource(
    Map<String, dynamic> musicItem, {
    String quality = 'standard',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final id = musicItem['songId'] as String? ?? '';
    if (id == '1') {
      return await firstGate.future;
    }
    return {'url': 'http://song$id'};
  }
}

/// 假 PlayerService:不真正播放只记录 url,避免真实 just_audio 依赖。
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
  void dispose() {
    // 不关闭父类真实 player(避免对测试环境造成影响)
  }
}
