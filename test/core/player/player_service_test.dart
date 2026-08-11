import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PlayerService exposes playing stream and controls', () async {
    final service = PlayerService();
    expect(service.playingStream, isNotNull);
    expect(service.positionStream, isNotNull);
    // 无真实网络环境下不实际播放;仅验证构造与 dispose 不抛异常
    service.dispose();
  });

  test('PlayerService seek/pause on idle player does not throw', () async {
    final service = PlayerService();
    await service.pause();
    await service.seek(const Duration(seconds: 1));
    service.dispose();
  });
}
