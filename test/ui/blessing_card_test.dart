// test/ui/blessing_card_test.dart
//
// 设置页底部的寄语卡片:纯展示元素,需要保证
//   ① 文案正确渲染;
//   ② 深浅色主题下都不溢出(窄屏尤为容易踩到);
//   ③ 不做交互(避免用户误以为可点)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';

void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    required bool dark,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: const Scaffold(body: PluginPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 切到「通用」分区(卡片所在位置)
    final general = find.text('通用');
    if (general.evaluate().isNotEmpty) {
      await tester.tap(general.first);
      await tester.pumpAndSettle();
    }
  }

  /// 设置页内容较长,卡片在底部,需要滚动才会进入视口与 widget 树。
  Future<void> scrollToBottom(WidgetTester tester) async {
    final scrollables = find.byType(Scrollable);
    for (final e in scrollables.evaluate()) {
      await tester.drag(find.byWidget(e.widget), const Offset(0, -2000));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('设置页底部渲染寄语卡片文案', (tester) async {
    await pumpSettings(tester, dark: false);
    await scrollToBottom(tester);

    expect(
      find.text('玫风入怀,静享喜乐,日日有甜。'),
      findsOneWidget,
      reason: '设置页底部应显示寄语卡片',
    );
  });

  testWidgets('窄屏(320dp)下卡片不溢出', (tester) async {
    await pumpSettings(tester, dark: false, size: const Size(320, 640));
    await scrollToBottom(tester);
    expect(tester.takeException(), isNull, reason: '窄屏不应出现 RenderFlex 溢出');
    expect(find.text('玫风入怀,静享喜乐,日日有甜。'), findsOneWidget);
  });

  testWidgets('深色主题下卡片不报错(有独立配色)', (tester) async {
    await pumpSettings(tester, dark: true);
    await scrollToBottom(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('玫风入怀,静享喜乐,日日有甜。'), findsOneWidget);
  });

  testWidgets('卡片不可点击(纯展示)', (tester) async {
    await pumpSettings(tester, dark: false);
    await scrollToBottom(tester);

    final text = find.text('玫风入怀,静享喜乐,日日有甜。');
    expect(text, findsOneWidget);
    // 卡片祖先链上不应出现 InkWell / GestureDetector(纯展示,无点击反馈)
    final clickable = find.ancestor(
      of: text,
      matching: find.byType(InkWell),
    );
    expect(clickable, findsNothing, reason: '纯展示卡片不该有点击响应');
  });
}
