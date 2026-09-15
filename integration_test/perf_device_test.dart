// integration_test/perf_device_test.dart
//
// 真机性能实测:①切歌速度(冷/热) ②渲染流畅度(FrameTiming)。
// 运行:flutter test integration_test/perf_device_test.dart -d <device>
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/models/music_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('切歌速度 + 渲染流畅度', (tester) async {
    final container = ProviderContainer();
    final manager = container.read(pluginManagerProvider);
    final catalog = BundledPluginCatalog();
    for (final p in await catalog.list()) {
      await manager.installBundledJs(await catalog.readJs(p),
          source: 'bundled:${p.assetPath}');
    }

    final r = await manager.search('周杰伦 晴天', page: 1,
        timeout: const Duration(seconds: 25));
    final items = ((r['data'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(MusicItem.fromJson)
        .take(4)
        .toList();
    debugPrint('PERF|搜索结果 ${items.length} 首');
    expect(items, isNotEmpty);

    // ① 冷启动切歌(媒体解析 + 起播),逐首测量
    final ctrl = container.read(playerControllerProvider.notifier);
    final cold = <int>[];
    for (var i = 0; i < items.length; i++) {
      final sw = Stopwatch()..start();
      await ctrl.playFromList(items, i);
      cold.add(sw.elapsedMilliseconds);
      debugPrint('PERF|切歌#${i + 1}(冷) ${cold.last}ms '
          '(${items[i].title}/${items[i].artist})');
    }

    // ② 热切换(命中媒体缓存):切回第 1 首
    final sw2 = Stopwatch()..start();
    await ctrl.playFromList(items, 0);
    debugPrint('PERF|切回#1(热/缓存) ${sw2.elapsedMilliseconds}ms');

    // ③ 直接测媒体解析:同一首第二次应命中缓存
    final sw3 = Stopwatch()..start();
    await manager.resolveMediaSource(items[1].toJson());
    debugPrint('PERF|媒体解析(热) ${sw3.elapsedMilliseconds}ms');

    // ④ 渲染流畅度:滚动首页/列表并收集帧耗时
    final timings = <FrameTiming>[];
    void cb(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(cb);
    for (var i = 0; i < 6; i++) {
      // 在窗口坐标系里做一次滑动(不依赖具体 widget 类型)
      await tester.dragFrom(const Offset(200, 700), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 90));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    SchedulerBinding.instance.removeTimingsCallback(cb);

    if (timings.isNotEmpty) {
      final builds = timings.map((t) => t.buildDuration.inMicroseconds / 1000).toList()..sort();
      final rasters = timings.map((t) => t.rasterDuration.inMicroseconds / 1000).toList()..sort();
      final janky = timings.where((t) => t.totalSpan.inMilliseconds > 17).length;
      debugPrint('PERF|帧数=${timings.length} '
          'build p50=${builds[builds.length ~/ 2].toStringAsFixed(1)}ms '
          'p90=${builds[(builds.length * 9) ~/ 10].toStringAsFixed(1)}ms '
          'raster p50=${rasters[rasters.length ~/ 2].toStringAsFixed(1)}ms '
          'p90=${rasters[(rasters.length * 9) ~/ 10].toStringAsFixed(1)}ms '
          '掉帧=$janky/${timings.length}');
    } else {
      debugPrint('PERF|未采集到帧数据');
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
