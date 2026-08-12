import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/search/search_controller.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/widgets/song_tile.dart';

/// 搜索页:品牌头部 + 搜索历史/推荐 + 结果列表。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.onOpenPlugins});

  /// 跳转到插件页(由 HomeShell 注入,用于安装插件引导)。
  final VoidCallback? onOpenPlugins;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _history = [];

  static const List<String> _suggestions = [
    'SoundHelix',
    '周杰伦',
    '林俊杰',
    '陈奕迅',
    'Taylor Swift',
    '钢琴曲',
    'Lo-Fi',
    'City Pop',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final keyword = raw.trim();
    if (keyword.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _history.remove(keyword);
      _history.insert(0, keyword);
      if (_history.length > 8) _history.removeLast();
    });
    ref.read(searchControllerProvider.notifier).search(keyword);
  }

  void _pickSuggestion(String keyword) {
    _controller.text = keyword;
    _submit(keyword);
  }

  void _clear() {
    _controller.clear();
    ref.read(searchControllerProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final hasQuery = state.query.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              controller: _controller,
              onSubmit: _submit,
              onClear: _clear,
            ),
            Expanded(
              child: hasQuery
                  ? _ResultView(
                      state: state,
                      onRetry: () => _submit(state.query),
                      onPlayAll: () => ref
                          .read(playerControllerProvider.notifier)
                          .playFromList(state.results, 0),
                      onPlay: (index) => ref
                          .read(playerControllerProvider.notifier)
                          .playFromList(state.results, index),
                    )
                  : _IdleView(
                      history: _history,
                      suggestions: _suggestions,
                      onPick: _pickSuggestion,
                      onClearHistory: () => setState(_history.clear),
                      onOpenPlugins: widget.onOpenPlugins,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 品牌头部 + 搜索框。
class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.onSubmit,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppTheme.accentGradient.createShader(bounds),
                child: Text(
                  'MusicX',
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  gradient: AppTheme.accentGradient,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text(
                  'FREE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '插件化音乐播放器',
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: onSubmit,
            decoration: InputDecoration(
              hintText: '搜索歌曲 / 歌手 / 专辑',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    tooltip: '清空',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: onClear,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 空闲态:欢迎语 + 最近搜索 + 热门推荐 + 插件引导。
class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.history,
    required this.suggestions,
    required this.onPick,
    required this.onClearHistory,
    this.onOpenPlugins,
  });

  final List<String> history;
  final List<String> suggestions;
  final ValueChanged<String> onPick;
  final VoidCallback onClearHistory;
  final VoidCallback? onOpenPlugins;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(
          '发现好音乐',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '输入关键词,从已安装的插件源搜索全网音乐',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 28),
          Row(
            children: [
              _SectionTitle('最近搜索'),
              const Spacer(),
              InkWell(
                onTap: onClearHistory,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    '清空',
                    style: textTheme.bodySmall?.copyWith(color: scheme.outline),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kw in history)
                ActionChip(
                  avatar: Icon(Icons.history_rounded,
                      size: 16, color: scheme.onSurfaceVariant),
                  label: Text(kw),
                  onPressed: () => onPick(kw),
                ),
            ],
          ),
        ],
        const SizedBox(height: 28),
        _SectionTitle('热门推荐'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kw in suggestions)
              ActionChip(
                avatar: Icon(Icons.local_fire_department_rounded,
                    size: 16, color: AppTheme.pink),
                label: Text(kw),
                onPressed: () => onPick(kw),
              ),
          ],
        ),
        if (onOpenPlugins != null) ...[
          const SizedBox(height: 32),
          Material(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onOpenPlugins,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: AppTheme.softGradient,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.extension_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '音乐由插件驱动',
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '前往插件页安装更多音乐源',
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: scheme.outline),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

/// 结果态:加载 / 错误 / 空 / 列表。
class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.state,
    required this.onRetry,
    required this.onPlayAll,
    required this.onPlay,
  });

  final SearchState state;
  final VoidCallback onRetry;
  final VoidCallback onPlayAll;
  final ValueChanged<int> onPlay;

  @override
  Widget build(BuildContext context) {
    if (state.loading) return _LoadingView(query: state.query);
    if (state.error != null) {
      return _ErrorView(error: state.error!, onRetry: onRetry);
    }
    if (state.results.isEmpty) return _EmptyResultView(query: state.query);

    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '“${state.query}”的搜索结果',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${state.results.length} 首',
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onPlayAll,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.pink,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.playlist_play_rounded, size: 18),
                label: const Text('全部播放'),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
            itemCount: state.results.length,
            itemBuilder: (context, index) {
              final song = state.results[index];
              return SongTile(
                song: song,
                showPlatform: true,
                onTap: () => onPlay(index),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '正在搜索 “$query”…',
            style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              '搜索失败',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResultView extends StatelessWidget {
  const _EmptyResultView({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 56, color: scheme.outline),
          const SizedBox(height: 16),
          Text(
            '未找到与 “$query” 相关的歌曲',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            '试试其他关键词,或安装更多音乐源插件',
            style: textTheme.bodySmall?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
