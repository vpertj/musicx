// test/core/player/auto_advance_double_trigger_test.dart
//
// 用户反馈(安卓真机):「播放一首歌曲后不能继续播放列表里面的下一首,会停止播放」。
//
// 复现时的根因:自动推进有**两条触发路径**(位置兜底 / completed 事件),二者
// 没有互斥。位置兜底在「时长 - 900ms」就判定播完,而真实 completed 会在随后
// 900ms 内到达,此时解析下一首地址还在进行(实测 0.4~2s)。于是第二条路径会
// **并发**再推进一次,两个 _advanceAuto 互相作废对方的播放令牌(playToken 不匹配
// → 被当成「起播失败」),各自的「跳过失败歌曲」循环又继续往后跳 —— 级联切歌、
// 白打源站,队列最后停住(听感就是「一首播完就停了」)。
//
// 本文件锁定两条不变式:
//   1. 一次「播完」只推进一首(无论收到几条播完信号);
//   2. 一次推进只解析/起播它该播的那一首(不空转打源站)。
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

/// 取流有真实耗时(实测 0.4~2s);统计解析次数作为「是否空转打源站」的证据。
class _SlowManager extends PluginManager {
  _SlowManager(super.rootDir);
  int resolves = 0;

  @override
  Future<Map<String, dynamic>> resolveMediaSource(
    Map<String, dynamic> musicItem, {
    String quality = 'standard',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    resolves++;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return {'url': 'https://example.com/${musicItem['songId']}.mp3'};
  }

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

  Future<(ProviderContainer, _FakeService, _SlowManager)> setup() async {
    final tmp = Directory.systemTemp.createTempSync('mx_double_trigger');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final fake = _FakeService();
    final mgr = _SlowManager(tmp);
    final c = ProviderContainer(
      overrides: [
        pluginManagerProvider.overrideWithValue(mgr),
        playerServiceProvider.overrideWith((ref) => fake),
      ],
    );
    addTearDown(c.dispose);
    return (c, fake, mgr);
  }

  void setListLoop(ProviderContainer c) {
    final ctrl = c.read(playerControllerProvider.notifier);
    var guard = 0;
    while (c.read(playerControllerProvider).repeatMode != LoopMode.all) {
      ctrl.toggleRepeat();
      if (++guard > 5) fail('无法切到列表循环');
    }
  }

  test('位置兜底 + completed 双双触发:只推进一首,不级联、不停播', () async {
    final (c, fake, mgr) = await setup();
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2), song(3), song(4), song(5)], 0);
    setListLoop(c);
    // 歌1 起播:解析歌1 + 预取歌2 = 2 次
    expect(mgr.resolves, 2, reason: '歌1 起播应只解析歌1、预取歌2');

    // 歌1 时长 200s;位置到 199.5s → 位置兜底在真实播完前 900ms 触发
    fake.emitDuration(const Duration(seconds: 200));
    fake.emitPosition(const Duration(seconds: 199, milliseconds: 500));
    // 50ms 后真实播完事件到达 —— 此时歌2 的地址仍在解析中(400ms)
    await Future<void>.delayed(const Duration(milliseconds: 50));
    fake.fireCompleted();

    await Future<void>.delayed(const Duration(seconds: 2));

    final s = c.read(playerControllerProvider);
    expect(s.currentIndex, 1, reason: '只应前进一首,不能被并发推进带跑');
    expect(s.isPlaying, isTrue, reason: '自动切歌后应处于播放中');
    expect(
      fake.playedUrls.length,
      2,
      reason: '歌1 + 歌2 各起播一次;多于 2 说明并发推进在白打源站',
    );
    // 2 次起播 + 2 次预取 = 4;此前实测同一场景会打 9 次源站
    expect(mgr.resolves, lessThanOrEqualTo(4));
  });

  test('位置兜底先触发、completed 后到:不作废已起播的下一首', () async {
    final (c, fake, mgr) = await setup();
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2), song(3)], 0);
    setListLoop(c);

    fake.emitDuration(const Duration(seconds: 100));
    fake.emitPosition(const Duration(seconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    fake.fireCompleted();
    await Future<void>.delayed(const Duration(seconds: 2));

    final s = c.read(playerControllerProvider);
    expect(s.error, isNull, reason: '正常的自动切歌不应留下错误');
    expect(s.isPlaying, isTrue);
    expect(s.currentIndex, 1);
    expect(fake.playedUrls.length, 2);
  });

  test('本地(下载)列表连播:连续两次播完都要能继续下一首', () async {
    // 本地播放曾经不占播放序号(_playToken 不递增),所有本地播放共用一个
    // 序号:第一次播完被记为「已处理」,第二次播完就被当成重复信号丢掉 ——
    // 下载列表播完一首就停住(与用户反馈同形)。
    final (c, fake, _) = await setup();
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playLocal(
      song(1),
      '/downloads/a.mp3',
      songs: [song(1), song(2)],
      paths: ['/downloads/a.mp3', '/downloads/b.mp3'],
    );
    setListLoop(c);
    expect(fake.playedUrls, ['file:///downloads/a.mp3']);

    // 歌1 播完 → 应自动播歌2
    fake.fireCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.read(playerControllerProvider).currentIndex, 1);
    expect(fake.playedUrls, [
      'file:///downloads/a.mp3',
      'file:///downloads/b.mp3',
    ]);

    // 歌2 播完 → 列表循环应回到歌1(第二次播完同样必须能推进)
    fake.fireCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final s = c.read(playerControllerProvider);
    expect(s.currentIndex, 0, reason: '第二次播完也要能继续切歌,不能被去重吃掉');
    expect(s.isPlaying, isTrue);
    expect(fake.playedUrls.length, 3);
  });
}
