import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/library/library_controller.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';
import 'package:musicx/ui/widgets/song_tile.dart';

/// 我的页:我喜欢的音乐 + 自定义歌单。
/// [initialPlaylistId] 为 null 时默认显示「我喜欢的音乐」。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.initialPlaylistId});

  final String? initialPlaylistId;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  String? _selected; // null = 我喜欢的音乐,否则为歌单 id

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPlaylistId;
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPlaylistId != oldWidget.initialPlaylistId) {
      _selected = widget.initialPlaylistId;
    }
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '歌单名称',
            prefixIcon: Icon(Icons.queue_music_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final lib = ref.read(libraryControllerProvider.notifier);
    final p = lib.createPlaylist(name);
    setState(() => _selected = p.id);
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final songs = _selected == null
        ? lib.favorites
        : (lib.playlists.where((p) => p.id == _selected).firstOrNull?.songs ??
              const <MusicItem>[]);
    final title = _selected == null
        ? '我喜欢的音乐'
        : lib.playlists.where((p) => p.id == _selected).firstOrNull?.name ??
              '歌单';

    // AppBar 标题:默认「我的」,选中歌单时显示歌单名
    final appBarTitle = _selected == null ? '我的' : title;

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const PluginPage())),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 分类选择:我喜欢的 + 歌单 + 新建
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  itemCount: lib.playlists.length + 2,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return _CatChip(
                        label: '♥ 我喜欢的',
                        selected: _selected == null,
                        onTap: () => setState(() => _selected = null),
                      );
                    }
                    if (i == lib.playlists.length + 1) {
                      return _CatChip(
                        label: '＋ 新建歌单',
                        selected: false,
                        onTap: _createPlaylist,
                      );
                    }
                    final p = lib.playlists[i - 1];
                    return _CatChip(
                      label: p.name,
                      selected: _selected == p.id,
                      onTap: () => setState(() => _selected = p.id),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$title (${songs.length})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: songs.isEmpty
                    ? _EmptyLibrary(
                        isFavorite: _selected == null,
                        onCreate: _createPlaylist,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                        itemCount: songs.length,
                        itemBuilder: (context, i) {
                          final song = songs[i];
                          final isFav = _selected == null;
                          return SongTile(
                            song: song,
                            showPlatform: true,
                            onTap: () => ref
                                .read(playerControllerProvider.notifier)
                                .playFromList(songs, i),
                            trailing: isFav
                                ? IconButton(
                                    tooltip: '取消喜欢',
                                    icon: const Icon(
                                      Icons.favorite_rounded,
                                      color: AppTheme.pink,
                                      size: 20,
                                    ),
                                    onPressed: () => ref
                                        .read(
                                          libraryControllerProvider.notifier,
                                        )
                                        .toggleFavorite(song),
                                  )
                                : IconButton(
                                    tooltip: '移出歌单',
                                    icon: Icon(
                                      Icons.remove_circle_outline_rounded,
                                      color: scheme.onSurfaceVariant,
                                      size: 20,
                                    ),
                                    onPressed: () => ref
                                        .read(
                                          libraryControllerProvider.notifier,
                                        )
                                        .removeSongFromPlaylist(
                                          _selected!,
                                          song,
                                        ),
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  const _CatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? AppTheme.violet : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? Colors.white : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.isFavorite, required this.onCreate});

  final bool isFavorite;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFavorite
                ? Icons.favorite_border_rounded
                : Icons.queue_music_rounded,
            size: 56,
            color: scheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            isFavorite ? '还没有喜欢的歌曲' : '歌单还是空的',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            isFavorite ? '在搜索结果点「+」把歌曲加入歌单吧' : '点「＋ 新建歌单」创建歌单',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
