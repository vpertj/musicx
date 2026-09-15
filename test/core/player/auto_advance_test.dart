// test/core/player/auto_advance_test.dart
//
// 用户反馈:列表播放时一首播完不会自动接着播下一首(循环模式)。
// 这里用可控的假播放服务直接验证「播完 → 自动下一首」的接线。
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
  void emitDuration(Duration d) => _duration.add(d);
  void emitPosition(Duration p) => _position.add(p);
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
    final tmp = Directory.systemTemp.createTempSync('mx_auto_advance');
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

  test('列表循环模式:一首播完自动播下一首', () async {
    final (c, fake) = await setup();
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2), song(3)], 0);
    while (c.read(playerControllerProvider).repeatMode != LoopMode.all) {
      ctrl.toggleRepeat();
    }
    expect(fake.playedUrls.length, 1);

    fake.fireCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(c.read(playerControllerProvider).currentIndex, 1,
        reason: '播完应自动切到下一首');
    expect(fake.playedUrls.length, 2, reason: '下一首应已开始播放');
  });

  test('列表循环:最后一首播完应回到第一首', () async {
    final (c, fake) = await setup();
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2)], 1);
    while (c.read(playerControllerProvider).repeatMode != LoopMode.all) {
      ctrl.toggleRepeat();
    }
    fake.fireCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.read(playerControllerProvider).currentIndex, 0,
        reason: '列表循环应从头继续');
  });

  test('单曲循环:播完重播同一首', () async {
    final (c, fake) = await setup();
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2)], 0);
    while (c.read(playerControllerProvider).repeatMode != LoopMode.one) {
      ctrl.toggleRepeat();
    }
    fake.fireCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.read(playerControllerProvider).currentIndex, 0);
    expect(fake.playedUrls.length, 2, reason: '单曲循环应重播');
  });

  test('顺序播放(off):最后一首播完停下,不越界', () async {
    final (c, fake) = await setup();
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2)], 1);
    expect(c.read(playerControllerProvider).repeatMode, LoopMode.off);
    fake.fireCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.read(playerControllerProvider).currentIndex, 1);
    expect(fake.playedUrls.length, 1, reason: '顺序播放到末尾应停止');
  });

  test('兜底:中转流不触发 completed 时,位置到达时长也要自动下一首', () async {
    final (c, fake) = await setup();
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2)], 0);
    while (c.read(playerControllerProvider).repeatMode != LoopMode.all) {
      ctrl.toggleRepeat();
    }
    // 模拟时长已知 + 位置走到末尾(但**不发** completed 事件)
    fake.emitDuration(const Duration(seconds: 200));
    fake.emitPosition(const Duration(seconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(c.read(playerControllerProvider).currentIndex, 1,
        reason: '位置到达时长应视为播完并切下一首(念心等中转流的兜底)');
  });

  test('兜底不会重复触发(位置继续更新也只切一次)', () async {
    final (c, fake) = await setup();
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2), song(3)], 0);
    fake.emitDuration(const Duration(seconds: 100));
    fake.emitPosition(const Duration(seconds: 100));
    fake.emitPosition(const Duration(seconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(c.read(playerControllerProvider).currentIndex, 1);
  });
}
