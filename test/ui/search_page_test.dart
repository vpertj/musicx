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
    File('${tmp.path}/mine.js').writeAsStringSync(_userSourcePlugin);
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

  testWidgets('选中的源已失效(改名/卸载/撤下)—— 首页回落「自动」,不能整页空', (tester) async {
    // 实测事故:1.7.57 把首页榜单/推荐改成「只用选中的源」,但用的仍是**原始选中值**,
    // 没走 SearchPage 已有的 _effectiveSource 自愈逻辑。选中源失效后
    // topLists(platform) 匹配不到插件 → 榜单空;search(artist, platform) 抛
    // 「no plugin resolved」被逐个吞掉 → 猜你喜欢也空 —— 用户看到「首页热门歌曲、
    // 推荐歌曲都没有」。
    final manager = _ChartRecordingManager(tmp);
    final container = ProviderContainer(
      overrides: [pluginManagerProvider.overrideWithValue(manager)],
    );
    addTearDown(container.dispose);
    container.read(searchSourceProvider.notifier).select('已撤下的源');

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

    expect(manager.topListCalls, contains(null), reason: '失效的选中源要回落自动');
    expect(find.text('选中的歌'), findsOneWidget,
        reason: '回落自动后首页必须有内容,不能整页空着');
  });

  testWidgets('选中的源本身没有榜单 —— 首页同样回落自动,不把「热门推荐」空着', (tester) async {
    File('${tmp.path}/mine.js').writeAsStringSync(_userSourcePlugin);
    final manager = _ChartRecordingManager(tmp, chartsOn: {'自动源'});
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

    expect(manager.topListCalls, contains('我的自建源'));
    expect(manager.topListCalls, contains(null), reason: '该源没榜单时应回落自动');
    expect(find.text('选中的歌'), findsOneWidget);
  });
}

/// 用户自装的音源(平台名可辨认),用于「选中源仍有效」的用例。
const _userSourcePlugin = '''
module.exports = { platform: "我的自建源", version: "1.0.0",
  search: function () { return Promise.resolve({ isEnd: true, data: [] }); }
};
''';

/// 记录 topLists 收到的 platform,并按该源返回一个可辨认的榜单。
/// 行为对齐真实管理器:platform 指向**不存在**的插件时拿不到任何榜单。
class _ChartRecordingManager extends PluginManager {
  _ChartRecordingManager(super.rootDir, {this.chartsOn});

  /// 这台「设备」上装了的音源(同步判断,避免 widget 测试里嵌套插件目录 I/O)。
  static const Set<String> knownPlatforms = {'demo', '我的自建源'};

  /// 只有这些 platform 能拿到榜单;null 表示「自动」能拿到、其他源拿不到。
  final Set<String>? chartsOn;

  final List<String?> topListCalls = [];

  @override
  Future<List<Map<String, dynamic>>> topLists({
    String? platform,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    topListCalls.add(platform);
    final wanted = platform ?? '自动源';
    if (chartsOn != null) {
      if (!chartsOn!.contains(wanted)) return const [];
    } else if (wanted != '自动源' && wanted != 'demo' && wanted != '我的自建源') {
      return const [];
    }
    return [
      {'title': '热歌榜', 'id': 'h1', 'platform': wanted},
    ];
  }

  @override
  Future<Map<String, dynamic>> search(
    String keyword, {
    String? platform,
    int page = 1,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // 真实行为:指定了一个没装的源 → 抛错(调用方逐个吞掉,结果为空)。
    // 注意:这里**不能**去 await listPlugins():widget 测试里嵌套读插件目录
    // 会卡住(store 的异步 I/O 在 runAsync 窗口外不再推进),用同步集合代替。
    if (platform != null && !knownPlatforms.contains(platform)) {
      throw Exception('no plugin resolved media source for $platform');
    }
    return {
      'isEnd': true,
      'data': [
        {
          'id': 'g1',
          'title': '猜你喜欢的歌',
          'artist': '歌手',
          'platform': platform ?? '自动源',
          'songId': 'g1',
          'duration': 180000,
        },
      ],
    };
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
