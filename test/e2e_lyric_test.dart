/// 歌词链路验证:网易云插件 getLyric 返回 rawLrc → Dart 解析出带时间戳行。
/// 依赖安全 XHR 桥(xhr_safe.dart):flutter_js 自带桥会把响应 JSON 里的
/// \n 转义破坏,导致 lrc.lyric 无法解析,本用例回归该问题。
@Tags(['network'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/models/lyric_line.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'e2e: netease getLyric returns timestamped lines',
    () async {
      final tmp = Directory.systemTemp.createTempSync('musicx_lyric');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File('${tmp.path}/netease.js').writeAsStringSync(
        File('example/plugins/netease.js').readAsStringSync(),
      );

      final manager = PluginManager(tmp);
      final result = await manager.search(
        '周杰伦',
        platform: 'netease',
        timeout: const Duration(seconds: 20),
      );
      final data = (result['data'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      expect(data, isNotEmpty, reason: '网易云搜索应有结果');

      var gotLines = false;
      for (final song in data.take(6)) {
        final lrc = await manager.resolveLyric(song);
        final lines = parseLrc(lrc);
        if (lines.isNotEmpty) {
          expect(lines.first.text, isNotEmpty);
          gotLines = true;
          break;
        }
      }
      expect(gotLines, isTrue, reason: '网易云应能解析到带时间戳的歌词');
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
