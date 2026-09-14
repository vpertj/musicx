// test/ui/download_playlist_test.dart
//
// 用户反馈:下载好的歌曲无法加入指定歌单。
// 这里锁住下载列表的「加入歌单」入口(点击复用统一的歌单选择器)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/download/download_controller.dart';
import 'package:musicx/models/downloaded_song.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/downloads/download_page.dart';

const _song = MusicItem(
  id: '1',
  title: '示例歌曲',
  artist: '歌手',
  platform: 'demo',
  songId: '1',
);

class _FakeDownloads extends DownloadController {
  @override
  List<DownloadedSong> build() => [
        DownloadedSong(
          song: _song,
          filePath: '/tmp/example.mp3',
          quality: 'standard',
          time: DateTime(2026, 9, 14),
        ),
      ];
}

void main() {
  testWidgets('下载列表每首歌都有「加入歌单」入口', (tester) async {
    final container = ProviderContainer(
      overrides: [downloadControllerProvider.overrideWith(_FakeDownloads.new)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DownloadPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('示例歌曲'), findsOneWidget);
    expect(find.byTooltip('加入歌单'), findsOneWidget,
        reason: '下载的歌曲必须能加入歌单');

    // 点击后弹出统一歌单选择器(含「新建歌单」入口)
    await tester.tap(find.byTooltip('加入歌单'));
    await tester.pumpAndSettle();
    expect(find.text('加入歌单'), findsOneWidget, reason: '应弹出选择器标题');
    expect(find.text('新建歌单并加入'), findsOneWidget,
        reason: '选择器内可直接新建歌单');
  });
}
