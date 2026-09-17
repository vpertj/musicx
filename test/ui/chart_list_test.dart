// test/ui/chart_list_test.dart
//
// 用户反馈:排行榜用卡片网格「好占地方」,希望改成列表。
//
// 这里锁死两件事:
//   ① 排行榜/猜你喜欢渲染为**列表行**(而不是卡片网格);
//   ② 榜单带序号,且前三名有强调色(排行榜惯例,卡片网格做不到)。
//
// 说明:_ChartList 是私有 widget,无法直接实例化。因此通过公开的
// SearchPage 驱动:它的推荐数据来自 pluginManagerProvider,这里用假的
// manager 直接返回榜单数据(不启动真实 isolate,避免 FakeAsync 无法推进)。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/search/recommend.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/ui/search/chart_detail_page.dart';
import 'package:musicx/ui/search/search_page.dart';
import 'package:musicx/ui/widgets/song_tile.dart';

/// 假的插件管理器:只覆写榜单相关接口,不启动 isolate。
/// 记录 topLists 被调用的次数,用于验证「下拉刷新确实重新拉取」。
int managerCallCount = 0;

class _FakeManager extends PluginManager {
  _FakeManager(super.rootDir);

  @override
  Future<List<Map<String, dynamic>>> topLists({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    managerCallCount++;
    return [
      {'title': '会员飙升榜', 'id': 's1', 'platform': 'demo'},
      {'title': '酷我热歌榜', 'id': 'h1', 'platform': 'demo'},
      {'title': '酷我新歌榜', 'id': 'n1', 'platform': 'demo'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> topListDetail(
    Map<String, dynamic> topList, {
    Duration timeout = const Duration(seconds: 15),
  }) async => [
    for (var i = 0; i < 9; i++)
      {
        'id': 'r$i',
        'songId': 'r$i',
        'title': '榜单歌曲$i',
        'artist': '歌手$i',
        'platform': 'demo',
        'duration': 180000,
      },
  ];

  @override
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    String? platform,
    Duration timeout = const Duration(seconds: 15),
  }) async => {'isEnd': true, 'data': const []};
}

void main() {
  setUp(() => managerCallCount = 0);

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginManagerProvider.overrideWithValue(_FakeManager(Directory.systemTemp.createTempSync('mx_chart'))),
        ],
        child: MaterialApp(
          // 每个用例注入独立缓存:SearchPage 默认用进程级共享缓存,
          // 否则第二个用例会直接复用第一个用例的结果,断言看似失败实为缓存命中。
          home: Scaffold(
            body: SearchPage(recommendCache: RecommendCache()),
          ),
        ),
      ),
    );
    // 榜单数据是异步加载的:用 runAsync 推进真实事件循环(若干次),
    // 再 pumpAndSettle 让 UI 落地。固定等待容易在负载高时不够,
    // 因此多轮探测「是否已渲染出榜单行」。
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 120),
          ));
      await tester.pumpAndSettle();
      if (find.byType(SongTile).evaluate().isNotEmpty) break;
    }
  }

  testWidgets('榜单渲染为列表行(不再是卡片网格)', (tester) async {
    await pumpHome(tester);

    // 列表行使用 SongTile;若仍是卡片网格则一个都不会出现
    expect(
      find.byType(SongTile),
      findsWidgets,
      reason: '排行榜应渲染为列表行(SongTile),而不是卡片网格',
    );
    // 卡片网格的标题+歌手堆叠结构不应再出现在榜单区域
    expect(find.text('榜单歌曲0'), findsOneWidget);

    // 紧凑排列:单行高度应明显小于普通 SongTile(封面 52 → 40,
    // 实测默认行高 76px、紧凑 64px)。用户反馈默认间距"有点大"。
    final rowRect = tester.getRect(find.byType(SongTile).first);
    expect(rowRect.height, lessThan(70.0),
        reason: '榜单行应使用紧凑模式(dense),行高明显小于默认 SongTile(76px)');
  });

  testWidgets('区块标题显示真实榜单名(而非写死的「热门推荐」)', (tester) async {
    await pumpHome(tester);

    expect(
      find.text('酷我热歌榜'),
      findsWidgets,
      reason: '应优先选中热歌榜,并把它的名字显示为区块标题',
    );
  });

  testWidgets('榜单行带序号,前三名有强调色', (tester) async {
    await pumpHome(tester);

    // 序号 1/2/3 应存在
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(find.text('3'), findsWidgets);

    // 第 1 名与第 4 名的颜色应不同(前三名强调)
    final t1 = tester.widget<Text>(find.text('1').first);
    final t4 = tester.widget<Text>(find.text('4').first);
    expect(
      t1.style?.color,
      isNot(t4.style?.color),
      reason: '前三名应使用品牌色强调,其余弱化',
    );
    expect(t1.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('提供下拉刷新(RefreshIndicator)', (tester) async {
    await pumpHome(tester);

    expect(
      find.byType(RefreshIndicator),
      findsOneWidget,
      reason: '首页应支持下拉刷新',
    );
  });

  testWidgets('下拉刷新会重新拉取(忽略缓存)', (tester) async {
    await pumpHome(tester);
    final before = managerCallCount;

    // 触发下拉刷新
    await tester.fling(find.byType(RefreshIndicator), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(
      managerCallCount,
      greaterThan(before),
      reason: '下拉后应重新请求榜单,而不是直接用缓存',
    );
  });

  testWidgets('首页只放预览(6 首),完整榜单走「查看全部」', (tester) async {
    await pumpHome(tester);

    expect(find.text('榜单歌曲0'), findsWidgets);
    expect(
      find.text('查看全部'),
      findsWidgets,
      reason: '应提供进入完整榜单列表页的入口',
    );
  });

  testWidgets('点「查看全部」进入完整榜单页(可上下滑动的列表)', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('查看全部').first);
    await tester.pumpAndSettle();

    expect(
      find.byType(ChartDetailPage),
      findsOneWidget,
      reason: '「查看全部」应打开独立的完整榜单页',
    );
    expect(find.text('播放全部'), findsOneWidget);
    // 完整列表页应能滑到榜尾(首页预览只有 6 首,这里共 9 首)
    await tester.drag(find.byType(ChartDetailPage), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('榜单歌曲8'), findsOneWidget);
  });
}
