// test/e2e_bundled_qq_test.dart
//
// 回归:内置的「腾讯音乐」插件返回的 duration 是**秒**(如 269),
// 宿主按毫秒处理时会被搜索页的「过滤 60 秒以下试听片段」逻辑全部丢掉,
// 表现为该音源「搜不到歌」。本用例锁死:归一化后必须能通过过滤。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/models/music_item.dart';

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
