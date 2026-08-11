import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/search_controller.dart';

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
  getMediaSource: function (m) { return { url: "https://x/a.mp3" }; }
};
''';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_sc');
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('search populates results from plugin', () async {
    final container = ProviderContainer(overrides: [
      pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
    ]);
    addTearDown(container.dispose);
    final ctrl = container.read(searchControllerProvider.notifier);
    await ctrl.search('示例');
    final s = container.read(searchControllerProvider);
    expect(s.loading, isFalse);
    expect(s.error, isNull);
    expect(s.results, isNotEmpty);
    expect(s.results.first.title, '示例歌曲');
  });
}
