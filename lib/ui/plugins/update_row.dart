import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/updater/update_controller.dart';
import 'package:musicx/core/updater/update_service.dart';
import 'package:musicx/theme/app_theme.dart';

/// 设置页「检查更新」行:显示当前版本,有新版本时高亮提示。
class UpdateRow extends ConsumerWidget {
  const UpdateRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final hasUpdate = state.info != null && state.info!.hasUpdate;
    final current =
        state.info?.currentVersion ?? UpdateService.currentVersion();

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openUpdateDialog(context, ref, state),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                hasUpdate
                    ? Icons.system_update_alt_rounded
                    : Icons.update_rounded,
                size: 20,
                color: hasUpdate ? AppTheme.pink : AppTheme.violet,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasUpdate
                          ? '发现新版本 v${state.info!.latestVersion}'
                          : '检查更新',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: hasUpdate ? AppTheme.pink : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasUpdate ? '当前 v$current · 点击立即更新' : '当前版本 v$current',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
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

  Future<void> _openUpdateDialog(
    BuildContext context,
    WidgetRef ref,
    UpdateState state,
  ) async {
    // 未检查过或处于 idle:先手动检查
    if (state.phase == UpdatePhase.idle || state.phase == UpdatePhase.error) {
      final messenger = ScaffoldMessenger.of(context);
      await ref.read(updateControllerProvider.notifier).check();
      final newState = ref.read(updateControllerProvider);
      if (!context.mounted) return;
      if (newState.error != null) {
        messenger.showSnackBar(SnackBar(content: Text(newState.error!)));
        return;
      }
      if (newState.info == null || !newState.info!.hasUpdate) {
        messenger.showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
        return;
      }
    }
    final info = ref.read(updateControllerProvider).info;
    if (info == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v${info.latestVersion}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本 v${info.currentVersion}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes!,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showDownloadProgress(context, ref);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  /// 下载 + 安装进度对话框,完成后自动重启。
  void _showDownloadProgress(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _UpdateProgressDialog(),
    );
    ref.read(updateControllerProvider.notifier).update();
  }
}

/// 更新下载/安装进度对话框(不可关闭,完成后自动重启)。
class _UpdateProgressDialog extends ConsumerWidget {
  const _UpdateProgressDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final installing = state.phase == UpdatePhase.installing;
    final downloading = state.phase == UpdatePhase.downloading;
    final failed = state.phase == UpdatePhase.error && state.error != null;

    return AlertDialog(
      title: Text(installing ? '正在安装更新…' : '正在下载更新…'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failed)
            Text(
              state.error!,
              style: textTheme.bodySmall?.copyWith(color: scheme.error),
            )
          else if (downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              state.progress > 0
                  ? '下载中 ${(state.progress * 100).toStringAsFixed(0)}%'
                  : '正在连接下载源…',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else if (installing)
            Text(
              '正在替换应用,完成后将自动重启…',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      actions: failed
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ]
          : null,
    );
  }
}
