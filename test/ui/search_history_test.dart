import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/search/search_controller.dart'
    show pluginManagerProvider;
import 'package:musicx/core/search/search_history.dart';
import 'package:musicx/ui/search/search_page.dart';

/// 复现:下拉选择历史记录应填入搜索框并关闭下拉(此前因 TextField 失焦
/// 使下拉框在 onTap 前消失而无法选中)。
void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_sh');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget buildApp() => ProviderScope(
        overrides: [
          pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
          searchHistoryProvider.overrideWith(() => _PrefilledHistory()),
        ],
        child: const MaterialApp(home: SearchPage()),
      );

  testWidgets('tapping a history item fills text field and closes dropdown', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    // 聚焦搜索框,展开历史下拉
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // 历史项「网易云」应显示在下拉中
    expect(find.text('网易云'), findsOneWidget);

    // 点击历史项:应填入搜索框并关闭下拉
    await tester.tap(find.text('网易云').first);
    await tester.pumpAndSettle();

    // 第一:搜索框填入历史词(点击选中生效)
    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.controller?.text, '网易云');

    // 第二:下拉已关闭——历史项 widget 不再存在(TextField 里仍有选中词)
    expect(
      find.byKey(const ValueKey('history-item-网易云')),
      findsNothing,
    );
  });

  testWidgets('history item stays selectable even after focus loss (onTapDown)', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    // 聚焦搜索框,展开历史下拉
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('网易云'), findsOneWidget);

    // 模拟真实设备:down 在历史项上,让 TextField 失焦触发下拉重建,再 up。
    // 旧实现(onTap)会因下拉框被移除而丢失点击;onTapDown 在 down 瞬间已选中。
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('网易云')),
    );
    await tester.pump(const Duration(milliseconds: 50));
    // 下拉框已因失焦重建(此时历史项可能已消失)
    await gesture.up();
    await tester.pumpAndSettle();

    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.controller?.text, '网易云');
  });
}

/// 预填一条搜索历史(避免依赖真实文件 IO)。
class _PrefilledHistory extends SearchHistoryController {
  @override
  List<String> build() => ['网易云'];
}
