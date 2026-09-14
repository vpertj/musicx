import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/settings/settings_store.dart';

void main() {
  late Directory tmp;
  late File file;
  late SettingsStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mx_settings_store');
    file = File('${tmp.path}/settings.json');
    store = SettingsStore(file);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('merge 写入新 key 并落盘', () {
    store.merge({'themeMode': 'dark'});
    expect(jsonDecode(file.readAsStringSync()), {'themeMode': 'dark'});
  });

  test('merge 只覆盖传入 key,不冲掉其它设置', () {
    store.merge({'desktopLyrics': {'fontSize': 40}});
    store.merge({'themeMode': 'dark'});
    expect(store.readAll()['themeMode'], 'dark');
    expect((store.readAll()['desktopLyrics'] as Map)['fontSize'], 40);
  });

  test('文件不存在时 readAll 返回空 map', () {
    expect(store.readAll(), isEmpty);
  });

  test('文件损坏时 readAll 返回空且 merge 能自愈', () {
    file.writeAsStringSync('{not json');
    expect(store.readAll(), isEmpty);
    store.merge({'a': 1});
    expect(store.readAll()['a'], 1);
  });
}
