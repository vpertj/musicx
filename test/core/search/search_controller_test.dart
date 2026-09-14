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
    final container = ProviderContainer(
      overrides: [pluginManagerProvider.overrideWithValue(PluginManager(tmp))],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(searchControllerProvider.notifier);
    await ctrl.search('示例');
    final s = container.read(searchControllerProvider);
    expect(s.loading, isFalse);
    expect(s.error, isNull);
    expect(s.results, isNotEmpty);
    expect(s.results.first.title, '示例歌曲');
  });

  test('search filters out very short songs (<60s)', () async {
    const mixed = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function (q) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({ isEnd: true, data: [
          { id: "d1", title: "完整歌曲", duration: 180000, platform: "demo", songId: "d1", extra: {} },
          { id: "d2", title: "30秒试听", duration: 30000, platform: "demo", songId: "d2", extra: {} },
          { id: "d3", title: "无时长字段", platform: "demo", songId: "d3", extra: {} }
        ] });
      }, 10);
    });
  },
  getMediaSource: function (m) { return { url: "https://x/a.mp3" }; }
};
''';
    File('${tmp.path}/demo.js').deleteSync();
    File('${tmp.path}/mixed.js').writeAsStringSync(mixed);
    final container = ProviderContainer(
      overrides: [pluginManagerProvider.overrideWithValue(PluginManager(tmp))],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(searchControllerProvider.notifier);
    await ctrl.search('示例');
    final s = container.read(searchControllerProvider);
    final titles = s.results.map((m) => m.title).toList();
    expect(titles, contains('完整歌曲'));
    expect(titles, isNot(contains('30秒试听')));
    // 时长未知的歌曲不被误杀
    expect(titles, contains('无时长字段'));
  });

  test('loadMore 追加结果、列表保持可见、翻页到底后停止请求', () async {
    const paged = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function (q, page) {
    page = page || 1;
    return new Promise(function (resolve) {
      setTimeout(function () {
        var data = page <= 2
            ? [ { id: "p" + page, title: "歌曲第" + page + "页", duration: 180000,
                  platform: "demo", songId: "p" + page, extra: {} } ]
            : [];
        resolve({ isEnd: page >= 2, data: data });
      }, 60);
    });
  },
  getMediaSource: function (m) { return { url: "https://x/a.mp3" }; }
};
''';
    File('${tmp.path}/demo.js').deleteSync();
    File('${tmp.path}/paged.js').writeAsStringSync(paged);
    final container = ProviderContainer(
      overrides: [pluginManagerProvider.overrideWithValue(PluginManager(tmp))],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(searchControllerProvider.notifier);
    await ctrl.search('歌');
    expect(container.read(searchControllerProvider).results, hasLength(1));

    // 翻页中:loadingMore 置位但 loading 不动、已有列表保持(整页不闪白的关键)
    final pending = ctrl.loadMore();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final mid = container.read(searchControllerProvider);
    expect(mid.loadingMore, isTrue);
    expect(mid.loading, isFalse);
    expect(mid.results, hasLength(1));
    await pending;

    final s2 = container.read(searchControllerProvider);
    expect(s2.results, hasLength(2));
    expect(s2.loadingMore, isFalse);
    expect(s2.isEnd, isTrue); // 第 2 页 isEnd=true

    // 到底后再触发:不再发请求(isEnd 守卫),结果不变
    await ctrl.loadMore();
    expect(container.read(searchControllerProvider).results, hasLength(2));
  });
}
