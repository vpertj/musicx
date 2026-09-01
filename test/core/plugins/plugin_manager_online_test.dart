import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

const _pluginJs = '''
module.exports = {
  platform: "online-test",
  version: "1.2.3",
  srcUrl: "",
  search: function () { return Promise.resolve({ isEnd: true, data: [] }); },
  getMediaSource: function () { return { url: "" }; }
};
''';

const _pluginsJson = '''
{
  "desc": "测试订阅源",
  "plugins": [
    { "name": "alpha", "url": "https://example.com/alpha.js", "version": "0.1.0" },
    { "name": "beta", "url": "https://example.com/beta.js", "version": "2.0.0" },
    { "name": "", "url": "https://example.com/bad.js", "version": "0.0.0" }
  ]
}
''';

/// 构造一个返回固定内容的 MockClient(模拟 https 下载)。
MockClient _mockClient() => MockClient((req) async {
  final path = req.url.path;
  if (path == '/plugin.js') {
    return http.Response.bytes(utf8.encode(_pluginJs), 200);
  }
  if (path == '/plugins.json') {
    return http.Response.bytes(utf8.encode(_pluginsJson), 200);
  }
  if (path == '/bad.js') {
    return http.Response.bytes(utf8.encode('this is not a plugin'), 200);
  }
  return http.Response('not found', 404);
});

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_online');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('installFromUrl downloads and installs a valid plugin over https',
      () async {
    final manager = PluginManager(tmp, client: _mockClient());
    final info = await manager.installFromUrl('https://example.com/plugin.js');

    expect(info.platform, 'online-test');
    expect(info.version, '1.2.3');

    final plugins = await manager.listPlugins();
    expect(plugins.any((p) => p.platform == 'online-test'), isTrue);
  });

  test('installFromUrl rejects non-plugin content', () async {
    final manager = PluginManager(tmp, client: _mockClient());
    expect(
      () => manager.installFromUrl('https://example.com/bad.js'),
      throwsA(anything),
    );
  });

  test('installFromUrl rejects invalid URLs', () async {
    final manager = PluginManager(tmp, client: _mockClient());
    expect(() => manager.installFromUrl('not a url'), throwsArgumentError);
    expect(
      () => manager.installFromUrl('file:///etc/passwd'),
      throwsArgumentError,
    );
  });

  test('installFromUrl rejects plaintext http (security)', () async {
    final manager = PluginManager(tmp, client: _mockClient());
    expect(
      () => manager.installFromUrl('http://example.com/plugin.js'),
      throwsArgumentError,
    );
  });

  test('fetchPluginSources rejects plaintext http (security)', () async {
    final manager = PluginManager(tmp, client: _mockClient());
    expect(
      () => manager.fetchPluginSources('http://example.com/plugins.json'),
      throwsArgumentError,
    );
  });

  test(
    'fetchPluginSources parses plugins.json and filters bad entries',
    () async {
      final manager = PluginManager(tmp, client: _mockClient());
      final sources = await manager.fetchPluginSources(
        'https://example.com/plugins.json',
      );

      expect(sources.length, 2);
      expect(sources[0].name, 'alpha');
      expect(sources[0].version, '0.1.0');
      expect(sources[1].name, 'beta');
    },
  );

  test('isInstalled reflects installed plugins', () async {
    final manager = PluginManager(tmp, client: _mockClient());
    await manager.installFromUrl('https://example.com/plugin.js');
    expect(await manager.isInstalled('online-test'), isTrue);
    expect(await manager.isInstalled('ghost'), isFalse);
  });
}
