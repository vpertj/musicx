import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/search/chart_selection.dart';
import 'package:musicx/core/search/search_controller.dart';
import 'package:musicx/core/search/search_history.dart';
import 'package:musicx/core/search/recommend.dart';
import 'package:musicx/core/search/source_selection.dart';
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/ui/search/chart_detail_page.dart';
import 'package:musicx/ui/widgets/download_picker.dart';
import 'package:musicx/ui/widgets/playlist_picker.dart';
import 'package:musicx/ui/widgets/song_tile.dart';
import 'package:musicx/core/download/download_controller.dart';
import 'package:musicx/models/music_item.dart';

/// 首页榜单区**预览**的歌曲数量。
///
/// 榜单实际有 30 首;首页只放少量预览,完整列表走「查看全部」进入
/// 独立页面(可上下滑动浏览选歌)。取 6 首:列表单行约 76px,
/// 6 首约 456px,与旧卡片网格(2 排)相当而不显臃肿。
const int kHomeChartPreview = 6;

/// 发现页:渐变品牌头部 + 搜索框 + 热门推荐/历史 + 插件引导。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.onOpenPlugins, this.recommendCache});

  /// 跳转到插件页(由 HomeShell 注入,用于安装插件引导)。
  final VoidCallback? onOpenPlugins;

  /// 推荐缓存。默认使用进程级共享缓存(避免切回首页就重新打源站);
  /// 测试可注入独立实例,避免用例之间互相污染。
  final RecommendCache? recommendCache;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  // 下拉是否可见(聚焦或输入时)
  bool _dropdownOpen = false;

  /// 首页动态推荐:热歌榜 + 猜你喜欢(方案 C)。源不支持时回退静态关键词卡。
  List<MusicItem> _hotSongs = const [];
  /// 可切换的榜单(热歌榜/飙升榜/新歌榜…)与当前选中项。
  List<Map<String, dynamic>> _topLists = const [];
  int _topListIndex = 0;
  List<MusicItem> _guessSongs = const [];
  bool _recLoading = false;

  /// 推荐缓存(10 分钟),避免每次回首页都打源站。
  /// 推荐缓存(10 分钟),避免每次回首页都打源站。
  ///
  /// 进程级共享:多个 SearchPage 实例复用同一份缓存。
  /// 测试可通过 [SearchPage.recommendCache] 注入独立实例,避免用例互相污染。
  static final RecommendCache _sharedRecCache = RecommendCache();

  RecommendCache get _recCache => widget.recommendCache ?? _sharedRecCache;

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
  void initState() {
    super.initState();
    // 首帧后异步拉取推荐,不阻塞页面
    Future.microtask(_loadRecommendations);
  }

  /// 拉取热歌榜与猜你喜欢:都是真实音源数据,失败则回退静态卡。
  ///
  /// [force] 为 true 时**忽略缓存**重新拉取(供下拉刷新使用)——
  /// 否则下拉后拿到的还是缓存内容,用户会以为刷新没生效。
  Future<void> _loadRecommendations({bool force = false}) async {
    if (_recLoading) return;
    if (force) {
      _recCache.clear();
    } else {
      final cached = _recCache.get('home');
      if (cached != null) {
        if (mounted) setState(() => _applyRecommendRaw(cached));
        return;
      }
    }
    setState(() => _recLoading = true);
    try {
      final manager = ref.read(pluginManagerProvider);
      final hot = <MusicItem>[];
      final lists = await manager.topLists();
      if (lists.isNotEmpty) {
        // 按名称优先挑出真正的「热歌榜」(而非盲取插件返回的第一个),
        // 并把它排到首位作为默认选中项。见 chart_selection.dart。
        final picked = selectChartsForHome(lists);
        _topListIndex = 0;
        final detail = await manager.topListDetail(picked.first);
        for (final raw in detail.take(kHomeChartPreview)) {
          try {
            hot.add(MusicItem.fromJson(raw));
          } catch (_) {}
        }
        if (mounted) setState(() => _topLists = picked);
      }
      // 猜你喜欢:按本地播放历史里最常听的歌手去找
      final artists = topArtistsFromHistory(ref.read(playHistoryProvider));
      final guess = <MusicItem>[];
      for (final artist in artists) {
        try {
          final r = await manager.search(artist, page: 1);
          final data = (r['data'] as List?) ?? const [];
          for (final raw in data.take(4)) {
            if (raw is! Map) continue;
            final item = Map<String, dynamic>.from(raw);
            // 只保留该歌手本人的歌(避免又混进翻唱)
            if (!'${item['artist'] ?? ''}'.contains(artist)) continue;
            guess.add(MusicItem.fromJson(item));
          }
        } catch (_) {}
      }
      final merged = mergeRecommendations([
        [for (final m in guess) m.toJson()],
      ], limit: 12);
      final guessItems = <MusicItem>[];
      for (final raw in merged) {
        try {
          guessItems.add(MusicItem.fromJson(raw));
        } catch (_) {}
      }
      // 进首页即预热榜单前 2 首:用户直接点首页卡片时也能接近瞬时
      // (此前只有搜索后才预热,冷启动首点仍要等取流)。
      for (final item in hot.take(2)) {
        unawaited(
          manager
              .resolveMediaSource(item.toJson())
              .catchError((_) => <String, dynamic>{}),
        );
      }
      _recCache.put('home', [
        for (final m in hot) {'__kind': 'hot', ...m.toJson()},
        for (final m in guessItems) {'__kind': 'guess', ...m.toJson()},
      ]);
      if (mounted) {
        setState(() {
          _hotSongs = hot;
          _guessSongs = guessItems;
        });
      }
    } catch (_) {
      // 拉取失败:保持静态关键词卡兜底
    } finally {
      if (mounted) setState(() => _recLoading = false);
    }
  }

  void _applyRecommendRaw(List<Map<String, dynamic>> raw) {
    final hot = <MusicItem>[];
    final guess = <MusicItem>[];
    for (final e in raw) {
      try {
        final item = MusicItem.fromJson(e);
        if (e['__kind'] == 'hot') {
          hot.add(item);
        } else {
          guess.add(item);
        }
      } catch (_) {}
    }
    _hotSongs = hot;
    _guessSongs = guess;
  }

  /// 切换到第 index 个榜单(热歌榜/飙升榜/新歌榜…)。
  Future<void> _switchTopList(int index) async {
    if (index == _topListIndex || index < 0 || index >= _topLists.length) return;
    setState(() {
      _topListIndex = index;
      _hotSongs = const [];
      _recLoading = true;
    });
    try {
      final manager = ref.read(pluginManagerProvider);
      final detail = await manager.topListDetail(_topLists[index]);
      final songs = <MusicItem>[];
      for (final raw in detail.take(kHomeChartPreview)) {
        try {
          songs.add(MusicItem.fromJson(raw));
        } catch (_) {}
      }
      if (mounted) setState(() => _hotSongs = songs);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _recLoading = false);
    }
  }

  /// 播放历史里的条目可能是旧数据,解析失败就跳过(不炸整页)。
  MusicItem? _safeItem(Map<String, dynamic> raw) {
    try {
      return MusicItem.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  /// 「最近播放」展示用的列表(最多 3 条)。
  ///
  /// 供各回调(播放/下载/删除)按 UI 下标取歌 —— 与展示用的是同一套规则,
  /// 避免"显示 3 条、按下标却删到别的歌"。
  List<MusicItem> _recentPlaysOf(WidgetRef ref) => [
    for (final e in ref.read(playHistoryProvider).take(3))
      if (_safeItem(e) != null) _safeItem(e)!,
  ];

  /// 播放首页推荐里的第 index 首。
  void _playRecommended(List<MusicItem> songs, int index) {
    ref.read(playerControllerProvider.notifier).playFromList(songs, index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 实际生效的音源:选中的源已被改名/卸载时自动回落「自动」,
  /// 避免继续用它搜索直接报 plugin not installed。
  String? get _effectiveSource {
    final installed =
        ref.read(pluginListProvider).value?.map((p) => p.platform).toSet() ??
            const <String>{};
    return effectiveSearchSource(
      selected: ref.read(searchSourceProvider),
      installedPlatforms: installed,
    );
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
        .search(keyword, source: _effectiveSource);
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
    // 音源变化时重载推荐:推荐只在 initState 加载一次,用户装完音源若不重启,
    // 首页会一直停在静态兜底卡(实测问题)。这里监听插件列表变化后重试。
    ref.listen(pluginListProvider, (_, next) {
      final count = next.value?.length ?? 0;
      if (count > 0 && (_hotSongs.isEmpty || _guessSongs.isEmpty)) {
        _recCache.clear();
        _loadRecommendations();
      }
    });
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
                // 音源切换条已移除:默认「自动」会按健康度挑最快且能拿到完整曲的源;
                // 需要指定某个源时到「设置 → 音乐源 → 默认音源」。
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
                      // 聚焦且未搜索时,历史下拉已展示历史;隐藏 IdleView,
                      // 避免其历史区与下拉重复、造成"历史项无法选中"的混淆。
                      : (_dropdownOpen
                            ? const SizedBox.shrink()
                            : _IdleView(
                                history: ref.watch(searchHistoryProvider),
                                suggestions: _suggestions,
                                hotSongs: _hotSongs,
                                guessSongs: _guessSongs,
                                recLoading: _recLoading,
                                topLists: _topLists,
                                topListIndex: _topListIndex,
                                onPickTopList: _switchTopList,
                                // 「查看全部」→ 完整榜单列表页(可滑动浏览选歌)
                                onOpenChart: (i) {
                                  if (i < 0 || i >= _topLists.length) return;
                                  openChartDetail(context, ref, _topLists[i]);
                                },
                                // 下拉刷新:忽略缓存重新拉取榜单与推荐
                                onRefresh: () =>
                                    _loadRecommendations(force: true),
                                // 用 watch 的值作数据源:清空/删除「最近播放」
                                // 后本页会重建,列表随之更新(只 read 不会刷新)。
                                recentPlays: [
                                  for (final e
                                      in ref.watch(playHistoryProvider).take(3))
                                    if (_safeItem(e) != null) _safeItem(e)!,
                                ],
                                onDownloadRecent: (i) {
                                  final list = _recentPlaysOf(ref);
                                  if (i < 0 || i >= list.length) return;
                                  showDownloadPicker(context, ref, list[i]);
                                },
                                onDownloadSong: (song) =>
                                    showDownloadPicker(context, ref, song),
                                onAddSong: (song) =>
                                    showPlaylistPicker(context, ref, song),
                                onPlayRecent: (i) =>
                                    _playRecommended(_recentPlaysOf(ref), i),
                                // 清空整个「最近播放」(用户诉求)
                                onClearRecentPlays: () => ref
                                    .read(playHistoryProvider.notifier)
                                    .clear(),
                                // 移除单首:UI 下标只针对**展示出来的那几条**,
                                // 这里统一用同一个取值函数换算,避免删错歌。
                                onRemoveRecent: (i) {
                                  final shown = _recentPlaysOf(ref);
                                  if (i < 0 || i >= shown.length) return;
                                  final t = shown[i];
                                  ref
                                      .read(playHistoryProvider.notifier)
                                      .removeEntry({
                                    'id': t.id,
                                    'platform': t.platform,
                                    'songId': t.songId,
                                    'title': t.title,
                                  });
                                },
                                onPlayHot: (i) => _playRecommended(_hotSongs, i),
                                onPlayGuess: (i) =>
                                    _playRecommended(_guessSongs, i),
                                onPick: _pickSuggestion,
                                onClearHistory: () => ref
                                    .read(searchHistoryProvider.notifier)
                                    .clear(),
                                onOpenPlugins: widget.onOpenPlugins,
                              )),
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
              // 用 onTapDown 提前触发:点击历史项时 TextField 会先失焦,导致
              // _dropdownOpen 立即置 false、下拉框在 onTap(抬手)前被移除,
              // 使 onTap 无法命中(真实设备有 down/up 时间间隔)。onTapDown 在
              // 按下瞬间即选中,不受失焦重建影响。
              onTapDown: (_) => onPick(kw),
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


/// 空闲态:欢迎语 + 最近搜索 + 热门推荐 + 插件引导。
class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.history,
    required this.suggestions,
    required this.onPick,
    required this.onClearHistory,
    this.onOpenPlugins,
    this.hotSongs = const [],
    this.guessSongs = const [],
    this.recLoading = false,
    this.onPlayHot,
    this.onPlayGuess,
    this.topLists = const [],
    this.topListIndex = 0,
    this.onPickTopList,
    this.onOpenChart,
    this.onRefresh,
    this.recentPlays = const [],
    this.onPlayRecent,
    this.onDownloadRecent,
    this.onClearRecentPlays,
    this.onRemoveRecent,
    this.onDownloadSong,
    this.onAddSong,
  });

  final List<String> history;
  final List<String> suggestions;

  /// 动态推荐:真实音源的热歌榜与「猜你喜欢」(方案 C)。
  final List<MusicItem> hotSongs;
  final List<MusicItem> guessSongs;
  final bool recLoading;
  final ValueChanged<int>? onPlayHot;
  final ValueChanged<int>? onPlayGuess;
  final List<Map<String, dynamic>> topLists;
  final int topListIndex;
  final ValueChanged<int>? onPickTopList;

  /// 打开第 index 个榜单的**完整列表页**(可上下滑动浏览选歌)。
  final ValueChanged<int>? onOpenChart;

  /// 下拉刷新:重新拉取榜单与推荐。为 null 时不启用下拉刷新。
  final Future<void> Function()? onRefresh;

  /// 最近播放(原「音乐由插件驱动」卡片的替代,用户诉求)。
  final List<MusicItem> recentPlays;
  final ValueChanged<int>? onPlayRecent;
  final ValueChanged<int>? onDownloadRecent;

  /// 清空整个「最近播放」列表。
  final VoidCallback? onClearRecentPlays;

  /// 移除「最近播放」里的单首(按下标)。
  final ValueChanged<int>? onRemoveRecent;

  /// 下载指定歌曲(榜单卡片长按菜单用)。
  final ValueChanged<MusicItem>? onDownloadSong;
  final ValueChanged<MusicItem>? onAddSong;
  final ValueChanged<String> onPick;
  final VoidCallback onClearHistory;
  final VoidCallback? onOpenPlugins;

  static const List<LinearGradient> _cardGradients = [
    LinearGradient(colors: [Color(0xFFE0324A), Color(0xFFC4343F)]),
    LinearGradient(colors: [Color(0xFFFA3B4D), Color(0xFFE0324A)]),
    LinearGradient(colors: [Color(0xFFFF7A85), Color(0xFFFA3B4D)]),
  ];

  /// 当前选中榜单的名称(用于区块标题)。
  ///
  /// 取不到时回落到「热门推荐」,保持旧观感不变。
  String get _currentChartName {
    if (topLists.isEmpty) return '热门推荐';
    if (topListIndex < 0 || topListIndex >= topLists.length) return '热门推荐';
    final title = '${topLists[topListIndex]['title'] ?? ''}'.trim();
    return title.isEmpty ? '热门推荐' : title;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final list = ListView(
      // 下拉刷新需要列表本身可滚动:内容不足一屏时也要能下拉,
      // 因此始终给 AlwaysScrollableScrollPhysics。
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 0, 24),
      children: [
        // 动态热歌榜(真实音源排行榜);拉不到时退回下面的静态关键词卡
        if (topLists.isNotEmpty) ...[
          _SectionTitle('排行榜', icon: Icons.local_fire_department_rounded),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 20),
              itemCount: topLists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == topListIndex;
                return _TopListChip(
                  label: '${topLists[i]['title'] ?? '榜单'}',
                  selected: selected,
                  onTap: () => onPickTopList?.call(i),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (hotSongs.isNotEmpty) ...[
          // 标题显示**当前实际榜单名**(如「酷我热歌榜」),而不是笼统的
          // 「热门推荐」—— 否则切换榜单后标题不变,用户分不清在看哪个榜,
          // 会觉得「新歌不是新歌」。
          // 右侧「查看全部」进入完整榜单页(30 首,可上下滑动浏览选歌)。
          _SectionTitle(
            _currentChartName,
            icon: Icons.local_fire_department_rounded,
            onMore: onOpenChart == null
                ? null
                : () => onOpenChart!(topListIndex),
          ),
          const SizedBox(height: 12),
          // 首页只放少量预览(列表形式,比卡片网格省空间);
          // 完整榜单走右上角「查看全部」。
          _ChartList(
            songs: hotSongs.take(kHomeChartPreview).toList(),
            onPlay: onPlayHot,
            onDownloadSong: onDownloadSong,
            onAddSong: onAddSong,
          ),
          const SizedBox(height: 24),
        ],
        if (guessSongs.isNotEmpty) ...[
          _SectionTitle('猜你喜欢', icon: Icons.auto_awesome_rounded),
          const SizedBox(height: 12),
          // 猜你喜欢同样用列表,保持与上方榜单一致的观感
          _ChartList(
            songs: guessSongs.take(kHomeChartPreview).toList(),
            onPlay: onPlayGuess,
            onDownloadSong: onDownloadSong,
            onAddSong: onAddSong,
          ),
          const SizedBox(height: 24),
        ],
        if (hotSongs.isEmpty && recLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (hotSongs.isEmpty && !recLoading) ...[
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
        ],
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
        if (recentPlays.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              _SectionTitle('最近播放', icon: Icons.history_rounded),
              const Spacer(),
              // 与「最近搜索」保持一致:整个列表可一键清空(用户诉求)。
              InkWell(
                onTap: onClearRecentPlays,
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
          const SizedBox(height: 8),
          for (var i = 0; i < recentPlays.length; i++)
            _RecentPlayRow(
              song: recentPlays[i],
              onTap: () => onPlayRecent?.call(i),
              onDownload: () => onDownloadRecent?.call(i),
              // 单首移除
              onRemove: () => onRemoveRecent?.call(i),
            ),
        ] else if (onOpenPlugins != null) ...[
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

    // 没有刷新回调时不套 RefreshIndicator,避免下拉出现"永远转不完"的指示器。
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// 榜单芯片(热歌榜/飙升榜/新歌榜…)。
class _TopListChip extends StatelessWidget {
  const _TopListChip({
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
      color: selected ? scheme.primary : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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

/// 最近播放行:替代原「音乐由插件驱动」卡片(用户诉求)。
class _RecentPlayRow extends ConsumerWidget {
  const _RecentPlayRow({
    required this.song,
    required this.onTap,
    required this.onDownload,
    this.onRemove,
  });

  final MusicItem song;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  /// 从「最近播放」移除这一首;为 null 时不显示删除按钮。
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final downloaded = ref
        .watch(downloadControllerProvider)
        .any((d) => d.song.id == song.id && d.song.platform == song.platform);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 40,
                height: 40,
                color: scheme.surfaceContainerHighest,
                child: song.artwork == null || song.artwork!.isEmpty
                    ? Icon(
                        Icons.music_note_rounded,
                        size: 18,
                        color: scheme.outline,
                      )
                    : Image.network(
                        song.artwork!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.music_note_rounded,
                          size: 18,
                          color: scheme.outline,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    song.artist ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // 最近播放也支持下载(刚听完想存下来的场景很常见)
            IconButton(
              tooltip: downloaded ? '已下载' : '下载',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                downloaded
                    ? Icons.check_circle_rounded
                    : Icons.download_rounded,
                color: scheme.onSurfaceVariant,
              ),
              onPressed: onDownload,
            ),
            // 单首移除(用户诉求:不想要的记录可以单独删掉)
            if (onRemove != null)
              IconButton(
                tooltip: '从最近播放中移除',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close_rounded,
                  color: scheme.outline,
                ),
                onPressed: onRemove,
              ),
            Icon(
              Icons.play_arrow_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 榜单/推荐的歌曲列表(替代原卡片网格)。
///
/// 为什么改成列表:排行榜本质是"歌单式"浏览,卡片网格每行只放 2-3 首、
/// 封面占掉大半高度,首页被拉得很长(用户反馈"卡片好占地方")。
/// 列表每条一行、信息密度更高,且与搜索结果共用 [SongTile],观感统一。
class _ChartList extends StatelessWidget {
  const _ChartList({
    required this.songs,
    required this.onPlay,
    this.onDownloadSong,
    this.onAddSong,
  });

  final List<MusicItem> songs;
  final ValueChanged<int>? onPlay;
  final ValueChanged<MusicItem>? onDownloadSong;
  final ValueChanged<MusicItem>? onAddSong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // 右侧留白与页面其他区块一致(ListView 的 padding 只管左侧)
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        children: [
          for (var i = 0; i < songs.length; i++)
            _ChartRow(
              // 用 platform+id 做 key:切换榜单时列表项能正确复用/替换
              key: ValueKey(
                '${songs[i].platform}|${songs[i].id}|$i',
              ),
              index: i,
              song: songs[i],
              onTap: onPlay == null ? null : () => onPlay!(i),
              onDownload: onDownloadSong == null
                  ? null
                  : () => onDownloadSong!(songs[i]),
              onAdd: onAddSong == null ? null : () => onAddSong!(songs[i]),
              rankColor: scheme.primary,
            ),
        ],
      ),
    );
  }
}

/// 榜单行:序号 + 歌曲信息 + 操作。
///
/// 榜单带序号(1/2/3…)是排行榜的惯例,能一眼看出名次 —— 卡片网格做不到这点。
class _ChartRow extends StatelessWidget {
  const _ChartRow({
    super.key,
    required this.index,
    required this.song,
    required this.onTap,
    this.onDownload,
    this.onAdd,
    required this.rankColor,
  });

  final int index;
  final MusicItem song;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;
  final VoidCallback? onAdd;
  final Color rankColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // 前三名用品牌色强调,其余用弱化色
    final isTop3 = index < 3;
    return Row(
      children: [
        SizedBox(
          width: 26,
          child: Text(
            '${index + 1}',
            textAlign: TextAlign.center,
            style: textTheme.labelMedium?.copyWith(
              color: isTop3 ? rankColor : scheme.outline,
              fontWeight: isTop3 ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: SongTile(
            song: song,
            onTap: onTap,
            onDownload: onDownload,
            onAdd: onAdd,
          ),
        ),
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
    // 仅「首屏加载」才整页转圈;翻页(loadMore)时列表保持可见,尾部小加载器,
    // 避免每次上滑加载下一页整页闪白。
    if (state.loading && state.results.isEmpty) {
      return _LoadingView(query: state.query);
    }
    if (state.error != null && state.results.isEmpty) {
      return _ErrorView(error: state.error!, onRetry: widget.onRetry);
    }
    if (state.results.isEmpty) return _EmptyResultView(query: state.query);

    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // 列表尾部:翻页中显示小加载器;没有更多时显示「已加载全部」
    final footerCount =
        (state.loadingMore || state.isEnd) && !state.loading ? 1 : 0;

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
                  foregroundColor: scheme.primary,
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
            itemCount: state.results.length + footerCount,
            itemBuilder: (context, index) {
              if (index >= state.results.length) {
                return _ListFooter(
                  loadingMore: state.loadingMore,
                  isEnd: state.isEnd,
                  total: state.results.length,
                );
              }
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

/// 列表尾部:翻页小加载器 / 已加载全部提示(不替换列表,无感加载)。
class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.loadingMore,
    required this.isEnd,
    required this.total,
  });

  final bool loadingMore;
  final bool isEnd;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: loadingMore
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '加载中…',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : Text(
                '已加载全部 $total 首',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.outline,
                ),
              ),
      ),
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
  const _SectionTitle(this.text, {this.icon, this.onMore});

  final String text;
  final IconData? icon;

  /// 提供时在右侧显示「查看全部 ›」入口(用于进入榜单完整列表页)。
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);

    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );

    // 无入口时只返回标题本身:mainAxisSize.min + Flexible 的 Row 可以安全地
    // 嵌在别的 Row 里(如「最近播放」那行自己带 Spacer + 清空按钮)。
    if (onMore == null) return title;

    // 带「查看全部」入口时必须独占一行:内部用了 Spacer/Expanded 之类的
    // 弹性布局,嵌进外层 Row 会因宽度约束无界而崩(RenderFlex 断言)。
    return Row(
      children: [
        Flexible(child: title),
        const Spacer(),
        InkWell(
          onTap: onMore,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '查看全部',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        // 入口右侧留出与页面一致的边距(ListView 的 padding 只管左侧)
        const SizedBox(width: 20),
      ],
    );
  }
}
