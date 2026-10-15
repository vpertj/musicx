// test/ui/app_chip_test.dart
//
// 芯片统一契约:高度 36、圆角 10、选中态品牌红实底、未选中白卡 + 细描边、
// 图标 16(此前 5 处各写各的,还有 emoji 当前缀导致高低不齐)。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/icons.dart';
import 'package:musicx/ui/tokens.dart';
import 'package:musicx/ui/widgets/app_chip.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('尺寸与圆角走 token', (tester) async {
    await tester.pumpWidget(_wrap(
      AppChip(label: '热歌榜', selected: false, onTap: () {}),
    ));

    final material = tester.widget<Material>(find.byType(Material).last);
    final container = tester.widget<Container>(
      find.descendant(of: find.byType(AppChip), matching: find.byType(Container)),
    );
    expect(tester.getSize(find.byType(AppChip)).height, isNotNull);
    expect(
      tester.getSize(find.descendant(
        of: find.byType(AppChip),
        matching: find.byType(Container),
      )).height,
      AppSize.chipHeight,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(
      decoration.borderRadius,
      BorderRadius.circular(AppRadius.chip),
      reason: '圆角统一走 AppRadius.chip',
    );
    expect(material.borderRadius, BorderRadius.circular(AppRadius.chip));
  });

  testWidgets('选中态品牌红实底 + 图标 16;未选中白卡 + 描边', (tester) async {
    final scheme = AppTheme.light.colorScheme;
    await tester.pumpWidget(_wrap(
      Column(
        children: [
          AppChip(
            label: '热歌榜',
            icon: AppIcons.fire,
            selected: true,
            onTap: () {},
          ),
          AppChip(
            label: '新歌榜',
            icon: AppIcons.chart,
            selected: false,
            onTap: () {},
          ),
        ],
      ),
    ));

    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
    expect(icons.first.size, AppSize.iconSmall);
    expect(icons.first.color, Colors.white, reason: '选中态图标用白');

    final boxes = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(boxes.first.color, isNull, reason: '选中态背景由 Material 上色');
    expect(boxes.last.border, isNotNull, reason: '未选中要有细描边');
    expect(boxes.last.border!.top.color, scheme.outlineVariant);
  });

  testWidgets('点击回调可用', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_wrap(
      AppChip(label: '点我', selected: false, onTap: () => tapped++),
    ));
    await tester.tap(find.byType(AppChip));
    expect(tapped, 1);
  });
}
