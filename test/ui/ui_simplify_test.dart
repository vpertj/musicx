// test/ui/ui_simplify_test.dart
//
// 界面精简(用户诉求)的确定性验证:
//   1) 首页不再显示音源芯片条
//   2) 歌曲列表不再显示来源标签
//   3) 唱片视图下方显示 5 行滚动歌词(当前句居中高亮)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/models/lyric_line.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/player/player_page.dart';
import 'package:musicx/ui/search/search_page.dart';
import 'package:musicx/ui/widgets/song_tile.dart';

const _plugin = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function (q) {
    return Promise.resolve({ isEnd: true, data: [
      { id: "d1", title: "示例歌曲", artist: "歌手", album: "专辑",
        duration: 180000, platform: "demo", songId: "d1" }
    ] });
  },
  getLyric: function () { return { rawLrc: "[00:01.00]第一句\\n[00:05.00]第二句\\n[00:09.00]第三句" }; }
};
''';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_ui_simplify');
    File('${tmp.path}/demo.js').writeAsStringSync(_plugin);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('首页不再渲染音源芯片(自动/腾讯音乐/网yi/酷我)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pluginManagerProvider.overrideWithValue(PluginManager(tmp))],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    // 首页会异步拉推荐,加载态有持续动画 → 用 pump 而非 pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in ['自动', '腾讯音乐', '网yi', '酷我(念心音源)']) {
      expect(find.text(label), findsNothing, reason: '首页不应再出现音源芯片「$label」');
    }
    // 首页其余内容保持(加载态下静态「热门推荐」会被动态推荐替代,故断言搜索框)
    expect(find.text('搜索歌曲 / 歌手 / 专辑'), findsOneWidget);
  });

  testWidgets('歌曲列表不显示来源标签,但保留下载/加歌单按钮', (tester) async {
    var downloaded = false;
    var added = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongTile(
            song: const MusicItem(
              id: '1',
              title: '示例歌曲',
              artist: '歌手',
              platform: '腾讯音乐',
              songId: '1',
            ),
            onDownload: () => downloaded = true,
            onAdd: () => added = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('腾讯音乐'), findsNothing, reason: '列表不应显示歌曲来源');
    expect(find.byTooltip('下载'), findsOneWidget);
    expect(find.byTooltip('加入歌单'), findsOneWidget);
    await tester.tap(find.byTooltip('下载'));
    await tester.tap(find.byTooltip('加入歌单'));
    expect(downloaded, isTrue);
    expect(added, isTrue);
  });

  testWidgets('唱片视图下方显示歌词窗口,当前句高亮(5 行窗口)', (tester) async {
    const song = MusicItem(
      id: '1',
      title: '测试曲',
      artist: '测试手',
      platform: 'demo',
      songId: '1',
    );
    // 进度 6s → 当前句「第二句」(5s <= 6 < 9);窗口 5 行居中
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => _FakePlayerController(
            song,
            position: const Duration(seconds: 6),
            lyric: const [
              LyricLine(time: Duration(seconds: 1), text: '第一句'),
              LyricLine(time: Duration(seconds: 5), text: '第二句'),
              LyricLine(time: Duration(seconds: 9), text: '第三句'),
              LyricLine(time: Duration(seconds: 13), text: '第四句'),
              LyricLine(time: Duration(seconds: 17), text: '第五句'),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    // 关键:必须设成手机宽度,否则默认 800 宽会走宽屏分支(右侧 _LyricView),
    // 新写的窄屏 _LyricWindow 根本不会被覆盖(会假通过)。
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PlayerPage()),
      ),
    );
    // 注意:唱片视图有持续旋转动画,pumpAndSettle 会超时,用 pump
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 唱片视图(默认)下也应看到歌词 —— 这是本次改动的核心。
    // 窗口随当前句滑动、当前句恒定居中:当前是「第二句」时可见 0~3 行,
    // 第 5 行在窗口之外(设计如此,保证当前句位置不跳动)。
    expect(find.text('第一句'), findsOneWidget);
    expect(find.text('第二句'), findsOneWidget);
    expect(find.text('第三句'), findsOneWidget);
    expect(find.text('第四句'), findsOneWidget);
    expect(find.text('第五句'), findsNothing);

    // 样式由 AnimatedDefaultTextStyle 提供,不在 Text 自身上
    // 取最内层(最近的)AnimatedDefaultTextStyle
    TextStyle styleOf(String line) => tester
        .widgetList<AnimatedDefaultTextStyle>(find.ancestor(
          of: find.text(line),
          matching: find.byType(AnimatedDefaultTextStyle),
        ))
        .first
        .style;
    final currentStyle = styleOf('第二句');
    final otherStyle = styleOf('第三句');
    debugPrint('RESULT: 当前句 fontSize=${currentStyle.fontSize} '
        'weight=${currentStyle.fontWeight} '
        '其它行 fontSize=${otherStyle.fontSize}');
    expect((currentStyle.fontSize ?? 0) > (otherStyle.fontSize ?? 0), isTrue,
        reason: '当前句应比其它行大');
    expect(currentStyle.fontWeight, FontWeight.w700, reason: '当前句应加粗');
  });
}

/// 预置播放状态,避免真实网络播放(与 player_page_test 同思路)。
class _FakePlayerController extends PlayerController {
  _FakePlayerController(this.song, {required this.position, this.lyric = const []});

  final MusicItem song;
  final Duration position;
  final List<LyricLine> lyric;

  @override
  PlayerState build() => PlayerState(
        queue: [song],
        currentIndex: 0,
        isPlaying: true,
        position: position,
        duration: const Duration(minutes: 4),
        lyric: lyric,
      );
}
