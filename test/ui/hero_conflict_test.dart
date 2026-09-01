import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/home_shell.dart';
import 'package:musicx/ui/widgets/mini_player_bar.dart';

MusicItem _song(int i) => MusicItem(
  id: '$i',
  title: 'Hero测试 $i',
  artist: '歌手',
  platform: 'demo',
  songId: '$i',
  duration: 200000,
);

class _FakePlayerController extends PlayerController {
  @override
  PlayerState build() => PlayerState(
    queue: [_song(0)],
    currentIndex: 0,
    isPlaying: true,
    position: const Duration(seconds: 10),
    duration: const Duration(minutes: 3),
  );
}

void main() {
  testWidgets('迷你条展开播放器无 Hero 冲突', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(() => _FakePlayerController()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hero测试 0'), findsWidgets);
    final miniBar = find.byType(MiniPlayerBar);
    await tester.tap(
      find.descendant(of: miniBar, matching: find.byType(InkWell)).first,
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
  });
}