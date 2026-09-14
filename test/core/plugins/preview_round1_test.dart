import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

/// 第一轮精确匹配也必须做试听片段检测。
///
/// 背景:网易/腾讯对 VIP 歌在未登录时返回 20~45 秒试听,而此前的试听检测
/// 只在第二轮(同平台降级)和第三轮(跨源换源)执行,第一轮精确命中直接
/// 返回 —— 用户点开歌听到的仍是试听,甚至像网易 45 秒 m4a 一样卡在缓冲。
///
/// 试听判定走注入式探针(audioTotalBytesProbe):flutter_test 会把主
/// isolate 的 HttpClient 换成 400 桩,真实 socket 探测在单测里无法进行;
/// 探针注入也让本用例专注于验证「第一轮检测 + 降级」逻辑本身。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_preview_r1');
    File('${tmp.path}/a.js').writeAsStringSync('''
module.exports = { platform: "测试源", version: "1.0",
  getMediaSource: function () {
    return Promise.resolve({ url: "http://cdn.test/trial" });
  }
};
''');
    File('${tmp.path}/b.js').writeAsStringSync('''
module.exports = { platform: "测试源(完整版)", version: "1.0",
  getMediaSource: function () {
    return Promise.resolve({ url: "http://cdn.test/full" });
  }
};
''');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('第一轮返回试听片段时应降级到同平台完整版', () async {
    final manager = PluginManager(
      tmp,
      // 300KB≈19秒@128kbps,对 200 秒的歌远小于 expected*0.5 → 试听;
      // 4MB → 完整版。CDN 对 HEAD 探测也可能失败,故 url 规范化走异常兜底。
      audioTotalBytesProbe: (url) async => url.endsWith('/trial')
          ? 300000
          : url.endsWith('/full')
          ? 4000000
          : -1,
    );
    final media = await manager.resolveMediaSource({
      'platform': '测试源',
      'id': '1',
      'songId': '1',
      'title': '歌名',
      'artist': '歌手',
      'duration': 200000,
    });
    expect(media['url'], 'http://cdn.test/full');
  });
}
