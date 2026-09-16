import 'dart:io';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/updater/app_flavor.dart';
import 'package:musicx/core/plugins/plugin_info.dart';
import 'package:musicx/core/search/source_selection.dart';
import 'package:musicx/core/providers.dart'
    show pluginManagerProvider, pluginListProvider;
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/models/plugin_source.dart';
import 'package:musicx/theme/app_theme.dart';
import 'package:musicx/core/plugins/bundled_install.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';
import 'package:musicx/ui/desktop_lyrics/desktop_lyrics_service.dart';
import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'package:musicx/ui/plugins/lyrics_settings_page.dart';
import 'package:musicx/core/updater/apk_installer.dart';
import 'package:musicx/core/updater/update_controller.dart';
import 'package:musicx/ui/plugins/update_row.dart';

/// 安装入口类型。
enum _InstallAction { bundled, url, source, file }

/// 设置页左右栏的区块:左侧菜单项,右侧对应内容。
enum _SettingsSection { sources, appearance, general }

/// 插件管理页:卡片式列表 + 安装/卸载。
class PluginPage extends ConsumerStatefulWidget {
  const PluginPage({super.key});

  @override
  ConsumerState<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends ConsumerState<PluginPage> {
  final TextEditingController _pathCtrl = TextEditingController();
  int _reload = 0;
  _SettingsSection _section = _SettingsSection.sources;
  Future<List<PluginInfo>>? _pluginsFuture;

  /// 缓存插件列表 future:setState(切换左右栏区块)不重建,避免出现
  /// 无限旋转的 CircularProgressIndicator 导致 pumpAndSettle 超时。
  /// 注意必须**同步返回同一个 future**,不能是 async 函数(每次调用都会
  /// 产生新 future,FutureBuilder 会一直处于 loading)。
  Future<List<PluginInfo>> _loadPlugins() =>
      _pluginsFuture ??= ref.read(pluginManagerProvider).listPlugins();

  /// 后台算一次内置音源待处理数(未安装 + 版本不同),用于分组行角标。
  Future<void> _refreshBundledPending(List<PluginInfo> installed) async {
    final bundled = await BundledPluginCatalog().list();
    if (bundled.isEmpty) return;
    final pending = pendingBundledPlugins(
      bundled: bundled,
      installedVersions: {for (final p in installed) p.platform: p.version},
    ).length;
    if (!mounted) return;
    // 内置平台名集合必须在启动路径就填好:否则音源列表与默认音源选择器会把
    // 内置音源当成用户音源显示出来(单测抓到的疏漏)。
    setState(() {
      _bundledPlatforms = {for (final p in bundled) p.platform};
      _bundledPending = pending;
    });
  }

  @override
  void initState() {
    super.initState();
    // 首帧后算一次「内置音源待处理数」(角标),不阻塞页面加载。
    Future.microtask(() async {
      final plugins = await _loadPlugins();
      await _refreshBundledPending(plugins);
    });
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _installFromPath() async {
    _pathCtrl.clear();
    final messenger = ScaffoldMessenger.of(context);
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('安装本地插件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('输入插件 .js 文件的本地路径,安装后即可在搜索中使用。'),
            const SizedBox(height: 14),
            TextField(
              controller: _pathCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '/path/to/plugin.js',
                prefixIcon: Icon(Icons.insert_drive_file_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _pathCtrl.text),
            child: const Text('安装'),
          ),
        ],
      ),
    );
    if (path == null || path.trim().isEmpty) return;
    try {
      await ref.read(pluginManagerProvider).installFromFile(path.trim());
      if (mounted) setState(() => _reload++);
      _bumpPluginList();
      messenger.showSnackBar(const SnackBar(content: Text('插件安装成功')));
    } catch (e) {
      if (mounted) setState(() => _reload++);
      messenger.showSnackBar(SnackBar(content: Text('安装失败:$e')));
    }
  }

