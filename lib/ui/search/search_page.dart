import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/search/search_controller.dart';
import 'package:musicx/core/search/search_history.dart';
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/widgets/download_picker.dart';
import 'package:musicx/ui/widgets/playlist_picker.dart';
import 'package:musicx/ui/widgets/song_tile.dart';
import 'package:musicx/core/plugins/plugin_info.dart';
import 'package:musicx/models/music_item.dart';

/// 发现页:渐变品牌头部 + 搜索框 + 热门推荐/历史 + 插件引导。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.onOpenPlugins});

  /// 跳转到插件页(由 HomeShell 注入,用于安装插件引导)。
  final VoidCallback? onOpenPlugins;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  // 下拉是否可见(聚焦或输入时)
  bool _dropdownOpen = false;

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
    setState(() => _dropdownOpen = false);
    // 记录搜索历史(持久化)
    ref.read(searchHistoryProvider.notifier).add(keyword);
    ref
        .read(searchControllerProvider.notifier)
        .search(keyword, source: ref.read(searchSourceProvider));
  }

  /// 切换音源:更新全局设置;若已有搜索词则用新音源重新搜索。
  void _selectSource(String? platform) {
    ref.read(searchSourceProvider.notifier).select(platform);
    final query = _controller.text.trim();
    if (query.isNotEmpty) {
      ref
          .read(searchControllerProvider.notifier)
          .search(query, source: platform);
    }
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
        // 桌面宽屏内容限宽居中,与「我的」页保持一致
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                _Header(
                  controller: _controller,
                  onSubmit: _submit,
                  onClear: _clear,
                  onOpenPlugins: widget.onOpenPlugins,
                  onFocusChanged: (f) =>
                      setState(() => _dropdownOpen = f && !hasQuery),
                ),
                // 历史下拉:聚焦且未搜索时显示(占布局流,可靠可点击)
                if (_dropdownOpen &&
                    ref.watch(searchHistoryProvider).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: _HistoryDropdown(
                      onPick: (kw) {
                        _controller.text = kw;
                        _submit(kw);
                      },
                      onClearAll: () =>
                          ref.read(searchHistoryProvider.notifier).clear(),
                    ),
                  ),
                // 音源切换条
                _SourceBar(
                  selected: ref.watch(searchSourceProvider),
                  onSelect: _selectSource,
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
                          onLoadMore: () => ref
                              .read(searchControllerProvider.notifier)
                              .loadMore(),
                          onAdd: (song) =>
                              showPlaylistPicker(context, ref, song),
                          onDownload: (song) =>
                              showDownloadPicker(context, ref, song),
                        )
                      : _IdleView(
                          history: ref.watch(searchHistoryProvider),
                          suggestions: _suggestions,
                          onPick: _pickSuggestion,
                          onClearHistory: () =>
                              ref.read(searchHistoryProvider.notifier).clear(),
                          onOpenPlugins: widget.onOpenPlugins,
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

/// 简洁头部:仅搜索框。
class _Header extends StatefulWidget {
  const _Header({
    required this.controller,
    required this.onSubmit,
    required this.onClear,
    this.onOpenPlugins,
    this.onFocusChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;
  final VoidCallback? onOpenPlugins;
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      widget.onFocusChanged?.call(_focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: TextField(
        controller: widget.controller,
        textInputAction: TextInputAction.search,
        onSubmitted: widget.onSubmit,
        focusNode: _focus,
        decoration: InputDecoration(
          hintText: '搜索歌曲 / 歌手 / 专辑',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: '清空',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: widget.onClear,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 搜索历史下拉面板:悬浮于搜索框下方,展示最近搜索。
/// 点击条目触发搜索;每条可单独删除;底部可清空全部。
class _HistoryDropdown extends ConsumerWidget {
  const _HistoryDropdown({required this.onPick, required this.onClearAll});

  final ValueChanged<String> onPick;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (history.isEmpty) return const SizedBox.shrink();

    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题行
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 15, color: scheme.outline),
                const SizedBox(width: 6),
                Text(
                  '最近搜索',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: onClearAll,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      '清空',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 历史条目
          for (final kw in history.take(8))
            InkWell(
              key: ValueKey('history-item-$kw'),
              onTap: () => onPick(kw),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        kw,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                    InkWell(
                      onTap: () =>
                          ref.read(searchHistoryProvider.notifier).remove(kw),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: scheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 音源切换条:自动 + 已装插件,自适应换行展示。
class _SourceBar extends ConsumerWidget {
  const _SourceBar({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(pluginListProvider).value ?? const <PluginInfo>[];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SourceChip(
            label: '自动',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final p in plugins)
            _SourceChip(
              label: p.platform,
              selected: selected == p.platform,
              onTap: () => onSelect(p.platform),
            ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
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
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: selected ? AppTheme.violet : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: selected ? Colors.white : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
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

  static const List<LinearGradient> _cardGradients = [
    LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)]),
    LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4C1D95)]),
    LinearGradient(colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)]),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 0, 24),
      children: [
        _SectionTitle('热门推荐', icon: Icons.local_fire_department_rounded),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(right: 20),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 108,
              ),
              itemCount: suggestions.length,
              itemBuilder: (context, i) {
                final kw = suggestions[i];
                return _SuggestionCard(
                  keyword: kw,
                  index: i,
                  onTap: () => onPick(kw),
                );
              },
            );
          },
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              _SectionTitle('最近搜索', icon: Icons.history_rounded),
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
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kw in history)
                  ActionChip(label: Text(kw), onPressed: () => onPick(kw)),
              ],
            ),
          ),
        ],
        if (onOpenPlugins != null) ...[
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Material(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onOpenPlugins,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: AppTheme.softGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.extension_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
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
                            const SizedBox(height: 1),
                            Text(
                              '前往「我的」页安装更多音源',
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
          ),
        ],
      ],
    );
  }
}

