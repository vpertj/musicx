// 真机探针:直接调用诊断采集逻辑,把真机实际读到的数据打印出来。
// 这是排查「真机提示已是最新版本但确实有新版本」的关键证据来源。
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:musicx/ui/plugins/update_diagnostics.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probe diagnostics on device', (tester) async {
    final text = await UpdateDiagnostics.collect();
    for (final line in text.split('\n')) {
      debugPrint('DIAG| $line');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
