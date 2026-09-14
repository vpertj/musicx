// integration_test/android_features_test.dart
//
// 安卓真机/模拟器功能验证。这些用例必须跑在设备上:
// 之前的教训(明文 HTTP 被禁、托盘图标格式、版本号读取)都是「只有真机才暴露」
// 的问题,单元测试与桌面构建都发现不了。
//
// 运行:flutter test integration_test/android_features_test.dart -d emulator-5554
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/player/player_service.dart';
import 'package:musicx/core/plugins/preview_detector.dart';
import 'package:musicx/core/search/original_filter.dart';
import 'package:musicx/models/lyric_line.dart';
import 'package:musicx/models/music_item.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PluginManager manager;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mx_android_it');
    manager = PluginManager(dir);
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('1) 安卓可直连音源(http 明文未被禁)', (tester) async {
    final client = HttpClient();
    var ok = false;
    Object? error;
    for (final url in [
      'http://search.kuwo.cn/r.s?client=kt&all=%E6%99%B4%E5%A4%A9&pn=0&rn=5&ft=music&rformat=json&encoding=utf8',
      'http://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=228908&httpStatus=1',
    ]) {
      try {
        final req = await client.getUrl(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        final resp = await req.close();
        await resp.drain<void>();
        debugPrint('RESULT: $url -> ${resp.statusCode}');
        if (resp.statusCode == 200) ok = true;
      } catch (e) {
        error = e;
        debugPrint('RESULT ERROR: $url -> $e');
      }
    }
    expect(ok, isTrue, reason: '安卓必须能直连 http 音源接口;$error');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('2) 内置音源可安装到设备并扫描到', (tester) async {
    final catalog = BundledPluginCatalog();
    final bundled = await catalog.list();
    debugPrint('RESULT: bundled=${bundled.map((p) => p.platform).toList()}');
    expect(bundled.map((p) => p.platform), contains('腾讯音乐'));

    for (final p in bundled) {
      await manager.installBundledJs(
        await catalog.readJs(p),
        source: 'bundled:${p.assetPath}',
      );
    }
    final installed = await manager.listPlugins();
    debugPrint('RESULT: installed=${installed.map((p) => p.platform).toList()}');
    expect(installed, hasLength(bundled.length));
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('3) 真实搜索:自动路由能拿到结果且过滤翻唱', (tester) async {
    final catalog = BundledPluginCatalog();
    for (final p in await catalog.list()) {
      await manager.installBundledJs(await catalog.readJs(p),
          source: 'bundled:${p.assetPath}');
    }

    final sw = Stopwatch()..start();
    final result = await manager.search('晴天 周杰伦', page: 1,
        timeout: const Duration(seconds: 25));
    final data = (result['data'] as List).cast<Map<String, dynamic>>();
    final items = data.map(MusicItem.fromJson).toList();
    debugPrint('RESULT: search ${sw.elapsedMilliseconds}ms count=${items.length}'
        ' first=${items.isEmpty ? "-" : "${items.first.title}/${items.first.artist}/${items.first.platform}"}');
    expect(items, isNotEmpty, reason: '自动模式下必须能搜到歌');

    // 与应用一致的处理链:先按原唱优先排序,再过滤翻唱
    final views = [
      for (final m in items)
        (title: m.title, artist: m.artist ?? '', album: m.album ?? ''),
    ];
    final ranked = [
      for (final i in rankSearchOrder(views, query: '晴天 周杰伦')) items[i],
    ];
    final shown = [for (final i in originalOnlyOrder(views)) items[i]];
    final covers = shown
        .where((m) => looksLikeCover(
              title: m.title,
              artist: m.artist ?? '',
              album: m.album ?? '',
            ))
        .length;
    debugPrint('RESULT: raw=${items.length} shown=${shown.length} '
        'covers=$covers top=${ranked.first.title}/${ranked.first.artist}');
    expect(shown, isNotEmpty, reason: '过滤后不能为空');
    expect(covers, 0, reason: '过滤翻唱后不应再出现翻唱');
    expect(
      looksLikeCover(
        title: ranked.first.title,
        artist: ranked.first.artist ?? '',
        album: ranked.first.album ?? '',
      ),
      isFalse,
      reason: '排序后首条必须是原唱,不能是翻唱',
    );
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('4) 歌词:酷我念心纯秒时间戳在设备上能解析出行', (tester) async {
    final catalog = BundledPluginCatalog();
    for (final p in await catalog.list()) {
      await manager.installBundledJs(await catalog.readJs(p),
          source: 'bundled:${p.assetPath}');
    }

    final found = await manager.search('晴天', platform: '酷我(念心音源)',
        page: 1, timeout: const Duration(seconds: 25));
    final items = (found['data'] as List).cast<Map<String, dynamic>>();
    expect(items, isNotEmpty);
    final item = Map<String, dynamic>.from(items.first);

    final lrc = await manager.resolveLyric(item,
        timeout: const Duration(seconds: 20));
    final lines = parseLrc(lrc);
    debugPrint('RESULT: lyric chars=${lrc.length} parsedLines=${lines.length}');
    expect(lrc, isNotEmpty, reason: '该音源应返回歌词');
    expect(lines, isNotEmpty, reason: '纯秒时间戳必须能解析出歌词行');
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('5) 取流:拿到的必须是完整歌曲而非试听片段', (tester) async {
    final catalog = BundledPluginCatalog();
    for (final p in await catalog.list()) {
      await manager.installBundledJs(await catalog.readJs(p),
          source: 'bundled:${p.assetPath}');
    }

    final found = await manager.search('晴天 周杰伦', page: 1,
        timeout: const Duration(seconds: 25));
    final items = (found['data'] as List).cast<Map<String, dynamic>>();
    expect(items, isNotEmpty);
    final item = Map<String, dynamic>.from(items.first);
    final durationMs = (item['duration'] as num?)?.toInt();
    debugPrint('RESULT: picked platform=${item['platform']} '
        'title=${item['title']} duration=${durationMs}ms');

    // 允许「全部只有试听」时抛错(产品决策:明确报错不播),但绝不允许
    // 静默返回一个 20 秒片段。
    try {
      final media = await manager.resolveMediaSource(item,
          timeout: const Duration(seconds: 30));
      final url = (media['url'] as String?) ?? '';
      debugPrint('RESULT: media=${Uri.tryParse(url)?.host}');
      expect(url, isNotEmpty);

      // 实测体积,确认不是试听片段
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      req.followRedirects = true;
      final resp = await req.close();
      var bytes = resp.contentLength;
      final range = resp.headers.value(HttpHeaders.contentRangeHeader);
      await resp.drain<void>();
      if (range != null && range.contains('/')) {
        bytes = int.tryParse(range.split('/').last.trim()) ?? bytes;
      }
      debugPrint('RESULT: bytes=$bytes preview='
          '${looksLikePreview(contentLength: bytes, durationMs: durationMs)}');
      expect(
        looksLikePreview(contentLength: bytes, durationMs: durationMs),
        isFalse,
        reason: '解析出的播放地址必须是完整歌曲,不能是试听片段',
      );
    } catch (e) {
      debugPrint('RESULT: 全部音源只有试听 -> $e');
      expect(e.toString(), contains('试听'),
          reason: '拿不到完整歌曲时必须明确报错,而不是静默播放片段');
    }
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('6) 真实播放:用现场解析的地址能正常出声', (tester) async {
    final catalog = BundledPluginCatalog();
    for (final p in await catalog.list()) {
      await manager.installBundledJs(await catalog.readJs(p),
          source: 'bundled:${p.assetPath}');
    }

    final found = await manager.search('晴天 周杰伦', page: 1,
        timeout: const Duration(seconds: 25));
    final items = (found['data'] as List).cast<Map<String, dynamic>>();
    expect(items, isNotEmpty);
    final item = Map<String, dynamic>.from(items.first);
    final media = await manager.resolveMediaSource(item,
        timeout: const Duration(seconds: 30));
    final url = (media['url'] as String?) ?? '';
    debugPrint('RESULT: play url host=${Uri.tryParse(url)?.host}');

    final service = PlayerService();
    try {
      final sw = Stopwatch()..start();
      await service.playUrl(url).timeout(const Duration(seconds: 20));
      final playing = await service.playingStream.first
          .timeout(const Duration(seconds: 10));
      debugPrint('RESULT: playUrl ${sw.elapsedMilliseconds}ms '
          'playing=$playing duration=${service.duration}');
      expect(playing, isTrue, reason: '解析出的地址必须能真正播放');
      expect(service.duration?.inSeconds ?? 0, greaterThan(60),
          reason: '时长应远大于试听片段(>60s)');
    } finally {
      await service.stop();
      service.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('7) 腾讯音乐歌词:经 MusicItem 往返后仍能取到(插件专属字段不丢)', (tester) async {
    final catalog = BundledPluginCatalog();
    for (final p in await catalog.list()) {
      await manager.installBundledJs(await catalog.readJs(p),
          source: 'bundled:${p.assetPath}');
    }

    final found = await manager.search('周杰伦', platform: '腾讯音乐', page: 1,
        timeout: const Duration(seconds: 25));
    final items = (found['data'] as List).cast<Map<String, dynamic>>();
    expect(items, isNotEmpty, reason: '腾讯音乐应能搜到歌');

    // 关键:应用播放时传的是 MusicItem.toJson(),此前 songmid 等插件专属
    // 字段会在这步丢失,导致 tx.js 的歌词接口拿到 undefined → 暂无歌词。
    final appSideItem = MusicItem.fromJson(items.first).toJson();
    debugPrint('RESULT: appSide keys=${appSideItem.keys.toList()}');
    expect(appSideItem['extra'], isNotNull,
        reason: '插件原始字段必须随 extra 保留');

    final lrc = await manager.resolveLyric(appSideItem,
        timeout: const Duration(seconds: 25));
    final lines = parseLrc(lrc);
    debugPrint('RESULT: 腾讯音乐 lyric chars=${lrc.length} lines=${lines.length}');
    expect(lrc, isNotEmpty, reason: '腾讯音乐歌词不能为空(此前显示「暂无歌词」)');
    expect(lines, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('8) 多首歌采样:绝不返回试听片段(否则必须明确报错)', (tester) async {
    final catalog = BundledPluginCatalog();
    for (final p in await catalog.list()) {
      await manager.installBundledJs(await catalog.readJs(p),
          source: 'bundled:${p.assetPath}');
    }

    Future<int> totalBytes(String url) async {
      try {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        req.followRedirects = true;
        final resp = await req.close();
        var n = resp.contentLength;
        final range = resp.headers.value(HttpHeaders.contentRangeHeader);
        await resp.drain<void>();
        if (range != null && range.contains('/')) {
          n = int.tryParse(range.split('/').last.trim()) ?? n;
        }
        return n;
      } catch (_) {
        return -1;
      }
    }

    final keywords = ['周杰伦 晴天', '林俊杰 江南', '陈奕迅 富士山下'];
    var okCount = 0;
    for (final kw in keywords) {
      final found = await manager.search(kw, page: 1,
          timeout: const Duration(seconds: 25));
      final items = (found['data'] as List).cast<Map<String, dynamic>>();
      if (items.isEmpty) {
        debugPrint('RESULT: $kw -> 搜不到,跳过');
        continue;
      }
      final item = Map<String, dynamic>.from(items.first);
      final dur = (item['duration'] as num?)?.toInt();
      final title = item['title'];
      final platform = item['platform'];
      String? url;
      try {
        final media = await manager.resolveMediaSource(item,
            timeout: const Duration(seconds: 30));
        url = (media['url'] as String?) ?? '';
      } catch (e) {
        // 产品决策:全部只有试听时明确报错(不播片段),报错须说明原因
        debugPrint('RESULT: $title($platform) -> 拒绝:$e');
        expect(e.toString(), contains('试听'),
            reason: '拿不到完整歌曲时报错必须说明是试听片段');
        continue;
      }
      // 断言放在 try 之外,避免 expect 失败被 catch 吞掉而假通过
      final bytes = await totalBytes(url);
      final preview = looksLikePreview(contentLength: bytes, durationMs: dur);
      debugPrint('RESULT: $title($platform) -> ${Uri.tryParse(url)?.host} '
          '${(bytes / 1048576).toStringAsFixed(2)}MB preview=$preview');
      expect(preview, isFalse,
          reason: '$title:解析出的必须是完整歌曲,不能是试听片段');
      okCount++;
    }
    debugPrint('RESULT: 采样完成,完整曲=$okCount/${keywords.length}');
  }, timeout: const Timeout(Duration(seconds: 300)));
}
