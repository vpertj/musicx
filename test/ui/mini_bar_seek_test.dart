import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/home_shell.dart';

MusicItem _song(int i) => MusicItem(
  id: '$i',
  title: '迷你条测试 $i',
  artist: '歌手',
  platform: 'demo',
  songId: '$i',
  duration: 200000,
);

class _SeekRecorder extends PlayerController {
  final List<Duration> seeks = [];

  @override
  PlayerState build() => PlayerState(
    queue: [_song(0)],
    currentIndex: 0,
    isPlaying: true,
    position: const Duration(seconds: 10),
    duration: const Duration(seconds: 100),
  );

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }
}

void main() {
  testWidgets('迷你播放条点击进度条触发 seek', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final recorder = _SeekRecorder();
    final container = ProviderContainer(
      overrides: [playerControllerProvider.overrideWith(() => recorder)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 进度条是最顶部那个:高度 6 的 SizedBox 内的 GestureDetector
    final progressBar = find.ancestor(
      of: find.byType(FractionallySizedBox),
      matching: find.byType(GestureDetector),
    );
    expect(progressBar, findsOneWidget);

    // 点击进度条中点 -> 应 seek 到 50s
    await tester.tapAt(tester.getCenter(progressBar));
    await tester.pump();
    expect(recorder.seeks, isNotEmpty);
    expect(recorder.seeks.last.inSeconds, 50);
  });
}
