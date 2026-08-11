import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/plugins/plugin_info.dart';
import 'package:musicx/core/search/search_controller.dart'
    show pluginManagerProvider;

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
        content: TextField(
          controller: _pathCtrl,
          decoration: const InputDecoration(
            hintText: '输入插件 .js 文件路径',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
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

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(pluginManagerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
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
            return const Center(child: Text('尚未安装插件'));
          }
          return ListView.builder(
            itemCount: plugins.length,
            itemBuilder: (context, index) {
              final p = plugins[index];
              return ListTile(
                leading: const Icon(Icons.extension),
                title: Text(p.platform),
                subtitle: Text('v${p.version}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '卸载',
                  onPressed: () async {
                    await manager.uninstall(p);
                    if (mounted) setState(() => _reload++);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已卸载')));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
