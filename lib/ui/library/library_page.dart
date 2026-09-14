import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/download/download_controller.dart';
import 'package:musicx/core/library/library_controller.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/downloads/download_page.dart';
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
    final downloadCount = ref.watch(
      downloadControllerProvider,
    ).length; // 首位入口:下载音乐数量随下载实时更新
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

    // 分类条目(两种布局共用)
    final categories = <_Category>[
      _Category(
        label: '我喜欢的',
        icon: Icons.favorite_rounded,
        selected: _selected == null,
        onTap: () => setState(() => _selected = null),
      ),
      // 下载音乐:固定入口(手机端此前没有下载列表入口)
      _Category(
        label: '下载音乐 ($downloadCount)',
        icon: Icons.download_for_offline_outlined,
        selected: false,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DownloadPage()),
        ),
      ),
      for (final p in lib.playlists)
        _Category(
          label: p.name,
          icon: Icons.queue_music_rounded,
          selected: _selected == p.id,
          onTap: () => setState(() => _selected = p.id),
        ),
      _Category(
        label: '新建歌单',
        icon: Icons.add_rounded,
        selected: false,
        onTap: _createPlaylist,
      ),
    ];

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
              // 分类选择:窄屏横滑芯片;宽屏(桌面)竖排列表
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 760) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final c in categories)
                            _CategoryTile(category: c),
                        ],
                      ),
                    );
                  }
                  return SizedBox(
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      itemCount: categories.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final c = categories[i];
                        return _CatChip(
                          label: switch (i) {
                            0 => '♥ ${c.label}',
                            1 => '⬇ ${c.label}',
                            _ when i == categories.length - 1 =>
                              '＋ ${c.label}',
                            _ => c.label,
                          },
                          selected: c.selected,
                          onTap: c.onTap,
                        );
                      },
                    ),
                  );
                },
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
                                                        onTap: () => ref
                                .read(playerControllerProvider.notifier)
                                .playFromList(songs, i),
                            trailing: isFav
                                ? IconButton(
                                    tooltip: '取消喜欢',
                                    icon: Icon(
                                      Icons.favorite_rounded,
                                      color: scheme.primary,
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

/// 分类条目描述(横滑芯片与竖排列表共用)。
class _Category {
  const _Category({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
}

/// 宽屏(桌面)竖排分类行:图标 + 名称,选中行高亮。
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});

  final _Category category;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: category.selected
            ? scheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: category.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(
                  category.icon,
                  size: 18,
                  color: category.selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: category.selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: category.selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
                if (category.selected)
                  Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: scheme.onPrimaryContainer,
                  ),
              ],
            ),
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
      color: selected ? scheme.primary : scheme.surfaceContainer,
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
