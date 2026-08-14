import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/download/download_controller.dart';
import 'package:musicx/core/library/library_controller.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/downloads/download_page.dart';
import 'package:musicx/ui/library/library_page.dart';
import 'package:musicx/ui/player/player_page.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';
import 'package:musicx/ui/search/search_page.dart';
import 'package:musicx/ui/widgets/mini_player_bar.dart';

/// 应用外壳(桌面优先响应式):
/// - 宽窗口(>=760):左侧导航栏(含歌单列表) + 右侧内容区
/// - 窄窗口:底部导航栏
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  /// 我的页当前显示的歌单(null = 我喜欢的音乐)。
  String? _libraryPlaylistId;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      SearchPage(onOpenPlugins: () => _openSettings()),
      const PlayerPage(),
      LibraryPage(
        key: ValueKey<String?>(_libraryPlaylistId),
        initialPlaylistId: _libraryPlaylistId,
      ),
    ];
  }

  /// 打开指定歌单(切到我的页并显示该歌单)。
  void _openPlaylist(String id) {
    setState(() {
      _libraryPlaylistId = id;
      _pages[2] = LibraryPage(
        key: ValueKey<String?>(_libraryPlaylistId),
        initialPlaylistId: _libraryPlaylistId,
      );
      _index = 2;
    });
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PluginPage()));
  }

  /// 从迷你播放条展开全屏播放器(底部滑入)。
  void _openPlayer() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => const PlayerPage(overlay: true),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  Widget _content() {
    final hasSong = ref.watch(playerControllerProvider).current != null;
    final showMiniPlayer = hasSong && _index != 1;
    return Column(
      children: [
        Expanded(
          child: IndexedStack(index: _index, children: _pages),
        ),
        if (showMiniPlayer) MiniPlayerBar(onOpen: _openPlayer),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 760;

    if (isDesktop) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(
              index: _index,
              onSelect: (i) => setState(() => _index = i),
              onOpenSettings: _openSettings,
              onOpenPlaylist: _openPlaylist,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _content()),
          ],
        ),
      );
    }

    return Scaffold(
      body: _content(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: '发现',
          ),
          NavigationDestination(
            icon: Icon(Icons.music_note_outlined),
            selectedIcon: Icon(Icons.music_note_rounded),
            label: '播放',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

/// 桌面左侧导航栏:导航项 + 我的歌单 + 底部设置。
class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.index,
    required this.onSelect,
    required this.onOpenSettings,
    required this.onOpenPlaylist,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onOpenPlaylist;

  static const _items = [
    (Icons.explore_outlined, Icons.explore_rounded, '发现'),
    (Icons.music_note_outlined, Icons.music_note_rounded, '播放'),
    (Icons.favorite_outline_rounded, Icons.favorite_rounded, '我的'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final lib = ref.watch(libraryControllerProvider);
    final downloads = ref.watch(downloadControllerProvider);

    return Container(
      width: 220,
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: ShaderMask(
                shaderCallback: (bounds) =>
                    AppTheme.accentGradient.createShader(bounds),
                child: Text(
                  'MusicX',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -.5,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            // 导航项
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Column(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    _NavItem(
                      icon: _items[i].$1,
                      selectedIcon: _items[i].$2,
                      label: _items[i].$3,
                      selected: index == i,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
            // 下载音乐
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: _NavItem(
                icon: Icons.download_for_offline_outlined,
                selectedIcon: Icons.download_for_offline_rounded,
                label: '下载音乐 (${downloads.length})',
                selected: false,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const DownloadPage()),
                ),
              ),
            ),
            // 我的歌单
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  Text(
                    '我的歌单',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '新建歌单',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.add_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => _createPlaylist(context, ref),
                  ),
                ],
              ),
            ),
            // 歌单列表
            Expanded(
              child: lib.playlists.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        '还没有歌单\n在歌曲「+」或上方「＋」新建',
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.outline.withValues(alpha: .8),
                          height: 1.5,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        for (final p in lib.playlists)
                          _PlaylistNavItem(
                            name: p.name,
                            count: p.songs.length,
                            onTap: () => onOpenPlaylist(p.id),
                          ),
                      ],
                    ),
            ),
            const Divider(height: 1),
            // 底部:设置
            _NavItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: '设置',
              selected: false,
              onTap: onOpenSettings,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _createPlaylist(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
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
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              ref.read(libraryControllerProvider.notifier).createPlaylist(name);
              Navigator.pop(ctx);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

/// 侧边栏歌单项。
class _PlaylistNavItem extends StatelessWidget {
  const _PlaylistNavItem({
    required this.name,
    required this.count,
    required this.onTap,
  });

  final String name;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                Icons.queue_music_rounded,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '$count',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧边栏导航项。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? AppTheme.violet.withValues(alpha: .14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 22,
                  color: selected ? AppTheme.violet : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
