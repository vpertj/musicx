// test/ui/blessing_card_test.dart
//
// 设置页底部的寄语卡片(仅安卓展示)。需要保证:
//   ① 展示规则正确(安卓显示,桌面不显示);
//   ② 文案与署名渲染正确、文案水平居中、署名在右下角;
//   ③ 深浅色主题、窄屏下都不溢出;
//   ④ 纯展示不可点。
//
// 注意:单元测试运行在 macOS 上,按真实平台判断卡片会被隐藏,
// 因此渲染类断言统一用 BlessingCard(visibleOverride: true) 直接驱动,
// 平台规则本身另有专门用例覆盖(不依赖宿主平台)。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/app_flavor.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';

void main() {
  /// 直接渲染卡片本体(绕过平台判断,便于在任意宿主上断言)。
  Future<void> pumpCard(
    WidgetTester tester, {
    required bool dark,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: BlessingCard(visibleOverride: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('展示变体规则', () {
    test('仅吴玫静版显示,标准版不显示', () {
      expect(BlessingCard.isVisibleIn(AppFlavor.blessing), isTrue);
      expect(BlessingCard.isVisibleIn(AppFlavor.standard), isFalse);
    });

    testWidgets('visibleOverride=false 时不渲染任何内容', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BlessingCard(visibleOverride: false)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(BlessingCard.line1), findsNothing);
      expect(find.text(BlessingCard.signature), findsNothing);
    });
  });

  testWidgets('渲染寄语文案与右下角署名', (tester) async {
    await pumpCard(tester, dark: false);

    expect(find.text('玫风入怀,静享喜乐,日日有甜。'), findsOneWidget);
    expect(find.text('---吴玫静'), findsOneWidget, reason: '右下角应有署名');
  });

  testWidgets('文案在卡片内水平居中', (tester) async {
    // 用户实测过文案偏左:只给 textAlign 不够,Text 默认按内容宽度收缩,
    // 必须让 Text 撑满卡片宽度(SizedBox width: double.infinity)。
    await pumpCard(tester, dark: false);

    final textFinder = find.text(BlessingCard.line1);
    // 用 BlessingCard 自身矩形作为卡片边界:卡片内部还有装饰性的圆形
    // Container,`find.ancestor(...Container).first` 未必命中卡片本体。
    final cardRect = tester.getRect(find.byType(BlessingCard));
    final textRect = tester.getRect(textFinder);

    expect(
      (textRect.center.dx - cardRect.center.dx).abs(),
      lessThan(1.0),
      reason: '文案中心应与卡片中心重合(实测为 0px);'
          '偏差大说明 Text 没撑满宽度,textAlign 失效',
    );
  });

  testWidgets('署名贴在卡片右下角', (tester) async {
    await pumpCard(tester, dark: false);

    final cardRect = tester.getRect(find.byType(BlessingCard));
    final lineRect = tester.getRect(find.text(BlessingCard.line1));
    final sigRect = tester.getRect(find.text(BlessingCard.signature));

    // 横向:贴着右边缘(右侧留白≈卡片内边距 20px,而非居中/靠左)
    expect(
      cardRect.right - sigRect.right,
      lessThan(30.0),
      reason: '署名应右对齐,贴近卡片右边缘',
    );
    // 纵向:排在正文下方(即右下角)
    expect(
      sigRect.top,
      greaterThan(lineRect.bottom),
      reason: '署名应在正文下方',
    );
  });

  testWidgets('窄屏(320dp)下不溢出', (tester) async {
    await pumpCard(tester, dark: false, size: const Size(320, 640));
    expect(tester.takeException(), isNull, reason: '窄屏不应出现 RenderFlex 溢出');
    expect(find.text(BlessingCard.line1), findsOneWidget);
    expect(find.text(BlessingCard.signature), findsOneWidget);
  });

  testWidgets('深色主题下正常渲染(有独立配色)', (tester) async {
    await pumpCard(tester, dark: true);
    expect(tester.takeException(), isNull);
    expect(find.text(BlessingCard.line1), findsOneWidget);
  });

  testWidgets('纯展示:卡片内没有可点击控件', (tester) async {
    await pumpCard(tester, dark: false);

    final card = find.byType(BlessingCard);
    expect(
      find.descendant(of: card, matching: find.byType(InkWell)),
      findsNothing,
      reason: '纯展示卡片不该有点击响应',
    );
    expect(
      find.descendant(of: card, matching: find.byType(IconButton)),
      findsNothing,
    );
  });
}
