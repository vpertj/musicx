// test/core/plugins/result_normalizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/result_normalizer.dart';

void main() {
  group('normalizeDurationMs', () {
    test('毫秒保持原值', () {
      expect(normalizeDurationMs(278961), 278961);
      expect(normalizeDurationMs(60000), 60000);
      expect(normalizeDurationMs(1000), 1000);
    });

    test('秒自动换算为毫秒(腾讯音乐 tx.js 返回 269 表示 269 秒)', () {
      expect(normalizeDurationMs(269), 269000);
      expect(normalizeDurationMs(180.5), 180500);
      expect(normalizeDurationMs(999), 999000);
    });

    test('数字字符串同样处理', () {
      expect(normalizeDurationMs('269'), 269000);
      expect(normalizeDurationMs('278961'), 278961);
    });

    test('缺失/非法/非正数保持原样(不猜)', () {
      expect(normalizeDurationMs(null), isNull);
      expect(normalizeDurationMs('abc'), 'abc');
      expect(normalizeDurationMs(0), 0);
      expect(normalizeDurationMs(-5), -5);
      expect(normalizeDurationMs('0'), 0);
    });
  });

  test('normalizeResultItem 同时补 platform 与 songId,并修正时长量纲', () {
    final item = <String, dynamic>{
      'id': 97773,
      'duration': 269,
      'platform': '插件里写死的旧名',
    };
    normalizeResultItem(item, platform: '腾讯音乐');
    expect(item['platform'], '腾讯音乐');
    expect(item['songId'], 97773);
    expect(item['duration'], 269000);
  });

  test('normalizeResultItem 不动已有的 songId', () {
    final item = <String, dynamic>{'id': 1, 'songId': 'keep', 'duration': 200000};
    normalizeResultItem(item, platform: 'x');
    expect(item['songId'], 'keep');
    expect(item['duration'], 200000);
  });
}
