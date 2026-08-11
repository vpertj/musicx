import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/search_controller.dart';
import 'package:musicx/ui/search/search_page.dart';

// 注:插件搜索运行在真实 isolate 中(PluginSandbox.isolate),其完成消息
// 依赖真实事件循环;flutter_test 的 FakeAsync zone 无法推进真实异步,
// 故交互需放在 tester.runAsync 中执行,否则 pumpAndSettle 会因 loading
// 态无限动画而超时。

const _demoPlugin = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function (q) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({ isEnd: true, data: [ { id: "d1", title: "示例歌曲", artist: "歌手", album: "专辑",
          artwork: "", duration: 180000, platform: "demo", songId: "d1", extra: {} } ] });
      }, 10);
    });
  },
  getMediaSource: function (m) { return { url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3" }; }
};
''';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_sp');
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('typing query and submitting shows song results', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
      ],
      child: const MaterialApp(home: SearchPage()),
    ));

    await tester.runAsync(() async {
      await tester.enterText(find.byType(TextField), '示例');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(find.text('示例歌曲'), findsOneWidget);
    expect(find.text('歌手'), findsOneWidget);
  });
}
