import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final song = state.current;

    return Scaffold(
      appBar: AppBar(title: const Text('播放')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('播放出错:${state.error}',
                    style: const TextStyle(color: Colors.red)),
              ),
            if (song == null)
              const Text('暂无播放内容,去搜索页选一首歌吧')
            else ...[
              const Icon(Icons.music_note, size: 96),
              const SizedBox(height: 16),
              Text(song.title,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(song.artist ?? '',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.skip_previous),
                    onPressed: () =>
                        ref.read(playerControllerProvider.notifier).previous(),
                  ),
                  IconButton(
                    iconSize: 64,
                    icon: Icon(
                        state.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () =>
                        ref.read(playerControllerProvider.notifier).togglePlay(),
                  ),
                  IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.skip_next),
                    onPressed: () =>
                        ref.read(playerControllerProvider.notifier).next(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
