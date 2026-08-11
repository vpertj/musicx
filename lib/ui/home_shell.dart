import 'package:flutter/material.dart';
import 'player/player_page.dart';
import 'plugins/plugin_page.dart';
import 'search/search_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  static const _pages = [SearchPage(), PluginPage(), PlayerPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(icon: Icon(Icons.extension), label: '插件'),
          NavigationDestination(icon: Icon(Icons.music_note), label: '播放'),
        ],
      ),
    );
  }
}
