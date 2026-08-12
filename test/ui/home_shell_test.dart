import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/library/library_controller.dart';
import 'package:musicx/main.dart';

void main() {
  setUp(() {
    // 清空音乐库数据,保证空态断言
    final f = LibraryController.dataFile();
    if (f.existsSync()) f.deleteSync();
  });
  Future<void> setWidth(WidgetTester tester, double w) async {
    tester.view.physicalSize = Size(w, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('窄窗口:底部导航并切换页面', (tester) async {
    await setWidth(tester, 500);
    await tester.pumpWidget(const ProviderScope(child: MusicxApp()));

    final navBar = find.byType(NavigationBar);
    expect(navBar, findsOneWidget);

    // 发现页:搜索框 + 热门推荐
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('热门推荐'), findsOneWidget);

    // 导航标签
    for (final label in ['发现', '播放', '我的']) {
      expect(
        find.descendant(of: navBar, matching: find.text(label)),
        findsOneWidget,
      );
    }

    // 切到播放页:空态提示
    await tester.tap(find.descendant(of: navBar, matching: find.text('播放')));
    await tester.pumpAndSettle();
    expect(find.text('暂无播放内容'), findsOneWidget);

    // 切到我的页:音乐库空态
    await tester.tap(find.descendant(of: navBar, matching: find.text('我的')));
    await tester.pumpAndSettle();
    expect(find.text('还没有喜欢的歌曲'), findsOneWidget);
  });

  testWidgets('宽窗口(桌面):左侧导航栏', (tester) async {
    await setWidth(tester, 1200);
    await tester.pumpWidget(const ProviderScope(child: MusicxApp()));

    // 桌面模式无底部导航,有侧边栏导航项
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('播放'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('我的歌单'), findsOneWidget);

    // 点击侧边栏"我的"切换页面
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('还没有喜欢的歌曲'), findsOneWidget);
  });
}
