import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/player/player_page.dart';

void main() {
  testWidgets('PlayerPage shows current song and controls', (tester) async {
    final song = MusicItem(
        id: '1', title: '测试曲', artist: '测试手', platform: 'demo', songId: '1');
    // 用 override 预置播放状态,避免真实网络播放(just_audio setUrl 在测试环境不可用)
    final container = ProviderContainer(overrides: [
      playerControllerProvider.overrideWith(
        () => _FakePlayerController(song),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PlayerPage()),
    ));
    await tester.pump();

    expect(find.text('测试曲'), findsOneWidget);
    expect(find.text('测试手'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
  });
}

class _FakePlayerController extends PlayerController {
  final MusicItem song;
  _FakePlayerController(this.song);

  @override
  PlayerState build() =>
      PlayerState(queue: [song], currentIndex: 0, isPlaying: true);
}
