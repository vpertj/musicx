// test/core/settings/hide_covers_test.dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/settings_providers.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mx_hide_covers');
    file = File('${tmp.path}/settings.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [settingsFileProvider.overrideWithValue(file)],
      );

  test('默认开启过滤翻唱', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    expect(c.read(hideCoversProvider), isTrue);
  });

  test('写入后持久化,且不冲掉其它设置', () {
    file.writeAsStringSync('{"themeMode":"dark"}');
    final c = makeContainer();
    addTearDown(c.dispose);

    c.read(hideCoversProvider.notifier).update(false);

    final map = c.read(settingsStoreProvider).readAll();
    expect(map['hideCovers'], isFalse);
    expect(map['themeMode'], 'dark');
    expect(file.readAsStringSync().contains('"hideCovers":false'), isTrue);
  });

  test('读取已有配置', () {
    file.writeAsStringSync('{"hideCovers":false}');
    final c = makeContainer();
    addTearDown(c.dispose);
    expect(c.read(hideCoversProvider), isFalse);
  });
}
