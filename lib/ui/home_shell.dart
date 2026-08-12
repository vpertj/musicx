import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/ui/player/player_page.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';
import 'package:musicx/ui/search/search_page.dart';
import 'package:musicx/ui/widgets/mini_player_bar.dart';

/// 应用外壳:三页签 + 底部迷你播放条。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      SearchPage(onOpenPlugins: () => setState(() => _index = 2)),
      const PlayerPage(),
      const PluginPage(),
    ];
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

  @override
  Widget build(BuildContext context) {
    // 有歌在播且不在播放页时,显示迷你播放条
    final hasSong = ref.watch(playerControllerProvider).current != null;
    final showMiniPlayer = hasSong && _index != 1;

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: IndexedStack(index: _index, children: _pages)),
          if (showMiniPlayer) MiniPlayerBar(onOpen: _openPlayer),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Icon(Icons.music_note_rounded),
            label: '播放',
          ),
          NavigationDestination(
            icon: Icon(Icons.extension_rounded),
            label: '插件',
          ),
        ],
      ),
    );
  }
}
