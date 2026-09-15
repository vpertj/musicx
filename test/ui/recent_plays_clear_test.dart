// test/ui/recent_plays_clear_test.dart
//
// 用户诉求:首页「最近播放」既不能整个清空,也不能删掉某一首。
//
// 这里验证 UI 层真的把两个操作接上了:
//   ① 区块标题右侧有「清空」,点击后列表消失;
//   ② 每行有单首移除按钮,点击后只少那一首。
// 同时锁死"删完必须立刻刷新"(只 read 不 watch 时界面会留着旧数据)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/recommend.dart';
import 'package:musicx/ui/search/search_page.dart';

Map<String, dynamic> _song(String id) => {
  'id': id,
  'songId': id,
  'platform': 'kuwo',
  'title': '歌曲$id',
  'artist': '歌手',
};

void main() {
  Future<ProviderContainer> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(playHistoryProvider.notifier).clear();
    container.read(playHistoryProvider.notifier).record(_song('a'));
    container.read(playHistoryProvider.notifier).record(_song('b'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SearchPage())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('「最近播放」区块显示清空按钮与单首移除按钮', (tester) async {
    await pumpHome(tester);

    expect(find.text('最近播放'), findsOneWidget, reason: '有历史时应展示该区块');
    expect(find.text('清空'), findsWidgets, reason: '区块标题右侧应有「清空」');
    expect(
      find.byTooltip('从最近播放中移除'),
      findsWidgets,
      reason: '每行应有单首移除入口',
    );
  });

  testWidgets('点「清空」后整个「最近播放」区块消失', (tester) async {
    final container = await pumpHome(tester);
    expect(find.text('最近播放'), findsOneWidget);

    // 「最近播放」旁的清空按钮是最后一个「清空」(最近搜索的在前)
    await tester.tap(find.text('清空').last);
    await tester.pumpAndSettle();

    expect(container.read(playHistoryProvider), isEmpty, reason: '数据应被清空');
    expect(
      find.text('最近播放'),
      findsNothing,
      reason: '清空后界面必须立刻重建;若仍显示说明没有 watch 数据源',
    );
  });

  testWidgets('点单首移除只删掉那一首,区块仍在', (tester) async {
    final container = await pumpHome(tester);
    expect(container.read(playHistoryProvider), hasLength(2));
    final before = container
        .read(playHistoryProvider)
        .map((e) => e['id'])
        .toList();

    await tester.tap(find.byTooltip('从最近播放中移除').first);
    await tester.pumpAndSettle();

    final after = container
        .read(playHistoryProvider)
        .map((e) => e['id'])
        .toList();
    expect(after, hasLength(1), reason: '只应移除一首');
    expect(before.contains(after.first), isTrue, reason: '剩下的应是原来那首');
    expect(find.text('最近播放'), findsOneWidget, reason: '还剩一首,区块应保留');
  });
}
