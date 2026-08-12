import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

/// 网易云音源插件验证:搜索(过滤 VIP) → 播放地址解析(完整歌曲)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('e2e: netease filters VIP and resolves full-song URL', () async {
    final tmp = Directory.systemTemp.createTempSync('musicx_ncm');
    addTearDown(() => tmp.deleteSync(recursive: true));

    File('${tmp.path}/netease.js')
        .writeAsStringSync(File('example/plugins/netease.js').readAsStringSync());

    final manager = PluginManager(tmp);
    final result = await manager.search('周杰伦', platform: 'netease',
        timeout: const Duration(seconds: 20));
    final data = (result['data'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    expect(data, isNotEmpty, reason: '网易云搜索应有结果');
    print('NCM 过滤后 ${data.length} 首,第一首: ${data.first['title']}');

    // 过滤后应能解析出可播放歌曲(遍历前 8 首验证)
    final client = HttpClient();
    var found = false;
    try {
      for (final song in data.take(8)) {
        final media = await manager.resolveMediaSource(song);
        final url = media['url'] as String;
        if (url.contains('/404')) {
          print('NCM ${song['title']}: 仍不可播(404),跳过');
          continue;
        }
        expect(url, startsWith('https://'));
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set('Range', 'bytes=0-4095');
        req.headers.set('user-agent', 'Mozilla/5.0');
        req.headers.set('referer', 'https://music.163.com/');
        final resp = await req.close();
        final body = await resp.fold<List<int>>([], (a, b) => a..addAll(b));
        final type = resp.headers.contentType?.mimeType ?? '';
        print('NCM ${song['title']}: HTTP ${resp.statusCode} type=$type');
        if (type.contains('audio') && body.length > 1000) {
          found = true;
          break;
        }
      }
    } finally {
      client.close(force: true);
    }
    expect(found, isTrue, reason: '过滤 VIP 后应能播放到完整歌曲');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
