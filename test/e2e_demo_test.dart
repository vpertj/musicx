import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

void main() {
  // fetch polyfill 经 rootBundle 加载,需要初始化 binding
  TestWidgetsFlutterBinding.ensureInitialized();

  test('e2e: install demo plugin, search, resolve real playable URL', () async {
    final tmp = Directory.systemTemp.createTempSync('musicx_e2e');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final demoSource = File('example/plugins/demo_plugin.js').readAsStringSync();
    File('${tmp.path}/demo.js').writeAsStringSync(demoSource);

    final manager = PluginManager(tmp);
    final result = await manager.search('SoundHelix');
    final data = (result['data'] as List).cast<Map<String, dynamic>>();
    expect(data, isNotEmpty);

    final first = data.first;
    final media = await manager.resolveMediaSource(first);
    final url = media['url'] as String;
    expect(url, startsWith('https://www.soundhelix.com/examples/mp3/'));
    expect(url, endsWith('.mp3'));
  });
}
