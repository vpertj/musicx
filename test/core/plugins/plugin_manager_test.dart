import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

const _demoPlugin = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function (q) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({ isEnd: true, data: [ { id: "d1", title: "示例歌曲", artist: "歌手", album: "专辑",
          artwork: "", duration: 180000, platform: "demo", songId: "d1", extra: {} } ] });
      }, 10);
    });
  },
  getMediaSource: function (m) { return { url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3" }; }
};
''';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_pm');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('listPlugins scans installed plugins', () async {
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
    final manager = PluginManager(tmp);
    final plugins = await manager.listPlugins();
    expect(plugins, hasLength(1));
    expect(plugins.first.platform, 'demo');
  });

  test('installFromFile copies js into rootDir', () async {
    final src = File('${tmp.path}/../src_demo.js')
      ..writeAsStringSync(_demoPlugin);
    final manager = PluginManager(tmp);
    await manager.installFromFile(src.path);
    final plugins = await manager.listPlugins();
    expect(plugins, hasLength(1));
    expect(plugins.first.platform, 'demo');
  });

  test('search resolves song list through isolate', () async {
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
    final manager = PluginManager(tmp);
    final result = await manager.search('示例');
    final data = (result['data'] as List).cast<Map<String, dynamic>>();
    expect(data, isNotEmpty);
    expect(data.first['title'], '示例歌曲');
  });

  test('updatePlugin edits name and srcUrl in place', () async {
    final path = '${tmp.path}/demo.js';
    File(path).writeAsStringSync(_demoPlugin);
    final manager = PluginManager(tmp);
    final plugin = (await manager.listPlugins()).first;

    await manager.updatePlugin(
      plugin,
      name: '网易云',
      srcUrl: 'https://example.com/wy.js',
    );

    final updated = (await manager.listPlugins()).first;
    expect(updated.platform, '网易云');
    expect(updated.srcUrl, 'https://example.com/wy.js');
    // 插件本体仍可正常搜索(编辑仅改元数据字段)
    final result = await manager.search('示例');
    final data = (result['data'] as List).cast<Map<String, dynamic>>();
    expect(data.first['platform'], '网易云');
  });

  test('updatePlugin inserts srcUrl when missing', () async {
    const bare = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function (q) { return { isEnd: true, data: [] }; }
};
''';
    final path = '${tmp.path}/bare.js';
    File(path).writeAsStringSync(bare);
    final manager = PluginManager(tmp);
    final plugin = (await manager.listPlugins()).first;

    await manager.updatePlugin(
      plugin,
      name: plugin.platform,
      srcUrl: 'https://example.com/bare.js',
    );

    final updated = (await manager.listPlugins()).first;
    expect(updated.srcUrl, 'https://example.com/bare.js');
  });

  test('updatePlugin rejects empty name', () async {
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
    final manager = PluginManager(tmp);
    final plugin = (await manager.listPlugins()).first;
    await expectLater(
      manager.updatePlugin(plugin, name: '   ', srcUrl: plugin.srcUrl ?? ''),
      throwsArgumentError,
    );
  });
}
