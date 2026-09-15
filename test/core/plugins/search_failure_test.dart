// test/core/plugins/search_failure_test.dart
//
// 搜索全失败时,错误信息必须能说明「哪个源因为什么失败」。
// 此前只抛 'no plugin returned search results',真机排障完全靠猜
// (安卓明文 HTTP 被禁那次就是如此)。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/search_failure.dart';

void main() {
  test('汇总每个源的失败原因', () {
    final text = describeSearchFailuresDetailed(const [
      SearchFailure(platform: '腾讯音乐', error: 'Connection refused'),
      SearchFailure(platform: '网yi', error: 'TimeoutException'),
    ]);
    expect(text, contains('腾讯音乐'));
    expect(text, contains('Connection refused'));
    expect(text, contains('网yi'));
    expect(text, contains('TimeoutException'));
  });

  test('超长错误被截断,避免弹窗/日志爆掉', () {
    final long = 'x' * 500;
    final text = describeSearchFailuresDetailed([
      SearchFailure(platform: 'p', error: long),
    ]);
    expect(text.length, lessThan(200));
    expect(text, contains('…'));
  });

  test('多行错误压成单行', () {
    final text = describeSearchFailuresDetailed(const [
      SearchFailure(platform: 'p', error: 'line1\nline2\nline3'),
    ]);
    expect(text, isNot(contains('\n')));
  });

  test('空列表给出可读提示', () {
    expect(describeSearchFailuresDetailed(const []), '没有可用音源');
  });

  test('用户可见文案不含任何音源名(用户要求 App 内不出现源名)', () {
    final text = describeSearchFailures(const [
      SearchFailure(platform: '腾讯音乐', error: 'boom'),
      SearchFailure(platform: '酷我(念心音源)', error: 'boom2'),
      SearchFailure(platform: '网yi', error: 'boom3'),
    ]);
    for (final name in ['腾讯', '酷我', '念心', '网yi', '网易']) {
      expect(text.contains(name), isFalse, reason: '不应出现「$name」');
    }
  });
}
