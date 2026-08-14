import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/library/library_controller.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/search/search_controller.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/downloads/download_page.dart';
import 'package:musicx/ui/home_shell.dart';
import 'package:musicx/ui/library/library_page.dart';
import 'package:musicx/ui/player/player_page.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';
import 'package:musicx/ui/search/search_page.dart';

/// 布局审计:在多种窗口尺寸下渲染各页面,检测 RenderFlex overflow。
/// 任何 overflow 都会以 FlutterError 抛出并被 testWidgets 判定失败。

const _demoPlugin = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function (q) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({ isEnd: true, data: [ { id: "d1", title: "示例歌曲", artist: "歌手", album: "专辑",
          artwork: "", duration: 180000, platform: "demo", songId: "d1", extra: {} } ] });
      }, 10);
    });
  },
  getMediaSource: function (m) { return { url: "https://example.com/a.mp3" }; }
};
''';

MusicItem _song(int i) => MusicItem(
  id: '$i',
  title: '测试歌曲标题 $i',
  artist: '测试歌手名字很长很长很长',
  album: '专辑名称也很长很长很长',
  platform: 'demo',
  songId: '$i',
  duration: 200000,
);

class _FakePlayerController extends PlayerController {
  final List<MusicItem> songs;
  _FakePlayerController(this.songs);

  @override
  PlayerState build() => PlayerState(
    queue: songs,
    currentIndex: 0,
    isPlaying: true,
    position: const Duration(minutes: 1, seconds: 23),
    duration: const Duration(minutes: 4, seconds: 5),
  );
}

void main() {
  const sizes = <double>[320, 375, 500, 700, 760, 1024, 1280, 1440];

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_layout');
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
    final f = LibraryController.dataFile();
    if (f.existsSync()) f.deleteSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> setSize(WidgetTester tester, double w) async {
    tester.view.physicalSize = Size(w, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
  }

  for (final w in sizes) {
    testWidgets('HomeShell 空态 w=$w', (tester) async {
      await setSize(tester, w);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: HomeShell())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  // HomeShell 播放态:覆盖迷你播放条布局(有歌曲时)
  for (final w in sizes) {
    testWidgets('HomeShell 播放态(迷你条) w=$w', (tester) async {
      await setSize(tester, w);
      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => _FakePlayerController([_song(0), _song(1)]),
          ),
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
      expect(tester.takeException(), isNull);
      expect(find.text('测试歌曲标题 0'), findsWidgets);
    });
  }

  for (final w in sizes) {
    testWidgets('LibraryPage 空态 w=$w', (tester) async {
      await setSize(tester, w);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LibraryPage())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final w in sizes) {
    testWidgets('SearchPage 空闲态 w=$w', (tester) async {
      await setSize(tester, w);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
          ],
          child: const MaterialApp(home: SearchPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final w in sizes) {
    testWidgets('PlayerPage 播放态 w=$w', (tester) async {
      await setSize(tester, w);
      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => _FakePlayerController([_song(0), _song(1), _song(2)]),
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
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  }

  // 歌词模式窄屏:进度条与控制台仍可见,无溢出
  for (final w in const <double>[320, 375, 500]) {
    testWidgets('PlayerPage 歌词态 w=$w', (tester) async {
      await setSize(tester, w);
      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => _FakePlayerController([_song(0), _song(1)]),
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
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('歌词'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final w in sizes) {
    testWidgets('PluginPage 空插件 w=$w', (tester) async {
      await setSize(tester, w);
      final empty = Directory.systemTemp.createTempSync('musicx_plug_empty');
      addTearDown(() => empty.deleteSync(recursive: true));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginManagerProvider.overrideWithValue(PluginManager(empty)),
          ],
          child: const MaterialApp(home: PluginPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final w in sizes) {
    testWidgets('PluginPage 有插件 w=$w', (tester) async {
      await setSize(tester, w);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
            ],
            child: const MaterialApp(home: PluginPage()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  for (final w in sizes) {
    testWidgets('DownloadPage 空态 w=$w', (tester) async {
      await setSize(tester, w);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DownloadPage())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
