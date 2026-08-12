import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/plugins/plugin_info.dart';
import 'package:musicx/core/search/search_controller.dart'
    show pluginManagerProvider;
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/models/plugin_source.dart';
import 'package:musicx/theme/app_theme.dart';

/// 安装入口类型。
enum _InstallAction { url, source, file }

/// 插件管理页:卡片式列表 + 安装/卸载。
class PluginPage extends ConsumerStatefulWidget {
  const PluginPage({super.key});

  @override
  ConsumerState<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends ConsumerState<PluginPage> {
  final TextEditingController _pathCtrl = TextEditingController();
  int _reload = 0;

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
      messenger.showSnackBar(
        SnackBar(content: Text('已安装插件「${info.platform}」v${info.version}')),
      );
    } catch (e) {
      if (mounted) setState(() => _reload++);
      messenger.showSnackBar(SnackBar(content: Text('安装失败:$e')));
    }
  }

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
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已卸载插件')));
  }

  /// 编辑已安装音源:修改音源名称与订阅地址(srcUrl),保存后立即生效。
  Future<void> _editPlugin(PluginInfo p) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({String name, String srcUrl})>(
      context: context,
      builder: (_) => _EditSourceDialog(
        name: p.platform,
        srcUrl: p.srcUrl ?? '',
      ),
    );
    if (result == null) return;
    try {
      await ref.read(pluginManagerProvider).updatePlugin(
            p,
            name: result.name,
            srcUrl: result.srcUrl,
          );
      if (mounted) setState(() => _reload++);
      messenger.showSnackBar(const SnackBar(content: Text('音源信息已更新')));
    } catch (e) {
      if (mounted) setState(() => _reload++);
      messenger.showSnackBar(SnackBar(content: Text('更新失败:$e')));
    }
  }

  /// 弹出默认音源选择器(自动 + 已装插件)。
  Future<void> _pickDefaultSource(
      List<PluginInfo> plugins, String? current) async {
    const autoMark = '__auto__';
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text(
                  '默认音源',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: Icon(Icons.auto_awesome_rounded,
                    color: scheme.onSurfaceVariant),
                title: const Text('自动'),
                subtitle: Text(
                  '按顺序尝试所有已装音源',
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                trailing: current == null
                    ? Icon(Icons.check_circle_rounded, color: AppTheme.violet)
                    : null,
                onTap: () => Navigator.pop(ctx, autoMark),
              ),
              for (final p in plugins)
                ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: AppTheme.softGradient,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.extension_rounded,
                        color: Colors.white, size: 18),
                  ),
                  title: Text(p.platform),
                  subtitle: Text(
                    'v${p.version}',
                    style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  trailing: current == p.platform
                      ? Icon(Icons.check_circle_rounded, color: AppTheme.violet)
                      : null,
                  onTap: () => Navigator.pop(ctx, p.platform),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    ref.read(searchSourceProvider.notifier)
        .select(picked == autoMark ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(pluginManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          PopupMenuButton<_InstallAction>(
            tooltip: '安装插件',
            icon: const Icon(Icons.add_rounded),
            onSelected: (action) => switch (action) {
              _InstallAction.url => _installFromUrl(),
              _InstallAction.source => _importFromSource(),
              _InstallAction.file => _installFromPath(),
            },
            itemBuilder: (_) => const [
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
        future: manager.listPlugins(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final plugins = snapshot.data ?? const [];
          if (plugins.isEmpty) {
            return _EmptyPlugins(onInstall: _installFromUrl);
          }
          final source = ref.watch(searchSourceProvider);
          // 桌面窗口内容限宽居中(PC 质感)
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _ProfileCard(
                pluginCount: plugins.length,
                onInstall: _installFromUrl,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const _SectionTitle2('已安装音源'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _installFromUrl,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.pink,
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
                  onTap: () =>
                      ref.read(searchSourceProvider.notifier).select(p.platform),
                  onEdit: () => _editPlugin(p),
                  onDelete: () => _uninstall(p),
                ),
              const SizedBox(height: 6),
              Text(
                '点击音源可设为默认,发现页搜索将优先使用',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 22),
              const _SectionTitle2('通用'),
              const SizedBox(height: 8),
              _DefaultSourceRow(
                current: source,
                onTap: () => _pickDefaultSource(plugins, source),
              ),
              const SizedBox(height: 20),
              const _AboutCard(),
            ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 顶部品牌信息卡(主流 App「我的」页风格)。
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.pluginCount, required this.onInstall});

  final int pluginCount;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    return Ink(
      decoration: BoxDecoration(
        gradient: AppTheme.softGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: InkWell(
        onTap: onInstall,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.music_note_rounded,
                    color: Colors.white, size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MusicX',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '插件化音乐播放器 · 轻量免费',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.extension_rounded,
                        color: Colors.white, size: 15),
                    const SizedBox(width: 5),
                    Text(
                      '$pluginCount 个插件',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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

class _SectionTitle2 extends StatelessWidget {
  const _SectionTitle2(this.text);

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

/// 关于信息卡。
class _AboutCard extends StatelessWidget {
  const _AboutCard();

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
              Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.violet),
              const SizedBox(width: 6),
              Text(
                '关于 MusicX',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '播放器本体不含任何音源,搜索与播放全部由第三方 JS 插件提供。\n安装音源:点右上角 + 在线安装,或导入订阅源。',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'MusicX v1.0.0 · 插件协议兼容 MusicFree',
            style: textTheme.labelSmall?.copyWith(color: scheme.outline),
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
              Icon(Icons.tune_rounded, size: 20, color: AppTheme.violet),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '默认音源',
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                current ?? '自动',
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
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
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.name);
  late final TextEditingController _urlCtrl =
      TextEditingController(text: widget.srcUrl);

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
          onPressed: () => Navigator.pop(
            context,
            (name: _nameCtrl.text, srcUrl: _urlCtrl.text),
          ),
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
  });

  final PluginInfo plugin;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
              ? AppTheme.violet.withValues(alpha: .6)
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
            child: const Icon(Icons.extension_rounded,
                color: Colors.white, size: 24),
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
                    Text(
                      'v${plugin.version}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (plugin.srcUrl != null && plugin.srcUrl!.isNotEmpty) ...[
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
                    color: (plugin.enabled
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
          IconButton(
            tooltip: '编辑',
            icon: Icon(Icons.edit_outlined,
                color: scheme.onSurfaceVariant),
            onPressed: onEdit,
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: '卸载',
            icon: Icon(Icons.delete_outline_rounded,
                color: scheme.onSurfaceVariant),
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
  const _EmptyPlugins({required this.onInstall});

  final VoidCallback onInstall;

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
              child: const Icon(Icons.extension_rounded,
                  color: Colors.white, size: 42),
            ),
            const SizedBox(height: 20),
            Text(
              '尚未安装插件',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '在线安装或导入订阅源,启用搜索与播放',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
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
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${sources.length} 个',
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
                    child: const Icon(Icons.extension_rounded,
                        color: Colors.white, size: 20),
                  ),
                  title: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    s.version.isNotEmpty ? 'v${s.version}' : s.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
