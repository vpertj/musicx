import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';

/// 用真实 JS 引擎加载收编后的 8 个 MusicFree 音源,验证:
///  1) Parcel 打包的 exports.default 能被 cjsShim 解包出 platform/version;
///  2) require 白名单(qs / big-integer / axios / crypto-js / he / dayjs / cheerio)
///     能让音源在加载阶段(不发网络请求)顺利完成定义。
/// 加载只执行 IIFE 顶层,不调用 search/getMediaSource,故无需联网。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plugins = {
    'bilibili.js': '哔哩哔哩',
    'kugou.js': '酷狗音乐',
    'kuwo.js': '酷我音乐',
    'migu.js': '咪咕音乐',
    'netease.js': '网易云音乐',
    'netease_fm.js': '网易云电台',
    'qqmusic.js': 'QQ音乐',
    'youtube.js': 'youtube',
  };

  const expectFuncs = {
    'netease.js': [
      'search', 'getMediaSource', 'getLyric', 'getMusicInfo',
      'getTopLists', 'importMusicSheet', 'getMusicSheetInfo',
    ],
    'bilibili.js': [
      'search', 'getMediaSource', 'getTopLists',
      'getArtistWorks', 'importMusicSheet', 'getMusicComments',
    ],
    'qqmusic.js': ['search', 'getMediaSource', 'getLyric', 'getTopLists'],
    'youtube.js': ['search', 'getMediaSource'],
  };

  for (final entry in plugins.entries) {
    test('收编音源可被引擎加载并解包: ${entry.key}', () {
      final source = File('assets/plugins/${entry.key}').readAsStringSync();
      final runtime = JsRuntimeFactory.createIsolateSafe();
      final loader = PluginLoader(runtime);
      final meta = loader.loadPlugin(source);
      expect(meta['platform'], entry.value,
          reason: '${entry.key} 应解包出 platform=${entry.value}');
      expect(meta['version'], isNotEmpty);
      final funcs = (meta['functions'] as List).cast<String>();
      expect(funcs, contains('search'));
      expect(funcs, contains('getMediaSource'));
      for (final f in (expectFuncs[entry.key] ?? const <String>[])) {
        expect(funcs, contains(f), reason: '${entry.key} 缺方法 $f');
      }
    });
  }
}
