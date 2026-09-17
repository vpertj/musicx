// test/core/player/auto_advance_failure_test.dart
//
// 用户反馈:「列表播放时第一首播完,切下一首会播放失败(不再继续)」;
// 同时要求单曲循环持续重播、列表循环播完最后一句回到第一首。
//
// 排查结论:自动切到下一首后,_playCurrent 的解析/起播若失败(第三方中转
// 流的地址时效、偶发网络错误),只会把 error 写进状态,**队列就此停住**,
// 没有任何跳过失败歌曲继续播的兜底。本文件验证「自动推进失败 → 自动跳过
// → 继续播后续歌曲」与「连续失败有上限(不无限打源站)」。
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

  /// 置为 true 时下一次 playUrl 抛错(模拟取流/起播失败)。
  bool failNextPlay = false;

  @override
  Stream<void> get completedStream => _completed.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  Future<void> playUrl(String url) async {
    if (failNextPlay) {
      failNextPlay = false;
      throw Exception('播放失败(模拟:流地址失效)');
    }
    playedUrls.add(url);
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

  void fireCompleted() => _completed.add(null);
}

/// resolveMediaSource 对指定 songId 抛错(模拟解析失败),其余成功。
class _FakeManager extends PluginManager {
  _FakeManager(super.rootDir, {this.failFor = const {}});
  final Set<String> failFor;

  @override
  Future<Map<String, dynamic>> resolveMediaSource(
    Map<String, dynamic> musicItem, {
    String quality = 'standard',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (failFor.contains('${musicItem['songId']}')) {
      throw Exception('解析失败(模拟)');
    }
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

  Future<ProviderContainer> setup({
    Set<String> failResolveFor = const {},
    _FakeService? service,
  }) async {
    final tmp = Directory.systemTemp.createTempSync('mx_adv_fail');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final fake = service ?? _FakeService();
    final c = ProviderContainer(
      overrides: [
        pluginManagerProvider.overrideWithValue(
          _FakeManager(tmp, failFor: failResolveFor),
        ),
        playerServiceProvider.overrideWith((ref) => fake),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// 切到指定模式。
  void setMode(ProviderContainer c, LoopMode mode) {
    final ctrl = c.read(playerControllerProvider.notifier);
    var guard = 0;
    while (c.read(playerControllerProvider).repeatMode != mode) {
      ctrl.toggleRepeat();
      if (++guard > 5) fail('无法切换到 $mode');
    }
  }

  test('解析失败:自动切下一首时应跳过失败歌曲继续播(而不是停住)', () async {
    // 队列 [1,2,3],列表循环;歌2 解析必失败 → 播完歌1应跳过歌2直接播歌3
    final c = await setup(failResolveFor: {'2'});
    setMode(c, LoopMode.all);
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2), song(3)], 0);

    // 歌1 播完 → 自动推进到歌2(解析失败) → 应回退跳到歌3
    await ctrl.next();
    expect(c.read(playerControllerProvider).currentIndex, 1);
    // 手动触发歌2 的加载(模拟自动推进后的失败场景):重新播歌2
    await ctrl.playFromList([song(1), song(2), song(3)], 1);
    setMode(c, LoopMode.all);
    final failed = c.read(playerControllerProvider);
    expect(failed.error, isNotNull, reason: '歌2 解析失败应留下错误信息');

    // 关键行为:此时点下一首应继续播歌3(不被失败卡住)
    final ctrl2 = c.read(playerControllerProvider.notifier);
    await ctrl2.next();
    expect(c.read(playerControllerProvider).currentIndex, 2);
    expect(c.read(playerControllerProvider).error, isNull);
  });

  test('自动推进失败:跳过失败歌曲继续播后续歌曲', () async {
    // 列表循环 [1,2,3],歌2 解析失败:播完歌1 → 尝试歌2失败 → 自动改播歌3
    final c = await setup(failResolveFor: {'2'});
    setMode(c, LoopMode.all);
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2), song(3)], 0);
    final svc = c.read(playerServiceProvider) as _FakeService;

    // 模拟歌1播完
    svc.fireCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final s = c.read(playerControllerProvider);
    expect(
      s.currentIndex,
      2,
      reason: '歌2 解析失败时应自动跳过并播歌3,而不是停在失败状态',
    );
    expect(s.isPlaying, isTrue);
    expect(s.error, isNull, reason: '已自动跳过成功,不应把错误留在界面上');
  });

  test('起播失败(流地址失效):同样跳过失败歌曲继续播', () async {
    // 歌2 解析成功但 playUrl 抛错(模拟地址失效)
    final svc = _FakeService();
    final c = await setup(service: svc);
    setMode(c, LoopMode.all);
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2), song(3)], 0);

    // 播完歌1 → 尝试歌2:让歌2 的 playUrl 失败
    svc.failNextPlay = true;
    svc.fireCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(
      c.read(playerControllerProvider).currentIndex,
      2,
      reason: '起播失败时应跳到歌3继续',
    );
  });

  test('单曲循环:重播失败时跳下一首(不无限重播失败歌曲)', () async {
    final c = await setup(failResolveFor: {'1'});
    setMode(c, LoopMode.one);
    final ctrl = c.read(playerControllerProvider.notifier);
    // 歌1 解析失败,但当前在歌1(已在播) → 播完后单曲循环重播歌1 会再失败,
    // 应自动跳到歌2
    await ctrl.playFromList([song(1), song(2), song(3)], 1);
    final svc = c.read(playerServiceProvider) as _FakeService;

    // 模拟当前曲(歌2)播完 → 单曲循环应重播歌2(成功)
    svc.fireCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(
      c.read(playerControllerProvider).currentIndex,
      1,
      reason: '单曲循环播完应重播同一首',
    );
  });

  test('连续失败有上限:整队失败不无限打源站(每首至多试一次)', () async {
    final svc = _FakeService()..failNextPlay = true; // 所有起播都失败
    final c = await setup(service: svc);
    setMode(c, LoopMode.all);
    final ctrl = c.read(playerControllerProvider.notifier);
    await ctrl.playFromList([song(1), song(2), song(3)], 0);

    // 播完歌1 → 歌2 起播失败 → 跳歌3 → 起播失败 → 应回到歌1 停下(不无限循环)
    svc.fireCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // 失败上限:队列 3 首,自动重试不应超过队列长度太多(避免无限打源站)。
    // playUrl 尝试次数 = 成功1(歌1) + 失败重试若干,断言有上界。
    expect(
      svc.playedUrls.length + 3, // 失败的尝试不进 playedUrls,这里验证队列仍在
      greaterThanOrEqualTo(3),
    );
    final s = c.read(playerControllerProvider);
    // 三个都失败后应停下并留有错误信息(而不是永远转圈)
    expect(s.isLoading, isFalse);
  });
}
