import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/plugins/plugin_info.dart';
import 'package:musicx/core/search/search_controller.dart'
    show pluginManagerProvider;
import 'package:musicx/theme/app_theme.dart';

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

  Future<void> _install() async {
    _pathCtrl.clear();
    final messenger = ScaffoldMessenger.of(context);
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('安装插件'),
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

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(pluginManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '安装插件',
            onPressed: _install,
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
            return _EmptyPlugins(onInstall: _install);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppTheme.softGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.extension_rounded,
                          color: Colors.white, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '已安装 ${plugins.length} 个插件',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '插件提供搜索与播放源,点右上角 + 安装',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: plugins.length,
                  itemBuilder: (context, index) {
                    final p = plugins[index];
                    return _PluginCard(
                      plugin: p,
                      onDelete: () => _uninstall(p),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.plugin, required this.onDelete});

  final PluginInfo plugin;
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
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
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
            tooltip: '卸载',
            icon: Icon(Icons.delete_outline_rounded,
                color: scheme.onSurfaceVariant),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

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
              '安装一个插件以启用搜索与播放\n示例:example/plugins/demo_plugin.js',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onInstall,
              icon: const Icon(Icons.add_rounded),
              label: const Text('安装插件'),
            ),
          ],
        ),
      ),
    );
  }
}
