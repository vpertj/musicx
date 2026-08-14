import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/models/lyric_line.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/player/player_page.dart';
import 'package:musicx/ui/widgets/seek_bar.dart';

void main() {
  testWidgets('PlayerPage shows current song and controls', (tester) async {
    final song = MusicItem(
      id: '1',
      title: '测试曲',
      artist: '测试手',
      platform: 'demo',
      songId: '1',
    );
    // 用 override 预置播放状态,避免真实网络播放(just_audio setUrl 在测试环境不可用)
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => _FakePlayerController(song),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PlayerPage()),
      ),
    );
    await tester.pump();

    expect(find.text('测试曲'), findsOneWidget);
    expect(find.text('测试手'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    // 底部固定控制台:进度条 + 队列入口始终可见
    expect(find.byType(SeekBar), findsOneWidget);
    expect(find.textContaining('播放队列'), findsOneWidget);
  });

  testWidgets('歌词视图下进度条与控制台仍可见', (tester) async {
    final song = MusicItem(
      id: '1',
      title: '测试曲',
      artist: '测试手',
      platform: 'demo',
      songId: '1',
    );
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => _FakePlayerController(
            song,
            lyric: const [
              LyricLine(time: Duration(seconds: 0), text: '第一句'),
              LyricLine(time: Duration(seconds: 5), text: '第二句'),
              LyricLine(time: Duration(seconds: 10), text: '第三句'),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PlayerPage()),
      ),
    );
    await tester.pump();

    // 切换到歌词视图
    await tester.tap(find.text('歌词'));
    await tester.pumpAndSettle();

    expect(find.text('第一句'), findsOneWidget);
    // 歌词模式下进度条 + 控制台仍然存在
    expect(find.byType(SeekBar), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.textContaining('播放队列'), findsOneWidget);
  });
}

class _FakePlayerController extends PlayerController {
  final MusicItem song;
  final List<LyricLine> lyric;
  _FakePlayerController(this.song, {this.lyric = const []});

  @override
  PlayerState build() => PlayerState(
    queue: [song],
    currentIndex: 0,
    isPlaying: true,
    position: const Duration(seconds: 2),
    duration: const Duration(minutes: 4),
    lyric: lyric,
  );
}
