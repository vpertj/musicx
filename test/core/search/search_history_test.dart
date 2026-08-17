import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/search_history.dart';

void main() {
  // 清理可能存在的真实历史数据,避免污染断言
  setUp(() {
    final f = SearchHistoryController.dataFile();
    if (f.existsSync()) f.deleteSync();
  });
  tearDown(() {
    final f = SearchHistoryController.dataFile();
    if (f.existsSync()) f.deleteSync();
  });

  test('add 去重置顶并限制条数', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(searchHistoryProvider.notifier);
    ctrl.add('周杰伦');
    ctrl.add('林俊杰');
    ctrl.add('周杰伦'); // 重复 -> 置顶
    expect(container.read(searchHistoryProvider), ['周杰伦', '林俊杰']);
    // 超限裁剪
    for (var i = 0; i < 15; i++) {
      ctrl.add('歌$i');
    }
    expect(container.read(searchHistoryProvider).length, lessThanOrEqualTo(12));
    expect(container.read(searchHistoryProvider).first, '歌14');
  });

  test('clear 清空历史', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(searchHistoryProvider.notifier);
    ctrl.add('a');
    ctrl.add('b');
    ctrl.clear();
    expect(container.read(searchHistoryProvider), isEmpty);
  });

  test('remove 删除单条', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(searchHistoryProvider.notifier);
    ctrl.add('a');
    ctrl.add('b');
    ctrl.remove('a');
    expect(container.read(searchHistoryProvider), ['b']);
  });
}
