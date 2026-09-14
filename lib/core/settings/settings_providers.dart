import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/settings/settings_store.dart';
import 'package:musicx/core/utils/app_paths.dart';

/// 当前搜索音源插件名;null 表示「自动」——按顺序尝试全部已装插件。
/// 由发现页音源切换条与「我的」页设置共同读写。
class SearchSourceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? source) => state = source;
}

final searchSourceProvider = NotifierProvider<SearchSourceNotifier, String?>(
  SearchSourceNotifier.new,
);

/// 应用设置持久化文件(数据目录下 settings.json;macOS 为 ~/.musicx)。
/// 测试可 override 到临时文件,避免污染真实配置。
final settingsFileProvider = Provider<File>(
  (ref) => AppPaths.file('settings.json'),
);

/// 设置存储(合并写),所有设置项的落盘都经由它。
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(settingsFileProvider)),
);

/// 主题偏好:浅色(默认)/深色,持久化到设置文件。
class ThemePreferenceController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final map = ref.watch(settingsStoreProvider).readAll();
    if (map['themeMode'] == 'dark') return ThemeMode.dark;
    return ThemeMode.light;
  }

  void setDark() {
    state = ThemeMode.dark;
    _persist();
  }

  void setLight() {
    state = ThemeMode.light;
    _persist();
  }

  void _persist() {
    ref
        .read(settingsStoreProvider)
        .merge({'themeMode': state == ThemeMode.dark ? 'dark' : 'light'});
  }
}

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceController, ThemeMode>(
      ThemePreferenceController.new,
    );


/// 是否过滤翻唱/非原唱版本(默认开启)。
///
/// 用户诉求:内置音源结果里不要翻唱,尽量都是正版原唱。识别逻辑见
/// core/search/original_filter.dart;过滤后若为空会回退不过滤。
class HideCoversController extends Notifier<bool> {
  @override
  bool build() {
    final map = ref.watch(settingsStoreProvider).readAll();
    return map['hideCovers'] is bool ? map['hideCovers'] as bool : true;
  }

  void update(bool value) {
    state = value;
    ref.read(settingsStoreProvider).merge({'hideCovers': value});
  }
}

final hideCoversProvider =
    NotifierProvider<HideCoversController, bool>(HideCoversController.new);
