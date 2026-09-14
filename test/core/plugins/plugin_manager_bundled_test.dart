// test/core/plugins/plugin_manager_bundled_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

const _kuwoJs = '''
module.exports = { platform: "kuwo", version: "0.1.0",
  search: function () { return Promise.resolve({ isEnd: true, data: [] }); }
};
''';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('musicx_bundled'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('installBundledJs 落盘到插件目录并可被 listPlugins 扫到', () async {
    final manager = PluginManager(tmp);
    final info = await manager.installBundledJs(
      _kuwoJs,
      source: 'bundled:assets/plugins/kuwo.js',
    );

    expect(info.platform, 'kuwo');
    expect(File(info.path).existsSync(), isTrue);
    expect(await File(info.path).readAsString(), _kuwoJs);
    final listed = await manager.listPlugins();
    expect(listed.map((p) => p.platform), contains('kuwo'));
  });

  test('installBundledJs 拒绝缺少 platform/version 的内容', () async {
    final manager = PluginManager(tmp);
    await expectLater(
      manager.installBundledJs('module.exports = {};', source: 'bundled:x'),
      throwsArgumentError,
    );
    expect(tmp.listSync(), isEmpty);
  });
}
