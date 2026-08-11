import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/main.dart';

void main() {
  testWidgets('HomeShell shows three nav destinations and switches pages',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MusicxApp()));

    final navBar = find.byType(NavigationBar);
    expect(navBar, findsOneWidget);

    // 搜索页占位文本与导航栏标签均为"搜索",用 NavigationBar 上下文区分断言
    expect(find.text('搜索'), findsNWidgets(2)); // body + 导航标签
    expect(
      find.descendant(of: navBar, matching: find.text('搜索')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('插件')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('播放')),
      findsOneWidget,
    );

    // 切到插件页
    await tester.tap(find.descendant(of: navBar, matching: find.text('插件')));
    await tester.pumpAndSettle();
    expect(find.text('插件管理'), findsOneWidget);
  });
}
