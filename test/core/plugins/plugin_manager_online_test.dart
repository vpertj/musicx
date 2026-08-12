import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
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
    { "name": "alpha", "url": "URL_PLACEHOLDER_alpha", "version": "0.1.0" },
    { "name": "beta", "url": "URL_PLACEHOLDER_beta", "version": "2.0.0" },
    { "name": "", "url": "URL_PLACEHOLDER_bad", "version": "0.0.0" }
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late Directory tmp;

  setUpAll(() async {
    // flutter_test 的 binding 会 mock 主 isolate 的 HttpClient(全部返回 400),
    // 这里重置为真实网络以测试在线下载。
    HttpOverrides.global = null;
    tmp = Directory.systemTemp.createTempSync('musicx_online');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/plugin.js') {
        request.response.headers.contentType = ContentType('application', 'javascript');
        request.response.write(_pluginJs);
      } else if (path == '/plugins.json') {
        request.response.headers.contentType = ContentType.json;
        final urlBase = 'http://127.0.0.1:${server.port}';
        request.response.write(_pluginsJson
            .replaceAll('URL_PLACEHOLDER_alpha', '$urlBase/plugin.js')
            .replaceAll('URL_PLACEHOLDER_beta', '$urlBase/plugin.js'));
      } else if (path == '/bad.js') {
        request.response.write('this is not a plugin');
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  test('installFromUrl downloads and installs a valid plugin', () async {
    final manager = PluginManager(tmp);
    final info = await manager.installFromUrl('http://127.0.0.1:${server.port}/plugin.js');

    expect(info.platform, 'online-test');
    expect(info.version, '1.2.3');

    final plugins = await manager.listPlugins();
    expect(plugins.any((p) => p.platform == 'online-test'), isTrue);
  });

  test('installFromUrl rejects non-plugin content', () async {
    final manager = PluginManager(tmp);
    expect(
      () => manager.installFromUrl('http://127.0.0.1:${server.port}/bad.js'),
      throwsA(anything),
    );
  });

  test('installFromUrl rejects invalid URLs', () async {
    final manager = PluginManager(tmp);
    expect(() => manager.installFromUrl('not a url'), throwsArgumentError);
    expect(() => manager.installFromUrl('file:///etc/passwd'), throwsArgumentError);
  });

  test('fetchPluginSources parses plugins.json and filters bad entries', () async {
    final manager = PluginManager(tmp);
    final sources =
        await manager.fetchPluginSources('http://127.0.0.1:${server.port}/plugins.json');

    expect(sources.length, 2);
    expect(sources[0].name, 'alpha');
    expect(sources[0].version, '0.1.0');
    expect(sources[1].name, 'beta');
  });

  test('isInstalled reflects installed plugins', () async {
    final manager = PluginManager(tmp);
    await manager.installFromUrl('http://127.0.0.1:${server.port}/plugin.js');
    expect(await manager.isInstalled('online-test'), isTrue);
    expect(await manager.isInstalled('ghost'), isFalse);
  });
}
