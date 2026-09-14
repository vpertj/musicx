import 'package:flutter/material.dart';

import 'package:musicx/core/plugins/bundled_plugins.dart';

/// 内置音源面板:列出随 App 打包的默认音源及其安装状态。
///
/// 纯展示 + 回调:不读 asset、不碰插件目录,便于单测与复用
/// (PluginPage 的「内置默认音源」入口与空态引导都用它)。
class BundledSourcesSheet extends StatelessWidget {
  const BundledSourcesSheet({
    super.key,
    required this.plugins,
    required this.installedVersions,
    required this.installedCount,
    required this.onInstall,
  });

  final List<BundledPlugin> plugins;

  /// platform → 已安装版本。
  final Map<String, String> installedVersions;

  /// 当前已安装插件总数(仅用于提示)。
  final int installedCount;

  final void Function(BundledPlugin plugin) onInstall;

  BundledInstallState _stateOf(BundledPlugin p) => bundledInstallState(
        bundledVersion: p.version,
        installedVersion: installedVersions[p.platform],
      );

  /// 需要处理的条目(未安装 + 版本不同)。
  List<BundledPlugin> get _pending =>
      plugins.where((p) => _stateOf(p) != BundledInstallState.installed).toList();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('默认音源', style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '随 App 内置的第三方音源插件,安装到本机后才可用于搜索与播放。'
                  '已安装 $installedCount 个音源。',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final p in plugins)
            _BundledRow(
              plugin: p,
              state: _stateOf(p),
              installedVersion: installedVersions[p.platform],
              onInstall: () => onInstall(p),
            ),
          if (_pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () {
                    for (final p in _pending) {
                      onInstall(p);
                    }
                  },
                  child: const Text('全部安装'),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text('内置音源均已安装', style: textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BundledRow extends StatelessWidget {
  const _BundledRow({
    required this.plugin,
    required this.state,
    required this.installedVersion,
    required this.onInstall,
  });

  final BundledPlugin plugin;
  final BundledInstallState state;
  final String? installedVersion;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final subtitle = StringBuffer('内置版本 ${plugin.version}');
    if (plugin.author.isNotEmpty) subtitle.write(' · 作者 ${plugin.author}');
    if (state == BundledInstallState.updatable && installedVersion != null) {
      subtitle.write(' · 已装 $installedVersion');
    }

    return ListTile(
      title: Text(plugin.name),
      subtitle: Text(subtitle.toString(), style: textTheme.bodySmall),
      trailing: switch (state) {
        BundledInstallState.installed => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 4),
              const Text('已安装'),
            ],
          ),
        BundledInstallState.updatable => FilledButton.tonal(
            onPressed: onInstall,
            child: const Text('更新'),
          ),
        BundledInstallState.notInstalled => FilledButton(
            onPressed: onInstall,
            child: const Text('安装'),
          ),
      },
    );
  }
}

/// 便捷入口:弹出内置音源面板。
Future<void> showBundledSourcesSheet(
  BuildContext context, {
  required List<BundledPlugin> plugins,
  required Map<String, String> installedVersions,
  required int installedCount,
  required void Function(BundledPlugin plugin) onInstall,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BundledSourcesSheet(
      plugins: plugins,
      installedVersions: installedVersions,
      installedCount: installedCount,
      onInstall: onInstall,
    ),
  );
}
