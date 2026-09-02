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

  Widget _app() => ProviderScope(
        overrides: [
          pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
          searchHistoryProvider.overrideWith(() => _PrefilledHistory()),
        ],
        child: const MaterialApp(home: SearchPage()),
      );

  testWidgets('tapping a history item fills text field and closes dropdown', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
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
}

/// 预填一条搜索历史(避免依赖真实文件 IO)。
class _PrefilledHistory extends SearchHistoryController {
  @override
  List<String> build() => ['网易云'];
}
