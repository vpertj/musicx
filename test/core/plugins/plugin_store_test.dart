import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_store.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_test');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('scanPluginFiles finds only .js files', () {
    File('${tmp.path}/a.js').writeAsStringSync('// x');
    File('${tmp.path}/b.txt').writeAsStringSync('// y');
    Directory('${tmp.path}/sub').createSync();
    File('${tmp.path}/sub/c.js').writeAsStringSync('// z');
    final store = PluginStore(tmp);
    final files = store.scanPluginFiles().map((f) => f.path.split('/').last).toList();
    expect(files, ['a.js']);
  });

  test('loadMeta extracts platform/version from CommonJS export', () async {
    final f = File('${tmp.path}/demo.js');
    f.writeAsStringSync('module.exports = { platform: "demo", version: "0.2.0", srcUrl: "http://x" };');
    final info = await PluginStore(tmp).loadMeta(f);
    expect(info.platform, 'demo');
    expect(info.version, '0.2.0');
    expect(info.srcUrl, 'http://x');
    expect(info.path, f.path);
    expect(info.hash, isNotEmpty);
  });
}
