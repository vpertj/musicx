import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/search_controller.dart';
import 'package:musicx/core/search/search_history.dart';
import 'package:musicx/ui/search/search_page.dart';

class _FakeHistory extends SearchHistoryController {
  _FakeHistory(this.initial);
  final List<String> initial;

  @override
  List<String> build() => List.of(initial);
}

void main() {
  testWidgets('聚焦搜索框显示历史下拉', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('musicx_dd');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        searchHistoryProvider.overrideWith(
          () => _FakeHistory(['周杰伦', '林俊杰', '陈奕迅']),
        ),
        pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pump();
    // 聚焦搜索框
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 200));
    // 下拉应显示历史(IdleView 也有'最近搜索'标题,故用 findsWidgets)
    expect(find.text('最近搜索'), findsWidgets);
    // 下拉里应有历史条目(IdleView chips 也有,数量应增加)
    expect(find.text('周杰伦'), findsWidgets);
    expect(find.text('林俊杰'), findsWidgets);
    // 点击下拉里的历史项(带 key)触发搜索
    await tester.tap(find.byKey(const ValueKey('history-item-周杰伦')));
    await tester.pump(const Duration(milliseconds: 300));
    // 已提交搜索:进入结果态,IdleView 消失
    expect(find.text('最近搜索'), findsNothing);
  });
}
