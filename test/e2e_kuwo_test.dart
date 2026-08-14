/// 酷我音源插件验证:搜索 → 播放地址解析(https 完整歌曲)。
@Tags(['network'])
library;

// e2e 诊断输出使用 print,属预期行为
// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'e2e: kuwo plugin searches and resolves full-song URL',
    () async {
      final tmp = Directory.systemTemp.createTempSync('musicx_kuwo');
      addTearDown(() => tmp.deleteSync(recursive: true));

      File(
        '${tmp.path}/kuwo.js',
      ).writeAsStringSync(File('example/plugins/kuwo.js').readAsStringSync());

      final manager = PluginManager(tmp);
      final result = await manager.search(
        '周杰伦',
        platform: 'kuwo',
        timeout: const Duration(seconds: 20),
      );
      final data = (result['data'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      expect(data, isNotEmpty, reason: '酷我搜索应有结果');
      print('KUWO 搜索到 ${data.length} 首,第一首: ${data.first['title']}');

      // 遍历前 5 首解析播放地址并验证可访问
      final client = HttpClient();
      var found = false;
      try {
        for (final song in data.take(5)) {
          final media = await manager.resolveMediaSource(song);
          final url = media['url'] as String;
          if (url.isEmpty) {
            print('KUWO ${song['title']}: 无可播地址,跳过');
            continue;
          }
          print('KUWO ${song['title']}: $url');
          expect(url, startsWith('https://'), reason: '酷我播放地址应为 https');

          final req = await client.getUrl(Uri.parse(url));
          req.headers.set('Range', 'bytes=0-4095');
          final resp = await req.close();
          final body = await resp.fold<List<int>>([], (a, b) => a..addAll(b));
          final type = resp.headers.contentType?.mimeType ?? '';
          print('KUWO ${song['title']}: HTTP ${resp.statusCode} type=$type');
          if (type.contains('audio') && body.length > 1000) {
            found = true;
            break;
          }
        }
      } finally {
        client.close(force: true);
      }
      expect(found, isTrue, reason: '酷我搜索结果的歌曲应至少有一首可完整播放');
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
