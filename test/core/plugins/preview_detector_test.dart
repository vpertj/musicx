// test/core/plugins/preview_detector_test.dart
//
// 腾讯/网易的 VIP 歌曲在未登录时会返回 20 秒试听片段。
// 只按「文件小于 256KB」判断会漏掉(20 秒 128kbps ≈ 320KB),
// 因此结合歌曲时长估算应得体积来判断。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/preview_detector.dart';

void main() {
  group('looksLikePreview', () {
    test('已知时长:20 秒试听被判为片段', () {
      // 269 秒的歌,试听约 20 秒 ≈ 320KB,远小于整曲应有体积
      expect(looksLikePreview(contentLength: 320 * 1024, durationMs: 269000), isTrue);
    });

    test('已知时长:整曲不被误判', () {
      // 269 秒 128kbps ≈ 4.3MB
      expect(looksLikePreview(contentLength: 4300000, durationMs: 269000), isFalse);
      // 略小的低码率整曲也要放行
      expect(looksLikePreview(contentLength: 2200000, durationMs: 269000), isFalse);
    });

    test('未知时长:回落到体积阈值(实测片段 0.18MB / 1.26MB 都要挡住)', () {
      expect(looksLikePreview(contentLength: 185 * 1024), isTrue,
          reason: '0.18MB 是「请在手机客户端播放」提示音');
      expect(looksLikePreview(contentLength: 1323746), isTrue,
          reason: '1.26MB 是约 80 秒片段,真机上曾被当成完整曲放行');
      expect(looksLikePreview(contentLength: 5 * 1024 * 1024), isFalse);
    });

    test('体积未知时不判定', () {
      expect(looksLikePreview(contentLength: 0, durationMs: 269000), isFalse);
      expect(looksLikePreview(contentLength: -1), isFalse);
    });

    test('短歌(30 秒)整曲不应因体积小而误判', () {
      // 30 秒整曲 = 30000ms → 期望 ~480KB,阈值取一半 = 240KB
      expect(looksLikePreview(contentLength: 460000, durationMs: 30000), isFalse);
    });
  });
}
