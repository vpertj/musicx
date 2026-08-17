import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/updater/update_service.dart';

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
        state = state.copyWith(
          phase: UpdatePhase.idle,
          clearInfo: true,
          error: silent ? null : '当前已是最新版本 v${info.currentVersion}',
        );
        if (!silent) state = state.copyWith(phase: UpdatePhase.error);
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

  /// 下载并安装更新,完成后自动重启。
  Future<void> update() async {
    final info = state.info;
    if (info == null) return;
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0);
    try {
      final service = ref.read(updateServiceProvider);
      final dmg = await service.download(
        info.dmgUrl,
        onProgress: (p) => state = state.copyWith(progress: p),
      );
      state = state.copyWith(phase: UpdatePhase.installing);
      await service.installAndRestart(dmg);
      // installAndRestart 会 exit(0),正常不会走到这里
    } catch (e) {
      state = state.copyWith(phase: UpdatePhase.error, error: '更新失败:$e');
    }
  }
}