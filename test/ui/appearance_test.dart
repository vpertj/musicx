import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/search/search_controller.dart'
    show pluginManagerProvider;
import 'package:musicx/core/settings/settings_providers.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';

const _demoPlugin = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function(q){ return Promise.resolve({isEnd:true,data:[{id:"1",title:"测试歌",artist:"歌手",songId:"1"}]}); },
  getMediaSource: function(m){ return Promise.resolve({url:"https://example.com/test.mp3"}); }
};
''';

void main() {
  late Directory tmp;
  late File settingsFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_appear');
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
    settingsFile = File('${tmp.path}/settings.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('设置页可切换深色(浅色默认)', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
            settingsFileProvider.overrideWithValue(settingsFile),
          ],
          child: const MaterialApp(home: PluginPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    // 默认浅色
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PluginPage)),
    );
    expect(container.read(themePreferenceProvider), ThemeMode.light);

    // 点击左侧「外观」菜单,显示浅色/深色切换
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();

    // 点击"深色"
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(container.read(themePreferenceProvider), ThemeMode.dark);

    // 持久化到设置文件
    expect(settingsFile.existsSync(), isTrue);
  });

  testWidgets('设置页可切回浅色', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
            settingsFileProvider.overrideWithValue(settingsFile),
          ],
          child: const MaterialApp(home: PluginPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PluginPage)),
    );
    container.read(themePreferenceProvider.notifier).setDark();
    await tester.pumpAndSettle();
    expect(container.read(themePreferenceProvider), ThemeMode.dark);

    // 点击左侧「外观」菜单,显示浅色/深色切换
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(container.read(themePreferenceProvider), ThemeMode.light);
  });
}
