// test/core/player/loop_manual_nav_test.dart
//
// 用户反馈:单曲循环 / 列表循环「有问题」。
//
// 定位到的缺陷:_advance() 被**自动播完**与**手动切歌**共用,而单曲循环
// 分支直接返回当前下标:
//     if (state.repeatMode == LoopMode.one) return state.currentIndex;
// 于是单曲循环下点「下一首/上一首」只会原地重播同一首,用户无法手动换歌。
//
// 正确语义(与主流播放器一致):
//   - 自动播完:单曲循环 → 重播当前曲;列表循环 → 播下一首,到尾回到开头;
//     顺序播放 → 到尾停下。
//   - 手动切歌:单曲循环不应阻止用户换歌 —— 应正常按队列前后移动,
//     到尾按当前模式处理(列表循环回到另一端,顺序播放停在原处)。
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/player/player_service.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/models/music_item.dart';

class _FakeService extends PlayerService {
  final _completed = StreamController<void>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();

  final List<String> playedUrls = [];

  @override
  Stream<void> get completedStream => _completed.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;

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

  void fireCompleted() => _completed.add(null);
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

  MusicItem song(int i) =>
      MusicItem(id: '$i', title: '歌$i', platform: 'demo', songId: '$i');

  Future<(ProviderContainer, _FakeService)> setup() async {
    final tmp = Directory.systemTemp.createTempSync('mx_loop_nav');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final fake = _FakeService();
    final c = ProviderContainer(
      overrides: [
        pluginManagerProvider.overrideWithValue(_FakeManager(tmp)),
        playerServiceProvider.overrideWith((ref) => fake),
      ],
    );
    addTearDown(c.dispose);
    return (c, fake);
  }

  Future<PlayerController> startAt(
    ProviderContainer c,
    List<MusicItem> queue,
    int index,
  ) async {
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList(queue, index);
    return ctrl;
  }

  void setMode(ProviderContainer c, LoopMode mode) {
    final ctrl = c.read(playerControllerProvider.notifier);
    var guard = 0;
    while (c.read(playerControllerProvider).repeatMode != mode) {
      ctrl.toggleRepeat();
      if (++guard > 5) fail('无法切换到 $mode');
    }
  }

  group('单曲循环:手动切歌', () {
    test('点「下一首」应切到下一首,而不是原地重播', () async {
      final (c, _) = await setup();
      final ctrl = await startAt(c, [song(1), song(2), song(3)], 0);
      setMode(c, LoopMode.one);

      await ctrl.next();

      expect(
        c.read(playerControllerProvider).currentIndex,
        1,
        reason: '单曲循环只影响"自动播完"的行为;手动点下一首应正常换歌',
      );
    });

    test('点「上一首」应切到上一首', () async {
      final (c, _) = await setup();
      final ctrl = await startAt(c, [song(1), song(2), song(3)], 2);
      setMode(c, LoopMode.one);

      await ctrl.previous();

      expect(c.read(playerControllerProvider).currentIndex, 1);
    });

    test('在第一首点「上一首」:单曲循环下应回到最后一首(队列可循环)', () async {
      final (c, _) = await setup();
      final ctrl = await startAt(c, [song(1), song(2), song(3)], 0);
      setMode(c, LoopMode.one);

      await ctrl.previous();

      expect(
        c.read(playerControllerProvider).currentIndex,
        2,
        reason: '单曲循环属于"会循环"的模式,边界应绕回另一端而不是卡住',
      );
    });
  });

  group('单曲循环:自动播完', () {
    test('播完重播同一首(不切歌)', () async {
      final (c, fake) = await setup();
      await startAt(c, [song(1), song(2)], 0);
      setMode(c, LoopMode.one);
      final before = fake.playedUrls.length;

      fake.fireCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(c.read(playerControllerProvider).currentIndex, 0,
          reason: '自动播完必须重播当前曲');
      expect(fake.playedUrls.length, greaterThan(before),
          reason: '应真的重新起播一次');
    });
  });

  group('列表循环:手动切歌', () {
    test('最后一首点「下一首」回到第一首', () async {
      final (c, _) = await setup();
      final ctrl = await startAt(c, [song(1), song(2), song(3)], 2);
      setMode(c, LoopMode.all);

      await ctrl.next();

      expect(c.read(playerControllerProvider).currentIndex, 0);
    });

    test('第一首点「上一首」到最后一首', () async {
      final (c, _) = await setup();
      final ctrl = await startAt(c, [song(1), song(2), song(3)], 0);
      setMode(c, LoopMode.all);

      await ctrl.previous();

      expect(c.read(playerControllerProvider).currentIndex, 2);
    });
  });

  group('顺序播放(off):手动切歌', () {
    test('最后一首点「下一首」停在原处(不越界)', () async {
      final (c, _) = await setup();
      final ctrl = await startAt(c, [song(1), song(2)], 1);
      setMode(c, LoopMode.off);

      await ctrl.next();

      expect(c.read(playerControllerProvider).currentIndex, 1);
    });

    test('第一首点「上一首」停在原处', () async {
      final (c, _) = await setup();
      final ctrl = await startAt(c, [song(1), song(2)], 0);
      setMode(c, LoopMode.off);

      await ctrl.previous();

      expect(c.read(playerControllerProvider).currentIndex, 0);
    });
  });

  group('模式切换顺序', () {
    test('off → all → one → off 循环', () async {
      final (c, _) = await setup();
      final ctrl = await startAt(c, [song(1)], 0);
      setMode(c, LoopMode.off);

      ctrl.toggleRepeat();
      expect(c.read(playerControllerProvider).repeatMode, LoopMode.all);
      ctrl.toggleRepeat();
      expect(c.read(playerControllerProvider).repeatMode, LoopMode.one);
      ctrl.toggleRepeat();
      expect(c.read(playerControllerProvider).repeatMode, LoopMode.off);
    });
  });
}
