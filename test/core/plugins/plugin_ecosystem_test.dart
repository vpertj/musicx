import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

/// MusicFree 生态兼容性测试(不依赖真实网络,稳定):
/// 模拟官方插件风格 —— 顶层 require("axios")、位置参数 search(keyword,page,type)、
/// 结果不含 platform/songId(宿主补全)。验证 require 白名单 + 调用协议 + 补全逻辑。
const _ecosimPlugin = '''
module.exports = {
  platform: "ecosim",
  version: "1.0.0",
  srcUrl: "",
  search: function (keyword, page, type) {
    return new Promise(function (resolve) {
      var axios = require("axios");
      var axiosType = typeof axios;
      var dayjsType = typeof require("dayjs");
      resolve({
        isEnd: true,
        data: [
          {
            id: "e1",
            title: "生态模拟曲:" + keyword + ":" + page + ":" + type,
            artist: "测试歌手",
            album: "测试专辑",
            duration: 180000
          }
        ]
      });
    });
  },
  getMediaSource: function (musicItem) {
    return { url: "https://example.com/audio/" + musicItem.id + ".mp3" };
  }
};
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_eco');
    File('${tmp.path}/ecosim.js').writeAsStringSync(_ecosimPlugin);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('位置参数 + require 白名单 + 宿主补全', () async {
    final manager = PluginManager(tmp);

    // 列表解析(parseMeta 应解析出正确 platform)
    final plugins = await manager.listPlugins();
    expect(plugins.single.platform, 'ecosim');
    expect(plugins.single.version, '1.0.0');

    // 位置参数 search(keyword, page, type) + 运行时 require("axios")
    final result = await manager.search('测试词');
    final data = (result['data'] as List).cast<Map<String, dynamic>>();
    expect(data, isNotEmpty);
    expect(data.first['title'], '生态模拟曲:测试词:1:music');

    // 宿主补全 platform / songId
    expect(data.first['platform'], 'ecosim');
    expect(data.first['songId'], 'e1');

    // getMediaSource 位置参数
    final media = await manager.resolveMediaSource(data.first);
    expect(media['url'], 'https://example.com/audio/e1.mp3');
  });

  test('parseMeta 忽略源码中非 exports 的 platform 字段', () async {
    // 模拟 bilibili 场景:源码内部有 platform: "pc" 参数,exports 才是真值
    final source = '''
const headers = { platform: "pc", version: "1" };
module.exports = { platform: "real", version: "0.3.0" };
''';
    final f = File('${tmp.path}/tricky.js');
    f.writeAsStringSync(source);
    final plugins = await PluginManager(tmp).listPlugins();
    final p = plugins.firstWhere((p) => p.path == f.path);
    expect(p.platform, 'real');
    expect(p.version, '0.3.0');
  });
}
