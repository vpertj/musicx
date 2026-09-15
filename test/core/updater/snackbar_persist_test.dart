// test/core/updater/snackbar_persist_test.dart
//
// 用户实测:「当前已是最新版本」提示条几秒后不消失,一直挡在屏幕底部。
//
// 根因不在业务逻辑,而在 Material 的一个默认行为:
//   SnackBar(persist: persist ?? action != null)
// 只要带了 `action`(我们在提示上加的「诊断」按钮),SnackBar 就**默认
// 永久停留**,必须显式指定 duration 才会自动消失。
//
// 这个测试锁死:更新相关的提示条必须带显式 duration。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/updater/update_controller.dart';
import 'package:musicx/core/updater/update_service.dart';
import 'package:musicx/ui/plugins/update_row.dart';

/// 假服务:永远报告"已是最新",用来复现用户看到的那条提示。
class _NoUpdateService extends UpdateService {
  @override
  Future<String> resolveCurrentVersion() async => '1.7.42';

  @override
  Future<UpdateInfo> checkForUpdate() async => const UpdateInfo(
    latestVersion: '1.7.42',
    currentVersion: '1.7.42',
    dmgUrl: 'https://example.com/a.apk',
    releaseUrl: 'https://example.com',
  );
}

void main() {
  Future<void> pumpRow(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateServiceProvider.overrideWithValue(_NoUpdateService()),
        ],
        child: const MaterialApp(home: Scaffold(body: UpdateRow())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('「已是最新版本」提示条会自行消失(不永久停留)', (tester) async {
    await pumpRow(tester);

    // 点「检查更新」行 → 触发手动检查 → 无更新 → 弹提示条
    await tester.tap(find.byType(UpdateRow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 文案带版本号(来自 controller 的 error 分支)
    expect(
      find.textContaining('当前已是最新版本'),
      findsOneWidget,
      reason: '应弹出「已是最新版本」提示条',
    );

    // 关键:推进超过 duration 后必须消失。
    //
    // 注意必须**逐帧推进**:单次 pump(大跨度)会直接跳过 Timer 与退场动画,
    // 让"其实已修好"的实现也显示为仍存在。
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(
      find.textContaining('当前已是最新版本'),
      findsNothing,
      reason: '提示条必须自动消失。Material 规则 persist = persist ?? action != null,'
          '带 action 时只给 duration 无效,必须显式 persist: false',
    );
  });

  testWidgets('提示条仍保留「诊断」入口(修 duration 不能把它弄丢)', (tester) async {
    await pumpRow(tester);

    await tester.tap(find.byType(UpdateRow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('诊断'), findsOneWidget,
        reason: '诊断按钮是排查真机问题的关键入口,不能为了自动消失而删掉');
  });
}
