// test/core/plugins/bundled_plugins_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';

const _manifest = '''
{
  "plugins": [
    {
      "name": "网易云音乐",
      "platform": "netease",
      "version": "2025.09.14",
      "asset": "assets/plugins/netease.js",
      "author": "Thomas喲",
      "sourceUrl": "https://example.com/wy.js"
    },
    {
      "name": "酷我音乐",
      "platform": "kuwo",
      "version": "0.1.0",
      "asset": "assets/plugins/kuwo.js"
    },
    { "name": "缺少 asset 的条目" },
    { "asset": "assets/plugins/no_name.js" }
  ]
}
''';

void main() {
  test('解析清单:保留合法条目,跳过缺字段的条目', () {
    final list = parseBundledPlugins(_manifest);
    expect(list, hasLength(2));
    expect(list.first.name, '网易云音乐');
    expect(list.first.platform, 'netease');
    expect(list.first.version, '2025.09.14');
    expect(list.first.assetPath, 'assets/plugins/netease.js');
    expect(list.first.author, 'Thomas喲');
    expect(list.last.platform, 'kuwo');
    expect(list.last.author, ''); // 缺省为空
  });

  test('清单不是 JSON 对象时抛 FormatException', () {
    expect(() => parseBundledPlugins('not json'), throwsFormatException);
    expect(() => parseBundledPlugins('[]'), throwsFormatException);
  });

  test('清单缺少 plugins 数组时返回空列表', () {
    expect(parseBundledPlugins('{"other": 1}'), isEmpty);
  });

  test('安装状态:未装/已装/版本不同', () {
    expect(
      bundledInstallState(bundledVersion: '1.0.0', installedVersion: null),
      BundledInstallState.notInstalled,
    );
    expect(
      bundledInstallState(bundledVersion: '1.0.0', installedVersion: '1.0.0'),
      BundledInstallState.installed,
    );
    expect(
      bundledInstallState(bundledVersion: '1.0.0', installedVersion: '0.9.0'),
      BundledInstallState.updatable,
    );
  });

  test('目录:经注入的 loader 读清单与插件正文,不碰真实 asset', () async {
    final files = <String, String>{
      BundledPluginCatalog.manifestAsset: _manifest,
      'assets/plugins/netease.js': 'module.exports = { platform: "netease", version: "2025.09.14" };',
    };
    final catalog = BundledPluginCatalog(loadAsset: (k) async => files[k]!);

    final list = await catalog.list();
    expect(list, hasLength(2));
    final js = await catalog.readJs(list.first);
    expect(js, contains('platform: "netease"'));
  });
}
