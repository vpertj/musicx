// test/core/updater/update_row_version_test.dart
//
// 用户反馈「应用里面没有版本号」:根因是 UI 用的是同步版
// UpdateService.currentVersion(),它在安卓只认 macOS Info.plist,恒为 0.0.0。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/update_controller.dart';
import 'package:musicx/core/updater/update_service.dart';
import 'package:musicx/ui/plugins/update_row.dart';

/// 假的更新服务:只覆写版本解析(不联网)。
class _FakeUpdateService extends UpdateService {
  _FakeUpdateService(this.version);

  final String version;

  @override
  Future<String> resolveCurrentVersion() async => version;
}

void main() {
  testWidgets('更新行显示真实版本号(而非 0.0.0)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateServiceProvider.overrideWithValue(_FakeUpdateService('1.7.10')),
        ],
        child: const MaterialApp(home: Scaffold(body: UpdateRow())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('v1.7.10'), findsOneWidget,
        reason: '应显示解析出的真实版本号');
    expect(find.textContaining('0.0.0'), findsNothing,
        reason: '不能把 macOS 专用的 0.0.0 显示给用户');
  });

  test('knownVersion 在无法解析时返回 null(不把 0.0.0 当版本)', () {
    // 测试环境无 Info.plist/平台通道 → 不应返回 0.0.0
    expect(UpdateService.knownVersion(), isNot('0.0.0'));
  });
}
