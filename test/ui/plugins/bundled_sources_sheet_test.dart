// test/ui/plugins/bundled_sources_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/bundled_plugins.dart';
import 'package:musicx/ui/plugins/bundled_sources_sheet.dart';

const _netease = BundledPlugin(
  name: '网易云音乐',
  platform: 'netease',
  version: '2025.09.14',
  assetPath: 'assets/plugins/netease.js',
  author: 'Thomas喲',
  sourceUrl: 'https://example.com/wy.js',
);
const _kuwo = BundledPlugin(
  name: '酷我音乐',
  platform: 'kuwo',
  version: '0.1.0',
  assetPath: 'assets/plugins/kuwo.js',
);

Future<void> pump(
  WidgetTester tester, {
  required Map<String, String> installed,
  required void Function(BundledPlugin) onInstall,
  int? installedCount,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BundledSourcesSheet(
          plugins: const [_netease, _kuwo],
          installedVersions: installed,
          installedCount: installedCount ?? installed.length,
          onInstall: onInstall,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('未安装时列出全部内置音源并提供安装按钮', (tester) async {
    final tapped = <BundledPlugin>[];
    await pump(tester, installed: const {}, onInstall: tapped.add);

    expect(find.text('网易云音乐'), findsOneWidget);
    expect(find.text('酷我音乐'), findsOneWidget);
    expect(find.textContaining('Thomas喲'), findsOneWidget); // 第三方署名
    expect(find.text('安装'), findsNWidgets(2));
    expect(find.text('全部安装'), findsOneWidget);

    await tester.tap(find.text('安装').first);
    await tester.pumpAndSettle();
    expect(tapped.single.platform, 'netease');
  });

  testWidgets('版本一致显示「已安装」且不可点', (tester) async {
    await pump(
      tester,
      installed: const {'netease': '2025.09.14'},
      onInstall: (_) {},
    );
    expect(find.text('已安装'), findsOneWidget);
    expect(find.text('安装'), findsOneWidget); // 只剩酷我可装
  });

  testWidgets('已装版本不同显示「更新」并列出两个版本', (tester) async {
    await pump(
      tester,
      installed: const {'netease': '2025.01.01'},
      onInstall: (_) {},
    );
    expect(find.text('更新'), findsOneWidget);
    expect(find.textContaining('2025.01.01'), findsOneWidget);
    expect(find.textContaining('2025.09.14'), findsOneWidget);
  });

  testWidgets('全部安装把未安装/可更新的条目都回调出去', (tester) async {
    final tapped = <BundledPlugin>[];
    await pump(
      tester,
      installed: const {'netease': '2025.01.01'},
      onInstall: tapped.add,
    );
    await tester.tap(find.text('全部安装'));
    await tester.pumpAndSettle();
    expect(tapped.map((p) => p.platform), ['netease', 'kuwo']);
  });

  testWidgets('全部装好时隐藏「全部安装」', (tester) async {
    await pump(
      tester,
      installed: const {'netease': '2025.09.14', 'kuwo': '0.1.0'},
      onInstall: (_) {},
    );
    expect(find.text('全部安装'), findsNothing);
    expect(find.text('已安装'), findsNWidgets(2));
  });
}
