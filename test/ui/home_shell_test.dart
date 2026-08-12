import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/main.dart';

void main() {
  testWidgets('HomeShell shows nav destinations and switches pages',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MusicxApp()));

    final navBar = find.byType(NavigationBar);
    expect(navBar, findsOneWidget);

    // 搜索页品牌头
    expect(find.text('MusicX'), findsOneWidget);
    expect(find.text('发现好音乐'), findsOneWidget);

    // 导航标签
    expect(
      find.descendant(of: navBar, matching: find.text('搜索')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('播放')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('插件')),
      findsOneWidget,
    );

    // 切到播放页:空态提示
    await tester.tap(find.descendant(of: navBar, matching: find.text('播放')));
    await tester.pumpAndSettle();
    expect(find.text('暂无播放内容'), findsOneWidget);

    // 切到插件页:标题
    await tester.tap(find.descendant(of: navBar, matching: find.text('插件')));
    await tester.pumpAndSettle();
    expect(find.text('插件管理'), findsOneWidget);
    expect(find.text('尚未安装插件'), findsOneWidget);
  });
}
