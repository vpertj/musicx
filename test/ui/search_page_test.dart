import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/recommend.dart';
import 'package:musicx/core/search/search_controller.dart';
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/ui/search/search_page.dart';

// 注:插件搜索运行在真实 isolate 中(PluginSandbox.isolate),其完成消息
// 依赖真实事件循环;flutter_test 的 FakeAsync zone 无法推进真实异步,
// 故交互需放在 tester.runAsync 中执行,否则 pumpAndSettle 会因 loading
// 态无限动画而超时。

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
    tmp = Directory.systemTemp.createTempSync('musicx_sp');
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('typing query and submitting shows song results', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
        ],
        child: const MaterialApp(home: SearchPage()),
      ),
    );

    await tester.runAsync(() async {
      await tester.enterText(find.byType(TextField), '示例');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      // 轮询等待结果:固定延时在并发跑测试时不稳定;
      // 也不能用 pumpAndSettle —— 首页推荐加载中的动画会让它永不结束。
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.text('示例歌曲').evaluate().isNotEmpty) break;
      }
    });
    await tester.pump();

    expect(find.text('示例歌曲'), findsOneWidget);
    expect(find.text('歌手'), findsOneWidget);
  });

  testWidgets('首页榜单跟着「默认音源」走(指定了源就不再按自动线路挑)', (tester) async {
    // 用户反馈:升级后首页热歌榜 / 推荐换了个源的内容。根因是首页榜单
    // 无论用户选了什么源都走自动线路(topLists() 当时没有 platform 参数)。
    final manager = _ChartRecordingManager(tmp);
    final container = ProviderContainer(
      overrides: [pluginManagerProvider.overrideWithValue(manager)],
    );
    addTearDown(container.dispose);
    container.read(searchSourceProvider.notifier).select('我的自建源');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SearchPage(recommendCache: RecommendCache()),
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.text('选中的歌').evaluate().isNotEmpty) break;
      }
    });
    await tester.pump();

    expect(
      manager.topListCalls,
      contains('我的自建源'),
      reason: '首页榜单必须把用户选的音源传下去',
    );
    expect(find.text('选中的歌'), findsOneWidget);
  });
}

/// 记录 topLists 收到的 platform,并按该源返回一个可辨认的榜单。
class _ChartRecordingManager extends PluginManager {
  _ChartRecordingManager(super.rootDir);

  final List<String?> topListCalls = [];

  @override
  Future<List<Map<String, dynamic>>> topLists({
    String? platform,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    topListCalls.add(platform);
    return [
      {'title': '热歌榜', 'id': 'h1', 'platform': platform ?? '自动源'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> topListDetail(
    Map<String, dynamic> topList, {
    Duration timeout = const Duration(seconds: 15),
  }) async => [
    {
      'id': 'x1',
      'title': '选中的歌',
      'artist': '歌手',
      'album': '专辑',
      'platform': '${topList['platform']}',
      'songId': 'x1',
      'duration': 180000,
      'extra': <String, dynamic>{},
    },
  ];

  @override
  Future<Map<String, dynamic>> resolveMediaSource(
    Map<String, dynamic> musicItem, {
    String quality = 'standard',
    Duration timeout = const Duration(seconds: 10),
  }) async => {'url': 'https://example.com/a.mp3'};
}
