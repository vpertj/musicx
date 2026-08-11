import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/search/search_controller.dart' show pluginManagerProvider;
import 'package:musicx/ui/plugins/plugin_page.dart';

const _demoPlugin = '''
module.exports = { platform: "demo", version: "0.1.0", search: function(q){ return Promise.resolve({isEnd:true,data:[]}); } };
''';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_pp');
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('PluginPage lists installed plugins', (tester) async {
    // listPlugins 涉及真实 File IO,flutter_test 的 FakeAsync zone 无法推进
    // 真实异步(见 search_page_test 同款注释),需在 runAsync 中完成 future。
    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
        ],
        child: const MaterialApp(home: PluginPage()),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('demo'), findsOneWidget);
    expect(find.text('v0.1.0'), findsOneWidget);
  });
}
