import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:musicx/core/updater/apk_installer.dart';
import 'package:musicx/core/updater/update_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probe version on device', (tester) async {
    try {
      final v = await ApkInstaller.versionName();
      debugPrint('RESULT: ApkInstaller.versionName=$v');
    } catch (e) {
      debugPrint('RESULT: versionName FAIL=$e');
    }
    debugPrint('RESULT: UpdateService.currentVersion()=${UpdateService.currentVersion()}');
    final resolved = await UpdateService().resolveCurrentVersion();
    debugPrint('RESULT: resolveCurrentVersion=$resolved');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