  /// 在线安装:输入插件 JS 的 URL。
  Future<void> _installFromUrl() async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('在线安装插件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('输入插件 JS 文件的下载地址,自动下载并安装。'),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://example.com/plugin/index.js',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('安装'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      final manager = ref.read(pluginManagerProvider);
      final info = await manager.installFromUrl(url);
      if (!mounted) return;
      setState(() => _reload++);
      _bumpPluginList();
      messenger.showSnackBar(
        SnackBar(content: Text('已安装插件「${info.platform}」v${info.version}')),
      );
    } catch (e) {
      if (mounted) setState(() => _reload++);
      messenger.showSnackBar(SnackBar(content: Text('安装失败:$e')));
    }
  }

  /// 内置音源待处理数(未安装 + 版本不同),用于音乐源分组行的角标。
  int _bundledPending = 0;

  /// 随 App 内置的音源平台名:装好后不再出现在音源列表/默认音源选择器里。
  Set<String> _bundledPlatforms = <String>{};

  /// 读取已安装音源的 platform → version。
  Future<Map<String, String>> _installedVersions() async {
    final manager = ref.read(pluginManagerProvider);
    return {for (final p in await manager.listPlugins()) p.platform: p.version};
  }

  /// 刷新「内置音源待处理数」角标。
  Future<void> _syncBundledPending() async {
    final bundled = await BundledPluginCatalog().list();
    if (bundled.isEmpty) return;
    if (mounted) {
      setState(() {
        _bundledPlatforms = {for (final p in bundled) p.platform};
      });
    }
    final pending = pendingBundledPlugins(
      bundled: bundled,
      installedVersions: await _installedVersions(),
    ).length;
    if (mounted && pending != _bundledPending) {
      setState(() => _bundledPending = pending);
    } else {
      _bundledPending = pending;
    }
  }

  /// 覆盖安装前先移除同平台旧插件,避免同平台出现多个插件文件。
  Future<bool> _confirmOverwrite(List<BundledPlugin> plugins) async {
    final manager = ref.read(pluginManagerProvider);
    final installed = await manager.listPlugins();
    if (!mounted) return false;
    final clash = installed
        .where((p) => plugins.any((b) => b.platform == p.platform))
        .toList();
    if (clash.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('已有 ${clash.length} 个同平台音源'),
        content: Text(
          '将覆盖安装:${clash.map((p) => p.platform).join('、')}。'
          '覆盖会先移除旧版本。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('覆盖安装'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    for (final old in clash) {
      await manager.uninstall(old);
    }
    return true;
  }

  /// 一键「下载音源」:把所有未安装/可更新的内置音源装好。
  ///
  /// 已是最新的直接跳过;只有在需要覆盖同平台已有插件时才弹一次确认,
  /// 其余全自动,装完给一条汇总提示。
  Future<void> _downloadBundledSources() async {
    final messenger = ScaffoldMessenger.of(context);
    final manager = ref.read(pluginManagerProvider);
    final catalog = BundledPluginCatalog();

    final bundled = await catalog.list();
    if (!mounted) return;
    if (bundled.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('内置音源清单为空')));
      return;
    }

    final pending = pendingBundledPlugins(
      bundled: bundled,
      installedVersions: await _installedVersions(),
    );
    if (pending.isEmpty) {
      await _syncBundledPending();
      messenger.showSnackBar(const SnackBar(content: Text('音源已是最新,无需重复安装')));
      return;
    }

    if (!await _confirmOverwrite(pending)) return;

    final result = await installBundledPlugins(
      manager: manager,
      catalog: catalog,
      plugins: pending,
    );
    final done = result.installed.map((p) => p.name).toList();
    final failed = result.failed.map((p) => p.name).toList();

