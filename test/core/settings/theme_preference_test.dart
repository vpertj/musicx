import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/settings_providers.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('mx_theme'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// 用独立临时设置文件构造容器,避免测试间共享持久化状态、不污染真实配置。
  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          settingsFileProvider.overrideWithValue(
            File('${tmp.path}/settings.json'),
          ),
        ],
      );

  test('默认浅色 ThemeMode.light', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    expect(c.read(themePreferenceProvider), ThemeMode.light);
  });

  test('setDark 切到深色并持久化(重启后保持)', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    c.read(themePreferenceProvider.notifier).setDark();
    expect(c.read(themePreferenceProvider), ThemeMode.dark);

    // 模拟重启:新容器读同一持久化文件,应仍为深色
    final c2 = makeContainer();
    addTearDown(c2.dispose);
    expect(c2.read(themePreferenceProvider), ThemeMode.dark);
  });

  test('setLight 切回浅色并持久化', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    c.read(themePreferenceProvider.notifier).setDark();
    c.read(themePreferenceProvider.notifier).setLight();
    expect(c.read(themePreferenceProvider), ThemeMode.light);

    final c2 = makeContainer();
    addTearDown(c2.dispose);
    expect(c2.read(themePreferenceProvider), ThemeMode.light);
  });
}
