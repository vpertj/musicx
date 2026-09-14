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

  test('normalizeResultItem 保留插件专属字段到 extra(songmid 等)', () {
    final item = <String, dynamic>{
      'id': 97773,
      'title': '晴天',
      'songmid': '0039MnYb0qxYhV',
      'strMediaMid': '003Qui1q2u1Zho',
      'mid': '0039MnYb0qxYhV',
      'duration': 269,
    };
    normalizeResultItem(item, platform: '腾讯音乐');

    final extra = item['extra'] as Map<String, dynamic>;
    expect(extra['songmid'], '0039MnYb0qxYhV');
    expect(extra['strMediaMid'], '003Qui1q2u1Zho');
  });

  test('pluginItem 把 extra 里的专属字段还原给插件(item 自身优先)', () {
    final item = <String, dynamic>{
      'id': '97773',
      'title': '晴天',
      'platform': '腾讯音乐',
      'songId': '97773',
      'duration': 269000,
      'extra': <String, dynamic>{
        'songmid': '0039MnYb0qxYhV',
        'strMediaMid': '003Qui1q2u1Zho',
        'title': '旧标题',
      },
    };
    final forPlugin = pluginItem(item);
    expect(forPlugin['songmid'], '0039MnYb0qxYhV',
        reason: 'tx.js 的 getLyric 依赖 songmid,丢了就取不到歌词');
    expect(forPlugin['strMediaMid'], '003Qui1q2u1Zho');
    expect(forPlugin['title'], '晴天', reason: 'item 自身字段优先');
    expect(forPlugin['duration'], 269000);
  });

  test('pluginItem 对没有 extra 的条目原样返回', () {
    final item = <String, dynamic>{'id': '1', 'title': 'x'};
    expect(pluginItem(item), same(item));
  });

  test('normalizeResultItem 不动已有的 songId', () {
    final item = <String, dynamic>{'id': 1, 'songId': 'keep', 'duration': 200000};
    normalizeResultItem(item, platform: 'x');
    expect(item['songId'], 'keep');
    expect(item['duration'], 200000);
  });
}
