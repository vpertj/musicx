// 榜单详情页:展示某个排行榜的完整歌曲列表(可上下滑动浏览并选歌)。
//
// 为什么独立成页:首页只适合放少量预览,而榜单本身有 30 首。用户诉求是
// 「一个完整的列表,能往上滑、在里面选歌」—— 这正是独立列表页的形态。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/widgets/download_picker.dart';
import 'package:musicx/ui/widgets/playlist_picker.dart';
import 'package:musicx/ui/widgets/song_tile.dart';

/// 打开某个榜单的完整列表页。
///
/// [topList] 为插件返回的榜单对象(含 title/id/platform)。
Future<void> openChartDetail(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> topList,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChartDetailPage(topList: topList),
    ),
  );
}

/// 榜单详情页:完整歌曲列表 + 播放全部。
class ChartDetailPage extends ConsumerStatefulWidget {
  const ChartDetailPage({super.key, required this.topList});

  final Map<String, dynamic> topList;

  @override
  ConsumerState<ChartDetailPage> createState() => _ChartDetailPageState();
}

class _ChartDetailPageState extends ConsumerState<ChartDetailPage> {
  List<MusicItem> _songs = const [];
  bool _loading = true;
  String? _error;

  String get _title {
    final t = '${widget.topList['title'] ?? ''}'.trim();
    return t.isEmpty ? '排行榜' : t;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final manager = ref.read(pluginManagerProvider);
      final detail = await manager.topListDetail(widget.topList);
      final songs = <MusicItem>[];
      for (final raw in detail) {
        try {
          songs.add(MusicItem.fromJson(raw));
        } catch (_) {
          // 单条解析失败不影响整页
        }
      }
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _play(int index) {
    ref.read(playerControllerProvider.notifier).playFromList(_songs, index);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_songs.isNotEmpty)
            TextButton.icon(
              onPressed: () => _play(0),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('播放全部'),
            ),
        ],
      ),
      body: _buildBody(scheme, textTheme),
    );
  }

  Widget _buildBody(ColorScheme scheme, TextTheme textTheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 40, color: scheme.outline),
              const SizedBox(height: 12),
              Text('加载失败', style: textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_songs.isEmpty) {
      return Center(
        child: Text(
          '这个榜单暂时没有歌曲',
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    // 完整列表:可上下滚动浏览。带序号是排行榜惯例,便于一眼看出名次。
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _songs.length,
      itemBuilder: (context, i) {
        final song = _songs[i];
        return Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.center,
                style: textTheme.labelMedium?.copyWith(
                  color: i < 3 ? scheme.primary : scheme.outline,
                  fontWeight: i < 3 ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: SongTile(
                song: song,
                onTap: () => _play(i),
                onDownload: () => showDownloadPicker(context, ref, song),
                onAdd: () => showPlaylistPicker(context, ref, song),
              ),
            ),
          ],
        );
      },
    );
  }
}
