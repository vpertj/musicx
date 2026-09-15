import 'dart:io';

import 'package:flutter/material.dart';
import 'package:musicx/core/updater/apk_installer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/updater/update_controller.dart';
import 'package:musicx/core/updater/update_service.dart';
import 'package:musicx/ui/plugins/update_diagnostics.dart';

/// 弹出"发现新版本"对话框(启动自动提示与设置页共用)。
/// 用户可选择「立即更新」(下载→安装→重启)或「稍后」。
Future<void> showUpdatePrompt(BuildContext context, UpdateInfo info) async {
  if (!context.mounted) return;
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
          onPressed: () {
            Navigator.pop(ctx);
            showUpdateDiagnostics(context);
          },
          child: const Text('诊断'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('稍后'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            if (UpdateService.canAutoInstall) {
              showUpdateProgress(context);
            } else {
              // 非 macOS:打开 GitHub Release 页由用户手动下载
              ProviderScope.containerOf(
                context,
              ).read(updateControllerProvider.notifier).update();
            }
          },
          icon: Icon(
            UpdateService.canAutoInstall
                ? Icons.download_rounded
                : Icons.open_in_new_rounded,
            size: 18,
          ),
          label: Text(UpdateService.canAutoInstall ? '立即更新' : '前往下载'),
        ),
      ],
    ),
  );
}

/// 显示下载/安装进度对话框并启动更新流程。
void showUpdateProgress(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _UpdateProgressDialog(),
  );
  // 从 ProviderScope 获取 controller
  final container = ProviderScope.containerOf(context);
  container.read(updateControllerProvider.notifier).update();
}

/// 设置页「检查更新」行:显示当前版本,有新版本时高亮提示。
class UpdateRow extends ConsumerStatefulWidget {
  const UpdateRow({super.key});

  @override
  ConsumerState<UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends ConsumerState<UpdateRow> {
  /// 真实版本号:安卓必须走平台通道解析(同步 API 只能读 macOS Info.plist,
  /// 在安卓恒为 0.0.0,此前导致「应用里看不到版本号」)。
  String? _version;

  /// 已装应用的 versionCode:升级问题排查的关键数字(可与 Release 包对比)。
  int? _versionCode;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final v = await ref.read(updateServiceProvider).resolveCurrentVersion();
    if (mounted && v.isNotEmpty && v != '0.0.0') setState(() => _version = v);
    final code = await ApkInstaller.versionCode();
    if (mounted && code != null && code > 0) {
      setState(() => _versionCode = code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final hasUpdate = state.info != null && state.info!.hasUpdate;
    final current =
        state.info?.currentVersion ??
        _version ??
        UpdateService.knownVersion() ??
        UpdateService.currentVersion();

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
                color: hasUpdate ? scheme.primary : scheme.onSurfaceVariant,
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
                        color: hasUpdate ? scheme.primary : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // 带上 versionCode:升级排查时可直接与 Release 包内数字对比
                      hasUpdate
                          ? '当前 v$current'
                                '${_versionCode == null ? '' : ' (code $_versionCode)'}'
                                ' · 点击${UpdateService.canAutoInstall ? '立即更新' : '前往下载'}'
                          : '当前版本 v$current'
                                '${_versionCode == null ? '' : ' (code $_versionCode)'}',
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
        messenger.showSnackBar(
          SnackBar(
            content: Text(newState.error!),
            // 必须显式 `persist: false`:Material 的规则是
            // `persist = persist ?? action != null` —— 只要带了 action,
            // 光给 duration 也没用,定时器到点后会因 persist 直接 return,
            // 提示条永远停在屏幕底部(用户实测就是这个现象)。
            persist: false,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: '诊断',
              onPressed: () => showUpdateDiagnostics(context),
            ),
          ),
        );
        return;
      }
      if (newState.info == null || !newState.info!.hasUpdate) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('当前已是最新版本'),
            persist: false,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '诊断',
              onPressed: () => showUpdateDiagnostics(context),
            ),
          ),
        );
        return;
      }
    }
    final info = ref.read(updateControllerProvider).info;
    if (info == null || !context.mounted) return;
    await showUpdatePrompt(context, info);
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
    // 「已交给系统安装器」是**成功交接**,不能当失败展示(用户实测:看到
    // 「更新失败」以为出错了)。
    final handedOff = state.phase == UpdatePhase.handedOff;

    return AlertDialog(
      title: Text(
        handedOff
            ? '安装包已就绪'
            : installing
            ? '正在安装更新…'
            : failed
            ? '更新失败'
            : '正在下载更新…',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (handedOff) ...[
            Icon(
              Icons.check_circle_outline_rounded,
              size: 40,
              color: scheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              state.error ?? '',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              Platform.isAndroid
                  ? '请在系统安装界面点「安装」;装好后回到应用会自动重启加载新版本。'
                  : '替换完成后应用会自动重启。',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else if (failed) ...[
            Icon(Icons.error_outline_rounded, size: 40, color: scheme.error),
            const SizedBox(height: 12),
            // 诊断信息可能较长(含版本号/versionCode/签名指纹),
            // 限高可滚动 + 可选中,方便用户复制数字反馈问题。
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(
                  state.error ?? '未知错误',
                  textAlign: TextAlign.start,
                  style: textTheme.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '可以稍后重试,或前往 GitHub Releases 手动下载',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else if (downloading) ...[
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
              Platform.isAndroid
                  ? '已下载完成,正在打开系统安装器…\n'
                        '首次需在系统提示中允许安装,装好后应用即为新版本。'
                  : '正在替换应用,完成后将自动重启…',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            Text(
              '准备中…',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      actions: (failed || handedOff)
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(handedOff ? '知道了' : '关闭'),
              ),
            ]
          : null,
    );
  }
}
