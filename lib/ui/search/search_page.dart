import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/search/search_controller.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String keyword) {
    if (keyword.trim().isEmpty) return;
    ref.read(searchControllerProvider.notifier).search(keyword.trim());
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              decoration: const InputDecoration(
                hintText: '搜索歌曲 / 歌手 / 专辑',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (searchState.loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (searchState.error != null)
            Expanded(
              child: Center(child: Text('搜索失败:${searchState.error}')),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: searchState.results.length,
                itemBuilder: (context, index) {
                  final song = searchState.results[index];
                  return ListTile(
                    leading: const Icon(Icons.music_note),
                    title: Text(song.title),
                    subtitle: Text(song.artist ?? ''),
                    onTap: () {
                      ref
                          .read(playerControllerProvider.notifier)
                          .playFromList(searchState.results, index);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
