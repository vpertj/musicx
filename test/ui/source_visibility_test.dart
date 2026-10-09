// test/ui/source_visibility_test.dart
//
// 用户要求(反复强调,必须彻底):
//   ① 内置音源(腾讯/网易/酷我)不要在 App 里显示任何名字;
//   ② 「已安装音源」只列用户自己装的;一个都没有时连这一行都不显示;
//   ③ 「默认音源」选择器只显示「自动」,用户自己装了音源才多出可选项。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/core/providers.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';

const _userPlugin = '''
module.exports = { platform: "我的音源", version: "1.0.0",
  search: function () { return Promise.resolve({ isEnd: true, data: [] }); }
};
''';

/// 内置音源名字(任何场景下都不该出现在界面里)。
const _bundledNames = ['腾讯音乐', '网yi', '酷我(念心音源)', '酷我'];

/// 老版本随 App 内置过、后来改名/下线的音源(用户手机上真实存在的遗留文件)。
/// 用户反馈:「默认音源怎么那么多,以前不是只有三个还是四个」—— 就是这些
/// 老文件被当成「用户自己装的音源」列了出来。
const _legacyNeteasePlugin = '''
module.exports = { platform: "网易音乐", version: "2025.09.14",
  srcUrl: "https://raw.githubusercontent.com/ThomasBy2025/musicfree/refs/heads/main/plugins/wy.js",
  search: function () { return Promise.resolve({ isEnd: true, data: [] }); }
};
''';

const _legacyKuwoDujiaPlugin = '''
module.exports = { platform: "酷我(独家音源)", version: "1.0.0",
  srcUrl: "https://x/kuwo_dujia.js",
  search: function () { return Promise.resolve({ isEnd: true, data: [] }); }
};
''';

void main() {
  late Directory tmp;
  late Directory srcDir;
  late PluginManager manager;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mx_src_vis');
    srcDir = Directory.systemTemp.createTempSync('mx_src_vis_src');
    manager = PluginManager(tmp);
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
    srcDir.deleteSync(recursive: true);
  });

  Future<void> installBundled() async {
    final catalog = BundledPluginCatalog();
    for (final p in await catalog.list()) {
      await manager.installBundledJs(
        await catalog.readJs(p),
        source: 'bundled:${p.assetPath}',
      );
    }
  }

  Future<void> installUser() async {
    await manager.installFromFile(
      (File('${srcDir.path}/my.js')..writeAsStringSync(_userPlugin)).path,
    );
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [pluginManagerProvider.overrideWithValue(manager)],
          child: const MaterialApp(home: PluginPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  void expectNoBundledName() {
    for (final name in _bundledNames) {
      expect(find.text(name), findsNothing,
          reason: '内置音源「$name」不应出现在界面里');
      expect(find.textContaining(name), findsNothing,
          reason: '内置音源「$name」不应出现在任何文案里');
    }
  }

  testWidgets('场景 A:只装了内置音源 —— 完全看不到内置源,也没有「已安装音源」行', (tester) async {
    await tester.runAsync(installBundled);
    await pump(tester);

    expectNoBundledName();
    expect(find.text('内置音源'), findsNothing, reason: '「内置音源」行应已移除');
    expect(find.text('已安装音源'), findsNothing,
        reason: '用户没有自己的音源时,这一行不显示');
    // 空态引导也不该出现(内置源已装,可以直接用)
    expect(find.text('尚未安装插件'), findsNothing);

    // 默认音源选择器:只有「自动」
    await tester.tap(find.text('默认音源'));
    await tester.pumpAndSettle();
    expect(find.text('自动'), findsWidgets);
    expectNoBundledName();
  });

  testWidgets('场景 B:内置 + 1 个用户音源 —— 只多出用户音源,内置仍不显示', (tester) async {
    await tester.runAsync(() async {
      await installBundled();
      await installUser();
    });
    await pump(tester);

    expectNoBundledName();
    expect(find.text('已安装音源'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: '计数只算用户音源');

    // 选择器:自动 + 我的音源,不含内置
    await tester.tap(find.text('默认音源'));
    await tester.pumpAndSettle();
    expect(find.text('我的音源'), findsOneWidget);
    expectNoBundledName();
  });

  testWidgets('场景 D:历史遗留的内置源(改过名/下线过)—— 同样不显示', (tester) async {
    // 用户手机上真实存在的遗留文件(升级是覆盖安装,老文件不会消失):
    // 「网易音乐」是内置 wy.js 的早期平台名,「酷我(独家音源)」是 08e9431 内置、
    // ed5e51c 下线的源。它们不是用户装的,不该出现在任何列表里。
    await tester.runAsync(() async {
      await installBundled();
      await manager.installFromFile(
        (File('${srcDir.path}/legacy_wy.js')
              ..writeAsStringSync(_legacyNeteasePlugin))
            .path,
      );
      await manager.installFromFile(
        (File('${srcDir.path}/legacy_dujia.js')
              ..writeAsStringSync(_legacyKuwoDujiaPlugin))
            .path,
      );
    });
    await pump(tester);

    expect(find.text('网易音乐'), findsNothing, reason: '改名过的老内置源不该冒充用户音源');
    expect(find.text('酷我(独家音源)'), findsNothing, reason: '下过线的老内置源不该冒充用户音源');
    expect(find.text('已安装音源'), findsNothing,
        reason: '用户没装自己的音源时,这一行不显示(遗留内置源不算)');

    await tester.tap(find.text('默认音源'));
    await tester.pumpAndSettle();
    expect(find.text('自动'), findsWidgets);
    expect(find.text('网易音乐'), findsNothing);
    expect(find.text('酷我(独家音源)'), findsNothing);
    expectNoBundledName();
  });

  testWidgets('场景 C:什么都没装 —— 显示引导入口,可安装内置音源', (tester) async {
    await pump(tester);


    expect(find.text('尚未安装插件'), findsOneWidget);
    expect(find.text('下载内置音源'), findsOneWidget);
    expect(find.text('已安装音源'), findsNothing);
    expect(find.text('内置音源'), findsNothing);

    // 选择器仍然只有「自动」
    await tester.tap(find.text('默认音源'));
    await tester.pumpAndSettle();
    expect(find.text('自动'), findsWidgets);
    expectNoBundledName();
  });
}
