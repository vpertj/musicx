// test/ui/chart_detail_test.dart
//
// 用户诉求:排行榜应是「一个完整的、能往上滑的列表,用户在里面选歌」。
//
// 首页只放少量预览,完整榜单(30 首)在独立页面展示。这里锁死:
//   ① 详情页渲染**全部**歌曲(不只首页那几首预览);
//   ② 可滚动浏览;
//   ③ 点击某首按正确下标播放。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/ui/search/chart_detail_page.dart';
import 'package:musicx/ui/widgets/song_tile.dart';

/// 返回 30 首的假榜单(贴近真实榜单规模)。
class _FakeManager extends PluginManager {
  _FakeManager(super.rootDir);

  /// 记录最近一次取详情的榜单,便于断言请求的是哪个榜。
  Map<String, dynamic>? lastRequested;

  @override
  Future<List<Map<String, dynamic>>> topListDetail(
    Map<String, dynamic> topList, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    lastRequested = topList;
    return [
      for (var i = 0; i < 30; i++)
        {
          'id': 'c$i',
          'songId': 'c$i',
          'title': '榜单第$i首',
          'artist': '歌手$i',
          'platform': 'demo',
          'duration': 200000,
        },
    ];
  }
}

void main() {
  late _FakeManager manager;

  Future<void> pumpDetail(
    WidgetTester tester, {
    Map<String, dynamic>? chart,
  }) async {
    manager = _FakeManager(Directory.systemTemp.createTempSync('mx_chart_d'));
    addTearDown(() {
      try {
        manager.rootDir.deleteSync(recursive: true);
      } catch (_) {}
    });
    tester.view.physicalSize = const Size(390, 800) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [pluginManagerProvider.overrideWithValue(manager)],
        child: MaterialApp(
          home: ChartDetailPage(
            topList: chart ??
                {'title': '酷我热歌榜', 'id': 'h1', 'platform': 'demo'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('标题显示榜单名', (tester) async {
    await pumpDetail(tester);
    expect(find.text('酷我热歌榜'), findsOneWidget);
  });

  testWidgets('渲染完整榜单(30 首),而非首页的少量预览', (tester) async {
    await pumpDetail(tester);

    // 首屏能看到前几首;总数应为 30(通过滚动到底验证最后一首存在)
    expect(find.text('榜单第0首'), findsOneWidget);
    expect(find.text('榜单第29首'), findsNothing, reason: '最后一首初始在屏幕外');

    // 往上滑(列表可滚动)
    await tester.drag(find.byType(SongTile).first, const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(
      find.text('榜单第29首'),
      findsOneWidget,
      reason: '应能滑动浏览到榜尾,证明展示的是完整列表',
    );
  });

  testWidgets('点击某一首按正确下标播放', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.text('榜单第0首'));
    await tester.pumpAndSettle();

    // 播放队列应为完整 30 首,且从第 0 首开始
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChartDetailPage)),
    );
    final state = container.read(playerControllerProvider);
    expect(state.queue.length, 30);
    expect(state.currentIndex, 0);
    expect(state.queue.first.title, '榜单第0首');
  });

  testWidgets('向下取的是被点击的那个榜单', (tester) async {
    await pumpDetail(
      tester,
      chart: {'title': '酷我新歌榜', 'id': 'n1', 'platform': 'demo'},
    );
    expect(manager.lastRequested?['id'], 'n1');
    expect(find.text('酷我新歌榜'), findsOneWidget);
  });

  testWidgets('加载失败时给出重试入口', (tester) async {
    // 用一个总是抛错的 manager
    final failing = _FailingManager(
      Directory.systemTemp.createTempSync('mx_chart_f'),
    );
    addTearDown(() {
      try {
        failing.rootDir.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pluginManagerProvider.overrideWithValue(failing)],
        child: const MaterialApp(
          home: ChartDetailPage(
            topList: {'title': '某榜单', 'id': 'x', 'platform': 'demo'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}

class _FailingManager extends PluginManager {
  _FailingManager(super.rootDir);
  @override
  Future<List<Map<String, dynamic>>> topListDetail(
    Map<String, dynamic> topList, {
    Duration timeout = const Duration(seconds: 15),
  }) async => throw Exception('网络错误');
}