    if (!mounted) return;
    setState(() => _reload++);
    _bumpPluginList();
    await _syncBundledPending();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? '已安装 ${done.length} 个音源:${done.join('、')}'
              : '已安装 ${done.length} 个;失败 ${failed.length} 个:${failed.join('、')}',
        ),
      ),
    );
  }

  /// 内置音源明细面板(查看版本/单独安装或更新)。
  /// 订阅源导入:输入 plugins.json 地址,列出可选插件。
  Future<void> _importFromSource() async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入订阅源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('输入订阅源地址(plugins.json),浏览并安装其中插件。'),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://example.com/plugins.json',
                prefixIcon: Icon(Icons.rss_feed_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('获取列表'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;

    final manager = ref.read(pluginManagerProvider);
    final List<PluginSource> sources;
    try {
      sources = await manager.fetchPluginSources(url);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('订阅源加载失败:$e')));
      return;
    }
    if (!mounted) return;
    // 已安装集合,用于列表状态展示
    final installed = <String>{};
    for (final p in await manager.listPlugins()) {
      installed.add(p.platform);
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SourceSheet(
        sources: sources,
        installed: installed,
        onInstall: (source) async {
          try {
            final info = await manager.installFromUrl(source.url);
            if (!mounted) return;
            setState(() => _reload++);
            _bumpPluginList();
            messenger.showSnackBar(
              SnackBar(content: Text('已安装插件「${info.platform}」')),
            );
          } catch (e) {
            if (!mounted) return;
            messenger.showSnackBar(SnackBar(content: Text('安装失败:$e')));
          }
        },
      ),
    );
  }

  Future<void> _uninstall(PluginInfo p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('卸载插件“${p.platform}”?'),
        content: const Text('卸载后将无法再通过该插件搜索和播放音乐。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final manager = ref.read(pluginManagerProvider);
    await manager.uninstall(p);
    if (mounted) setState(() => _reload++);
    _bumpPluginList();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已卸载插件')));
  }

  /// 编辑已安装音源:修改音源名称与订阅地址(srcUrl),保存后立即生效。
  Future<void> _editPlugin(PluginInfo p) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({String name, String srcUrl})>(
      context: context,
      builder: (_) =>
          _EditSourceDialog(name: p.platform, srcUrl: p.srcUrl ?? ''),
    );
    if (result == null) return;
    try {
      await ref
          .read(pluginManagerProvider)
          .updatePlugin(p, name: result.name, srcUrl: result.srcUrl);
      // 改名后当前选中的源要跟着迁移,否则搜索会指着已不存在的平台名。
      final migrated = migrateSelectedSource(
        selected: ref.read(searchSourceProvider),
        from: p.platform,
        to: result.name,
      );
      ref.read(searchSourceProvider.notifier).select(migrated);
      if (mounted) setState(() => _reload++);
      _bumpPluginList();
      messenger.showSnackBar(const SnackBar(content: Text('音源信息已更新')));
    } catch (e) {
      if (mounted) setState(() => _reload++);
      messenger.showSnackBar(SnackBar(content: Text('更新失败:$e')));
    }
  }

  /// 弹出默认音源选择器(自动 + 已装插件)。
  Future<void> _pickDefaultSource(
    List<PluginInfo> plugins,
    String? current,
  ) async {
    const autoMark = '__auto__';
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;
        final maxH = MediaQuery.of(ctx).size.height * 0.7;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Text(
                    '默认音源',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.auto_awesome_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                  title: const Text('自动'),
                  subtitle: Text(
                    '按顺序尝试所有已装音源',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: current == null
                      ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, autoMark),
                ),
                // 插件列表可滚动,避免音源多时弹窗底部溢出
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in plugins)
                        ListTile(
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: AppTheme.softGradient,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.extension_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          title: Text(p.platform),
                          subtitle: Text(
                            'v${p.version}',
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: current == p.platform
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: scheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(ctx, p.platform),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    ref
        .read(searchSourceProvider.notifier)
        .select(picked == autoMark ? null : picked);
  }

  /// 测试音源可用性:搜索 + 解析,结果以 SnackBar 展示。
  Future<void> _testPlugin(PluginInfo p) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('正在测试「${p.platform}」…')));
    try {
      final result = await ref
          .read(pluginManagerProvider)
          .testPlugin(p.platform);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                result.ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: result.ok ? const Color(0xFF34D399) : Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('「${p.platform}」${result.detail}')),
            ],
          ),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('「${p.platform}」测试失败:$e')));
    }
  }

  /// 插件列表已变更:使缓存的插件列表失效,下次读取时重新扫描。
  void _bumpPluginList() {
    _pluginsFuture = null;
    ref.invalidate(pluginListProvider);
  }

  /// 进入音源管理二级页(插件卡片列表 + 安装/编辑/卸载/测试)。
  void _openSourceManager(List<PluginInfo> plugins) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SourceManagerPage(
          plugins: plugins,
          current: ref.read(searchSourceProvider),
          onEdit: _editPlugin,
          onDelete: _uninstall,
          onTest: _testPlugin,
          onInstallUrl: _installFromUrl,
          onInstallPath: _installFromPath,
          onInstallSource: _importFromSource,
          onInstallBundled: _downloadBundledSources,
        ),
      ),
    );
  }

  /// 当前选中区块的内容(宽屏右侧)。
  List<Widget> _sectionContent(
    _SettingsSection section,
    List<PluginInfo> plugins,
    String? source,
  ) {
    switch (section) {
      case _SettingsSection.sources:
        // 内置音源(腾讯/网易/酷我)是随 App 自带的实现细节:装好后不再出现在
        // 音源列表里,只留一条「内置音源:已安装 N」的状态;列表与默认音源
        // 选择器只展示用户自己装的音源(用户诉求)。
        final userPlugins = [
          for (final p in plugins)
            if (!_bundledPlatforms.contains(p.platform)) p,
        ];
        return [
          // 没有任何音源(含内置)时,在分组内显示引导卡片而不是整页替换,
          // 否则「通用 → 检查更新 / 关于(版本号)」会一起消失。
          if (plugins.isEmpty) ...[
            _EmptyPlugins(
              onInstall: _installFromUrl,
              onDownloadBundled: _downloadBundledSources,
            ),
            const SizedBox(height: 16),
          ],
          _SettingsGroup(
            title: '音乐源',
            children: [
              _DefaultSourceRow(
                current: source,
                onTap: () => _pickDefaultSource(userPlugins, source),
              ),
              const SizedBox(height: 8),
              _FilterCoversRow(),
              // 内置音源(App 自带的腾讯/网易/酷我)完全不在设置页显示:
              // 既没有「内置音源」行,也不会出现在「已安装音源」列表与
              // 「默认音源」选择器里 —— 用户明确要求只看到自己装的音源。
              //
              // 「已安装音源」行只在用户自己装了音源时出现;一个都没有时
              // 显示「0」既无意义也容易让人以为内置源是用户装的。
              if (userPlugins.isNotEmpty) ...[
                const SizedBox(height: 8),
                _MenuItemRow(
                  icon: Icons.library_music_rounded,
                  title: '已安装音源',
                  trailing: '${userPlugins.length}',
                  onTap: () => _openSourceManager(userPlugins),
                ),
              ],
            ],
          ),
        ];
      case _SettingsSection.appearance:
        final lyrics = ref.watch(desktopLyricsSettingsProvider);
        return [
          _SettingsGroup(
            title: '外观',
            children: [
              _AppearanceSection(),
              if (DesktopLyricsService.supported)
                _MenuItemRow(
                  icon: Icons.lyrics_rounded,
                  title: '桌面歌词',
                  trailing:
                      '${lyrics.cardStyle == LyricsCardStyle.plain ? '纯文字' : '毛玻璃'}'
                      ' · ${lyrics.fontSize.round()}px',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LyricsSettingsPage(),
                    ),
                  ),
                ),
            ],
          ),
        ];
      case _SettingsSection.general:
        return [
          _SettingsGroup(
            title: '通用',
            children: [
              const UpdateRow(),
              const SizedBox(height: 8),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 8),
                _MenuItemRow(
                  icon: Icons.restart_alt_rounded,
                  title: '重启应用',
                  trailing: '安装新版本后点这里',
                  onTap: () => ApkInstaller.restartApp(),
                ),
              ],
              const SizedBox(height: 8),
              const _AboutCard(),
              const BlessingCard(),
            ],
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          PopupMenuButton<_InstallAction>(
            tooltip: '安装插件',
            icon: const Icon(Icons.add_rounded),
            onSelected: (action) => switch (action) {
              _InstallAction.bundled => _downloadBundledSources(),
              _InstallAction.url => _installFromUrl(),
              _InstallAction.source => _importFromSource(),
              _InstallAction.file => _installFromPath(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _InstallAction.bundled,
                child: ListTile(
                  leading: Icon(Icons.widgets_rounded),
                  title: Text('下载音源'),
                  subtitle: Text('App 内置,一键安装'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _InstallAction.url,
                child: ListTile(
                  leading: Icon(Icons.link_rounded),
                  title: Text('在线安装'),
                  subtitle: Text('输入插件 JS 的 URL'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _InstallAction.source,
                child: ListTile(
                  leading: Icon(Icons.rss_feed_rounded),
                  title: Text('导入订阅源'),
                  subtitle: Text('浏览 plugins.json 中的插件'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _InstallAction.file,
                child: ListTile(
                  leading: Icon(Icons.insert_drive_file_outlined),
                  title: Text('本地文件'),
                  subtitle: Text('从磁盘路径安装'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<PluginInfo>>(
        key: ValueKey<int>(_reload),
        future: _loadPlugins(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final plugins = snapshot.data ?? const [];
          // 无插件不再整页替换(见 _sectionContent):保留「通用」分组,
          // 否则检查更新与版本号入口会一起消失。
          final source = ref.watch(searchSourceProvider);
          // 自适应:宽屏左右栏(左侧菜单 + 右侧内容),窄屏单列
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final content = Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 760 : 640),
                  child: ListView(
                    // 底部留出导航栏高度:此前「通用」分组(检查更新/关于)
                    // 被底部导航遮住(真机截图发现)。
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      // 导航栏高度 + 安全区:最后一个分组不再贴着底部
                      24 +
                          88 +
                          MediaQuery.of(context).viewPadding.bottom,
                    ),
                    children: [
                      _ProfileCard(
                        pluginCount: plugins.length,
                        onInstall: _installFromUrl,
                      ),
                      const SizedBox(height: 22),
                      // 宽屏:左侧菜单切换,只显示选中区块。
                      // 窄屏(手机):没有侧边栏,必须堆叠显示全部分组 ——
                      // 此前误用 _section 导致「外观/通用(检查更新·版本号)」
                      // 在手机上完全进不去(用户反馈设置里找不到更新检查)。
                      if (wide)
                        ..._sectionContent(_section, plugins, source)
                      else ...[
                        ..._sectionContent(
                          _SettingsSection.sources,
                          plugins,
                          source,
                        ),
                        const SizedBox(height: 20),
                        ..._sectionContent(
                          _SettingsSection.appearance,
                          plugins,
                          source,
                        ),
                        const SizedBox(height: 20),
                        ..._sectionContent(
                          _SettingsSection.general,
                          plugins,
                          source,
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              );
              if (!wide) return content;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsSidebar(
                    selected: _section,
                    onSelect: (s) => setState(() => _section = s),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// 外观切换:浅色 / 深色(持久化到设置文件)。
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themePreferenceProvider);
    final notifier = ref.read(themePreferenceProvider.notifier);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(4),
      child: SegmentedButton<ThemeMode>(
        emptySelectionAllowed: false,
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            label: Text('浅色'),
            icon: Icon(Icons.light_mode_outlined),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            label: Text('深色'),
            icon: Icon(Icons.dark_mode_outlined),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (s) {
          if (s.contains(ThemeMode.dark)) {
            notifier.setDark();
          } else {
            notifier.setLight();
          }
        },
      ),
    );
  }
}

/// 顶部品牌条(瘦身版):图标 + 名称 + 版本号 + 插件数。
///
/// 原先是一张高约 100 的大渐变卡,占位多、把设置项挤到下面;改为一行矮条,
/// 只在最需要时提供信息(用户诉求:设置页看着乱)。
class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({required this.pluginCount, required this.onInstall});

  final int pluginCount;
  final VoidCallback onInstall;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  String? _version;

  @override
  void initState() {
    super.initState();
    ref.read(updateServiceProvider).resolveCurrentVersion().then((v) {
      if (mounted && v.isNotEmpty && v != '0.0.0') setState(() => _version = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: widget.onInstall,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  color: scheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MusicX',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _version == null ? '插件化音乐播放器' : 'v$_version',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${widget.pluginCount} 个音源',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.outline,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle2 extends StatelessWidget {
  const _SectionTitle2(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

/// 关于信息卡。
class _AboutCard extends ConsumerStatefulWidget {
  const _AboutCard();

  @override
  ConsumerState<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends ConsumerState<_AboutCard> {
  String? _version;

  @override
  void initState() {
    super.initState();
    // 安卓必须异步解析版本号(同步 API 只认 macOS Info.plist)
    ref.read(updateServiceProvider).resolveCurrentVersion().then((v) {
      if (mounted && v.isNotEmpty && v != '0.0.0') setState(() => _version = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '关于 MusicX',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // 版本号:用户此前在应用里找不到
              Text(
                _version == null ? '' : 'v$_version',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '插件协议兼容 MusicFree · 播放器本体不含音源',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置页底部的寄语卡片(吴玫静版专属)。
///
/// 设计要点:
/// - 品牌红渐变 + 柔和高光,作为整页唯一的"装饰性"元素;
/// - 深浅色两套配色都保证对比度(渐变上统一用白字);
/// - 纯展示、不可点,避免用户误以为能交互;
/// - **只在吴玫静版展示**,标准版设置页不出现该卡片。
///
/// 展示规则由**构建变体**决定(见 app_flavor.dart),与运行平台无关。
/// 保留 [visibleOverride] 供测试覆盖:测试宿主的变体未必是吴玫静版,
/// 否则渲染类断言永远无法执行。
class BlessingCard extends StatelessWidget {
  const BlessingCard({super.key, this.visibleOverride});

  /// 仅供测试:强制显示/隐藏,绕过变体判断。
  final bool? visibleOverride;

  /// 展示规则:仅吴玫静版。
  static bool isVisibleIn(AppFlavor flavor) => flavor.showsBlessingCard;

  static const String line1 = '玫风入怀,静享喜乐,日日有甜。';

  /// 右下角署名。
  static const String signature = '---吴玫静';

  @override
  Widget build(BuildContext context) {
    final visible = visibleOverride ?? isVisibleIn(currentFlavor);
    if (!visible) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 深色模式整体压暗一档,避免在深色页面上过亮刺眼。
    final gradient = LinearGradient(
      colors: isDark
          ? const [Color(0xFF8E2A38), Color(0xFFB93044)]
          : const [Color(0xFFC4343F), Color(0xFFFA3B4D)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFA3B4D).withValues(
              alpha: isDark ? 0.18 : 0.22,
            ),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 右上角柔光,让纯色渐变不至于太平。
          Positioned(
            right: -30,
            top: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Column(
              children: [
                Icon(
                  Icons.favorite_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                const SizedBox(height: 10),
                // 用 SizedBox(width: double.infinity) 让 Text 撑满卡片宽度。
                // 只写 textAlign: center 是不够的:Text 默认按内容宽度收缩,
                // textAlign 只在自身宽度内居中,实测文案会明显偏左。
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    line1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.7,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          color: Color(0x33000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 署名:右下角。用 width: double.infinity + 右对齐,
                // 保证它始终贴着卡片右边缘(不随正文宽度浮动)。
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    signature,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                      shadows: const [
                        Shadow(
                          color: Color(0x26000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 默认音源设置行。
class _DefaultSourceRow extends StatelessWidget {
  const _DefaultSourceRow({required this.current, required this.onTap});

  final String? current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '默认音源',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                current ?? '自动',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 编辑音源弹窗:自持有输入控制器,随弹窗销毁时释放。
/// 返回 (name, srcUrl) 记录,取消返回 null。
class _EditSourceDialog extends StatefulWidget {
  const _EditSourceDialog({required this.name, required this.srcUrl});

  final String name;
  final String srcUrl;

  @override
  State<_EditSourceDialog> createState() => _EditSourceDialogState();
}

class _EditSourceDialogState extends State<_EditSourceDialog> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _urlCtrl = TextEditingController(
    text: widget.srcUrl,
  );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑音源'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('修改音源名称与订阅地址,保存后立即生效。'),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '音源名称',
              prefixIcon: Icon(Icons.label_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '音源地址 (srcUrl)',
              hintText: 'https://example.com/plugin.js',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            name: _nameCtrl.text,
            srcUrl: _urlCtrl.text,
          )),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.plugin,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.onTest,
  });

  final PluginInfo plugin;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onTest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: .6)
              : Colors.white.withValues(alpha: .06),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppTheme.softGradient,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.extension_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.platform,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'v${plugin.version}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (plugin.srcUrl != null &&
                          plugin.srcUrl!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            plugin.srcUrl!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.outline,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 启用状态指示
            Tooltip(
              message: plugin.enabled ? '已启用' : '已停用',
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: plugin.enabled
                      ? const Color(0xFF34D399)
                      : scheme.outline,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (plugin.enabled
                                  ? const Color(0xFF34D399)
                                  : scheme.outline)
                              .withValues(alpha: .5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (onTest != null)
              IconButton(
                tooltip: '测试音源',
                icon: Icon(Icons.radar_rounded, color: scheme.onSurfaceVariant),
                onPressed: onTest,
              ),
            IconButton(
              tooltip: '编辑',
              icon: Icon(Icons.edit_outlined, color: scheme.onSurfaceVariant),
              onPressed: onEdit,
            ),
            const SizedBox(width: 2),
            IconButton(
              tooltip: '卸载',
              icon: Icon(
                Icons.delete_outline_rounded,
                color: scheme.onSurfaceVariant,
              ),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// 已安装音源行:选中(默认)高亮描边 + 右上角徽标 + 删除。

class _EmptyPlugins extends StatelessWidget {
  const _EmptyPlugins({
    required this.onInstall,
    required this.onDownloadBundled,
  });

  final VoidCallback onInstall;

  /// 一键安装随 App 内置的默认音源(新用户首屏入口)。
  final VoidCallback onDownloadBundled;

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
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: AppTheme.softGradient,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.extension_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '尚未安装插件',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'App 已内置默认音源,一键即可开始使用',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            // 真机验证发现:空态此前只有「在线安装插件」,新用户根本看不到
            // 「下载音源」入口(它在「音乐源」分组里,而该分组只在有插件时渲染),
            // 内置音源等于白做。这里把一键下载放到首屏主按钮位置。
            FilledButton.icon(
              onPressed: onDownloadBundled,
              icon: const Icon(Icons.download_rounded),
              label: const Text('下载内置音源'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onInstall,
              icon: const Icon(Icons.link_rounded),
              label: const Text('在线安装插件'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 订阅源插件列表弹层:展示可安装插件与安装状态。
class _SourceSheet extends StatelessWidget {
  const _SourceSheet({
    required this.sources,
    required this.installed,
    required this.onInstall,
  });

  final List<PluginSource> sources;
  final Set<String> installed;
  final ValueChanged<PluginSource> onInstall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: Row(
              children: [
                Text(
                  '订阅源插件',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${sources.length} 个',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: sources.length,
              itemBuilder: (context, i) {
                final s = sources[i];
                final isInstalled = installed.contains(s.name);
                return ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
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
                  title: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    s.version.isNotEmpty ? 'v${s.version}' : s.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: isInstalled
                      ? Text(
                          '已安装',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : FilledButton(
                          onPressed: () => onInstall(s),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: const Text('安装'),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 过滤翻唱开关:内置音源里不要翻唱,尽量都是正版原唱。
class _FilterCoversRow extends ConsumerWidget {
  const _FilterCoversRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hide = ref.watch(hideCoversProvider);
    return Row(
      children: [
        Icon(
          Icons.verified_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '过滤翻唱',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '隐藏翻唱/伴奏/纯音乐版本,只留正版原唱',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Switch(
          value: hide,
          onChanged: (v) => ref.read(hideCoversProvider.notifier).update(v),
        ),
      ],
    );
  }
}

/// 设置页左侧菜单栏(宽屏左右栏):音乐源 / 外观 / 通用。
class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({required this.selected, required this.onSelect});

  final _SettingsSection selected;
  final ValueChanged<_SettingsSection> onSelect;

  static const _tabs = [
    (_SettingsSection.sources, Icons.library_music_rounded, '音乐源'),
    (_SettingsSection.appearance, Icons.palette_outlined, '外观'),
    (_SettingsSection.general, Icons.settings_rounded, '通用'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 180,
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          children: [
            for (final (s, icon, label) in _tabs)
              _SidebarItem(
                icon: icon,
                label: label,
                selected: s == selected,
                onTap: () => onSelect(s),
              ),
          ],
        ),
      ),
    );
  }
}

/// 设置页左侧菜单项。
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: .12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置分组容器:标题 + 卡片式分组。
/// 分组内是否在某两行之间画分隔线:跳过 SizedBox 占位与空态卡片。
bool _needsDivider(List<Widget> children, int i) {
  if (i == 0) return false;
  final prev = children[i - 1];
  final cur = children[i];
  if (prev is SizedBox || cur is SizedBox) return false;
  if (prev is _EmptyPlugins || cur is _EmptyPlugins) return false;
  return true;
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: _SectionTitle2(title),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          // 统一布局:组内不再靠零散的 SizedBox 撑间距,而是「行 + 细分隔线」,
          // 行高由各行自己保证(min 56),视觉更整齐(用户反馈设置页看着乱)。
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (_needsDivider(children, i))
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 48,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: .4),
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 通用菜单行:图标 + 标题 + 尾部值 + chevron。
class _MenuItemRow extends StatelessWidget {
  const _MenuItemRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 音源管理二级页:插件卡片列表 + 安装/编辑/卸载/测试。
/// 主设置页点击「已安装音源」进入。
class _SourceManagerPage extends ConsumerStatefulWidget {
  const _SourceManagerPage({
    required this.plugins,
    required this.current,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
    required this.onInstallUrl,
    required this.onInstallPath,
    required this.onInstallSource,
    required this.onInstallBundled,
  });

  final List<PluginInfo> plugins;
  final String? current;
  final void Function(PluginInfo) onEdit;
  final void Function(PluginInfo) onDelete;
  final void Function(PluginInfo) onTest;
  final VoidCallback onInstallUrl;
  final VoidCallback onInstallPath;
  final VoidCallback onInstallSource;
  final VoidCallback onInstallBundled;

  @override
  ConsumerState<_SourceManagerPage> createState() => _SourceManagerPageState();
}

class _SourceManagerPageState extends ConsumerState<_SourceManagerPage> {
  @override
  Widget build(BuildContext context) {
    // 响应式:主设置页删除/安装后 invalidate pluginListProvider,此处自动刷新列表。
    final asyncPlugins = ref.watch(pluginListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('音源管理'),
        actions: [
          PopupMenuButton<_InstallAction>(
            tooltip: '安装插件',
            icon: const Icon(Icons.add_rounded),
            onSelected: (action) => switch (action) {
              _InstallAction.bundled => widget.onInstallBundled(),
              _InstallAction.url => widget.onInstallUrl(),
              _InstallAction.source => widget.onInstallSource(),
              _InstallAction.file => widget.onInstallPath(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _InstallAction.bundled,
                child: ListTile(
                  leading: Icon(Icons.widgets_rounded),
                  title: Text('下载音源'),
                  subtitle: Text('App 内置,一键安装'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _InstallAction.url,
                child: ListTile(
                  leading: Icon(Icons.link_rounded),
                  title: Text('在线安装'),
                  subtitle: Text('输入插件 JS 的 URL'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _InstallAction.source,
                child: ListTile(
                  leading: Icon(Icons.rss_feed_rounded),
                  title: Text('导入订阅源'),
                  subtitle: Text('浏览 plugins.json 中的插件'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _InstallAction.file,
                child: ListTile(
                  leading: Icon(Icons.insert_drive_file_outlined),
                  title: Text('本地文件'),
                  subtitle: Text('从磁盘路径安装'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: asyncPlugins.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败:$e')),
        data: (plugins) {
          if (plugins.isEmpty) {
            // 空态下也要能进入「通用」看版本/检查更新
            return _EmptyPlugins(
              onInstall: widget.onInstallUrl,
              onDownloadBundled: widget.onInstallBundled,
            );
          }
          final source = ref.watch(searchSourceProvider);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Row(
                    children: [
                      const _SectionTitle2('已安装音源'),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: widget.onInstallUrl,
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('安装'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final p in plugins)
                    _PluginCard(
                      plugin: p,
                      selected: source == p.platform,
                      onTap: () => ref
                          .read(searchSourceProvider.notifier)
                          .select(p.platform),
                      onEdit: () => widget.onEdit(p),
                      onDelete: () => widget.onDelete(p),
                      onTest: () => widget.onTest(p),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '点击音源可设为默认,发现页搜索将优先使用',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
