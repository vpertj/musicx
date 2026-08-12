import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:musicx/core/player/player_service.dart';

/// 真实 macOS 环境验证 PlayerService.playUrl(修复后)不挂起且能播放。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('playUrl returns promptly and audio plays', (tester) async {
    const url =
        'https://kw-er.kuwo.cn/519b5950f9c8018fcad4ded65b2fce6b/6a7c0b44/resource/30106/trackmedia/M500004OK6pa2JfRwK.mp3';
    final service = PlayerService();
    try {
      final sw = Stopwatch()..start();
      await service
          .playUrl(url)
          .timeout(const Duration(seconds: 15));
      debugPrint('RESULT: playUrl returned in ${sw.elapsedMilliseconds}ms');
      final playing = await service.playingStream.first
          .timeout(const Duration(seconds: 8));
      debugPrint('RESULT: stream playing=$playing duration=${service.duration}');
      expect(sw.elapsedMilliseconds, lessThan(10000),
          reason: 'playUrl 不应挂起');
      expect(playing, isTrue, reason: '应进入播放状态');
    } catch (e, st) {
      debugPrint('RESULT ERROR: $e\n$st');
      rethrow;
    } finally {
      await service.stop();
      service.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 40)));
}
