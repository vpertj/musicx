// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('testPlugin: mock 健康插件返回可用', () async {
    final tmp = Directory.systemTemp.createTempSync('musicx_tp');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/demo.js').writeAsStringSync('''
module.exports = { platform: "demo", version: "0.1.0",
  search: function(q){ return Promise.resolve({isEnd:true,data:[{id:"1",title:"测试歌",artist:"歌手",songId:"1"}]}); },
  getMediaSource: function(m){ return Promise.resolve({url:"https://example.com/test.mp3"}); }
};
''');
    final mgr = PluginManager(tmp);
    final r = await mgr.testPlugin('demo');
    print('demo: ok=' + r.ok.toString() + ' detail=' + r.detail);
    expect(r.ok, isTrue);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('testPlugin: 无结果插件返回不可用', () async {
    final tmp = Directory.systemTemp.createTempSync('musicx_tp2');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/demo.js').writeAsStringSync('''
module.exports = { platform: "demo2", version: "0.1.0",
  search: function(q){ return Promise.resolve({isEnd:true,data:[]}); }
};
''');
    final mgr = PluginManager(tmp);
    final r = await mgr.testPlugin('demo2');
    print('demo2: ok=' + r.ok.toString() + ' detail=' + r.detail);
    expect(r.ok, isFalse);
  }, timeout: const Timeout(Duration(minutes: 1)));
}