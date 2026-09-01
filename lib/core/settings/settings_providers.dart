import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// 应用设置持久化文件(默认 `~/.musicx/settings.json`)。
/// 测试可 override 到临时文件,避免污染真实配置。
final settingsFileProvider = Provider<File>((ref) {
  final home = Platform.environment['HOME'];
  final dir = Directory(home == null || home.isEmpty ? '.musicx' : '$home/.musicx');
  return File('${dir.path}/settings.json');
});

/// 主题偏好:浅色(默认)/深色,持久化到设置文件。
class ThemePreferenceController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    try {
      final f = ref.read(settingsFileProvider);
      if (f.existsSync()) {
        final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        if (map['themeMode'] == 'dark') return ThemeMode.dark;
      }
    } catch (_) {}
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
    try {
      final f = ref.read(settingsFileProvider);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        jsonEncode({'themeMode': state == ThemeMode.dark ? 'dark' : 'light'}),
      );
    } catch (_) {}
  }
}

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceController, ThemeMode>(
      ThemePreferenceController.new,
    );

