// test/e2e_bundled_qq_test.dart
//
// 回归:内置的「腾讯音乐」插件返回的 duration 是**秒**(如 269),
// 宿主按毫秒处理时会被搜索页的「过滤 60 秒以下试听片段」逻辑全部丢掉,
// 表现为该音源「搜不到歌」。本用例锁死:归一化后必须能通过过滤。
//
// 默认跳过:它**打真实上游接口**,结果受腾讯侧限流/风控与 runner 出口 IP 影响。
// 实测(2026-10-08)同一提交在 CI 上时通时不通:main 的 CI 连续失败两次,
// std-v1.7.57 的 Release 首次构建也因它失败(重跑才过)—— 实时联网用例不该
// 卡在发版路径上。与 e2e_update_download_test 同一约定,显式开启才真跑:
//   flutter test test/e2e_bundled_qq_test.dart --dart-define=RUN_NET_E2E=1
//   (或 RUN_NET_E2E=1 flutter test test/e2e_bundled_qq_test.dart)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/models/music_item.dart';

/// 是否执行真实网络请求(约定同 e2e_update_download_test)。
final _runNetE2E = Platform.environment['RUN_NET_E2E'] == '1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late PluginManager manager;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_qq_e2e');
    manager = PluginManager(tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('e2e: 内置腾讯音乐搜索结果能通过 60 秒过滤(时长量纲已归一)', () async {
    if (!_runNetE2E) {
      // ignore: avoid_print
      print('SKIP: 未开启网络 E2E(用 RUN_NET_E2E=1 flutter test ...)');
      return;
    }
    final catalog = BundledPluginCatalog();
    final bundled = await catalog.list();
    final qq = bundled.firstWhere((p) => p.platform == '腾讯音乐');
    await manager.installBundledJs(
      await catalog.readJs(qq),
      source: 'bundled:${qq.assetPath}',
    );

    final raw = await manager.search(
      '晴天',
      platform: '腾讯音乐',
      page: 1,
      timeout: const Duration(seconds: 25),
    );
    final data = (raw['data'] as List).cast<Map<String, dynamic>>();
    expect(data, isNotEmpty, reason: '腾讯音乐应能搜到结果');
    expect((data.first['duration'] as num).toDouble(), greaterThan(60000),
        reason: 'duration 应被归一化为毫秒');

    // 与搜索页完全相同的过滤条件
    final kept = data
        .map(MusicItem.fromJson)
        .where((m) {
          final d = m.duration;
          if (d == null || d <= 0) return true;
          return d >= 60 * 1000;
        })
        .toList();
    expect(kept, isNotEmpty, reason: '过滤后不能为空,否则用户看到「搜不到歌曲」');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
