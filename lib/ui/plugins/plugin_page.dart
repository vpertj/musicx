import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/plugins/plugin_info.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/search/search_controller.dart'
    show pluginManagerProvider;

class PluginPage extends ConsumerWidget {
  const PluginPage({super.key});

  Future<void> _install(WidgetRef ref, BuildContext context) async {
    final pathCtrl = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('安装插件'),
        content: TextField(
          controller: pathCtrl,
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
            onPressed: () => Navigator.pop(ctx, pathCtrl.text),
            child: const Text('安装'),
          ),
        ],
      ),
    );
    if (path == null || path.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(pluginManagerProvider).installFromFile(path.trim());
      messenger.showSnackBar(const SnackBar(content: Text('插件安装成功')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('安装失败:$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(pluginManagerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '安装插件',
            onPressed: () => _install(ref, context),
          ),
        ],
      ),
      body: FutureBuilder<List<PluginInfo>>(
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
                    // 触发重建:更换 FutureBuilder 的 key 或刷新状态
                    // (MVP 简化:重建页面)
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已卸载')));
                    }
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
