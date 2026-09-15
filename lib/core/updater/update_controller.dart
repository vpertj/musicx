import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/updater/apk_installer.dart';
import 'package:musicx/core/updater/install_decision.dart';
import 'package:musicx/core/updater/update_service.dart';
import 'package:musicx/core/utils/open_external.dart';

/// 更新流程状态。
enum UpdatePhase { idle, checking, ready, downloading, installing, error }

class UpdateState {
  final UpdatePhase phase;
  final UpdateInfo? info;
  final double progress; // 下载进度 0~1
  final String? error;

  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.info,
    this.progress = 0,
    this.error,
  });

  UpdateState copyWith({
    UpdatePhase? phase,
    UpdateInfo? info,
    bool clearInfo = false,
    double? progress,
    String? error,
    bool clearError = false,
  }) {
    return UpdateState(
      phase: phase ?? this.phase,
      info: clearInfo ? null : (info ?? this.info),
      progress: progress ?? this.progress,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

class UpdateController extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  /// 静默检查更新(启动时调用),发现新版即进入 ready 态。
  Future<void> check({bool silent = false}) async {
    state = state.copyWith(phase: UpdatePhase.checking, clearError: true);
    try {
      final info = await ref.read(updateServiceProvider).checkForUpdate();
      if (!info.hasUpdate) {
        if (silent) {
          // 静默检查:无更新不打扰用户,回到 idle。
          state = state.copyWith(phase: UpdatePhase.idle, clearInfo: true);
        } else {
          // 手动检查:无更新时直接置 error 相位并显示提示。
          state = state.copyWith(
            phase: UpdatePhase.error,
            clearInfo: true,
            error: '当前已是最新版本 v${info.currentVersion}',
          );
        }
      } else {
        state = state.copyWith(phase: UpdatePhase.ready, info: info);
      }
    } catch (e) {
      state = state.copyWith(
        phase: UpdatePhase.error,
        error: silent ? null : '检查更新失败:$e',
      );
    }
  }

  /// 执行更新:macOS/Android 应用内下载并安装(Android 会拉起系统安装器);
  /// Windows/Linux 打开 Release 页手动下载。
  Future<void> update() async {
    // 并发守卫:下载/安装进行中时忽略重复触发(启动弹窗 + 设置页按钮
    // 可能同时被点到,重复下载会白耗流量并互相覆盖文件)。
    if (state.phase == UpdatePhase.downloading ||
        state.phase == UpdatePhase.installing) {
      return;
    }
    var info = state.info;
    if (info == null) {
      // info 缺失(如直接调用),重新检查一次
      await check();
      info = state.info;
      if (info == null || !info.hasUpdate) {
        state = state.copyWith(phase: UpdatePhase.error, error: '没有可用的更新版本');
        return;
      }
    }
    // 不支持应用内安装的平台:打开 GitHub Release 页,由用户手动下载。
    if (!UpdateService.canAutoInstall) {
      final ok = await openExternalUrl(info.releaseUrl);
      state = ok
          ? state.copyWith(phase: UpdatePhase.idle, clearError: true)
          : state.copyWith(
              phase: UpdatePhase.error,
              error: '无法打开下载页面,请手动访问 GitHub Release',
            );
      return;
    }
    // 安装前用真实版本再确认一次:此前安卓上同步版本号恒为 0.0.0,
    // 会对着已是最新的机器继续下载,最后被系统安装器以「已是新版本」拒绝。
    final service = ref.read(updateServiceProvider);
    final installed = await service.resolveCurrentVersion();
    if (compareVersions(info.latestVersion, installed) <= 0) {
      state = state.copyWith(
        phase: UpdatePhase.error,
        clearInfo: true,
        error: '当前已是最新版本 v$installed',
      );
      return;
    }
    // 安卓 8+ 必须先获得「安装未知应用」权限,否则安装会被系统静默拒绝,
    // 用户只看到「更新失败」(实测:装 1.7.20 后升级,系统弹窗提示不允许
    // 从此来源安装应用)。这里在**下载前**检查并引导授权,避免白下载 60MB。
    if (Platform.isAndroid) {
      final allowed = await ApkInstaller.canInstallPackages();
      if (!allowed) {
        await ApkInstaller.openInstallPermissionSettings();
        state = state.copyWith(
          phase: UpdatePhase.error,
          error: '请先在系统设置里允许「MusicX 安装应用」,然后返回重新点击更新',
        );
        return;
      }
    }
    // 下载前先核对**直链里的版本号**:更新检查若给出旧版本直链,我们会白下载
    // 60MB 再被系统以「已安装更高版本」拒绝(用户实测)。这里提前拦下并自动
    // 重新检查一次;重检后仍不可信则给出带版本号的可读提示。
    final pre = decidePreDownload(
      assetUrl: info.dmgUrl,
      installedVersion: installed,
      expectedLatest: info.latestVersion,
    );
    if (pre == PreDownloadDecision.staleCheck) {
      debugPrint(
        'MusicX 更新: 直链版本不可信(url=${info.dmgUrl} '
        'installed=$installed latest=${info.latestVersion}),重新检查',
      );
      final retry = await service.checkForUpdate();
      final pre2 = decidePreDownload(
        assetUrl: retry.dmgUrl,
        installedVersion: installed,
        expectedLatest: retry.latestVersion,
      );
      if (pre2 == PreDownloadDecision.staleCheck) {
        state = state.copyWith(
          phase: UpdatePhase.error,
          clearInfo: true,
          error: '更新包版本(${versionFromAssetUrl(retry.dmgUrl) ?? "未知"})'
              '不高于当前版本(v$installed),无需更新。'
              '如仍提示,请到 GitHub Releases 手动下载最新版',
        );
        return;
      }
      info = retry;
    }
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0);
    try {
      final pkg = await service.download(
        info.dmgUrl,
        onProgress: (p) => state = state.copyWith(progress: p),
        expectedSha256: info.dmgSha256,
        version: info.latestVersion,
      );
      state = state.copyWith(phase: UpdatePhase.installing);
      // 把目标版本一并交给校验:安装包的 versionName 必须等于它
      await service.installAndRestart(pkg, version: info.latestVersion);
      // macOS 的 installAndRestart 会 exit(0),正常不会走到这里。
      if (Platform.isAndroid) {
        // 关键:清掉缓存的版本号,否则本进程仍以为自己是旧版本,
        // 会继续提示「有新版本」,再点更新就会拿同版本 APK 去装并被系统拒绝
        // (实测:1.7.11 装完 1.7.13 后仍提示更新,安装器回「已安装更高版本」)。
        UpdateService.invalidateVersionCache();
        state = state.copyWith(
          phase: UpdatePhase.error,
          clearInfo: true,
          error: '已把 v${info.latestVersion} 的安装包交给系统安装器'
              '(文件 ${pkg.path.split('/').last})。'
              '若系统界面显示的版本号不是 v${info.latestVersion},'
              '说明它装的是别的旧文件,请改用应用内更新重试。'
              '安装完成后请重新打开应用。',
        );
      }
    } catch (e) {
      state = state.copyWith(phase: UpdatePhase.error, error: '更新失败:$e');
    }
  }
}
