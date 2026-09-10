import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

/// 模拟一个「酷我(独家音源)」插件:getLyric 直接返回 LRC 文本。
/// 用于验证 resolveLyric 的同平台降级匹配(歌曲 platform=「酷我」)。
const _kuwoPlugin = '''
module.exports = { platform: "酷我(独家音源)", version: "1.0.0",
  search: function (q) { return Promise.resolve({ isEnd: true, data: [] }); },
  getMediaSource: function (m) { return Promise.resolve({ url: "" }); },
  getLyric: function (m) { return Promise.resolve({ rawLrc: "[00:01.00]测试歌词行" }); }
};
''';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('musicx_lyric'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('resolveLyric 同平台降级:酷我 匹配 酷我(独家音源)', () async {
    File('${tmp.path}/kuwo.js').writeAsStringSync(_kuwoPlugin);
    final manager = PluginManager(tmp);
    // 歌曲 platform 是「酷我」,插件名是「酷我(独家音源)」——修复前精确匹配
    // 会跳过该插件返回空;修复后应降级命中并取到歌词。
    final lrc = await manager.resolveLyric({
      'platform': '酷我',
      'title': '测试歌',
      'songId': '1',
      'id': '1',
    });
    expect(lrc, contains('测试歌词行'));
  });

  test('resolveLyric 不相关 platform 不误匹配(返回空)', () async {
    File('${tmp.path}/kuwo.js').writeAsStringSync(_kuwoPlugin);
    final manager = PluginManager(tmp);
    final lrc = await manager.resolveLyric({
      'platform': '网易云',
      'title': '测试歌',
      'songId': '1',
    });
    expect(lrc, isEmpty);
  });
}