/// 热门推荐横滑卡片:渐变底 + 序号 + 关键词。
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.keyword,
    required this.index,
    required this.onTap,
  });

  final String keyword;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final gradient =
        _IdleView._cardGradients[index % _IdleView._cardGradients.length];

    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(gradient: gradient),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                right: -14,
                bottom: -16,
                child: Icon(
                  Icons.music_note_rounded,
                  size: 72,
                  color: Colors.white.withValues(alpha: .16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOP ${index + 1}',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: .75),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      keyword,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: AppTheme.violet),
          const SizedBox(width: 6),
        ],
        Text(text, style: style),
      ],
    );
  }
}

/// 结果态:加载 / 错误 / 空 / 列表。
class _ResultView extends StatefulWidget {
  const _ResultView({
    required this.state,
    required this.onRetry,
    required this.onPlayAll,
    required this.onPlay,
    required this.onLoadMore,
    this.onAdd,
    this.onDownload,
  });

  final SearchState state;
  final VoidCallback onRetry;
  final VoidCallback onPlayAll;
  final ValueChanged<int> onPlay;
  final VoidCallback onLoadMore;
  final void Function(MusicItem)? onAdd;
  final void Function(MusicItem)? onDownload;

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 滚动到底部附近时加载下一页
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.loading) return _LoadingView(query: state.query);
    if (state.error != null) {
      return _ErrorView(error: state.error!, onRetry: widget.onRetry);
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
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${state.results.length} 首',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: widget.onPlayAll,
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
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
            itemCount: state.results.length,
            itemBuilder: (context, index) {
              final song = state.results[index];
              return SongTile(
                song: song,
                showPlatform: true,
                onTap: () => widget.onPlay(index),
                onAdd: widget.onAdd == null ? null : () => widget.onAdd!(song),
                onDownload: widget.onDownload == null
                    ? null
                    : () => widget.onDownload!(song),
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
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
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
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
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
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
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
