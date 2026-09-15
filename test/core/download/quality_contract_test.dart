// test/core/download/quality_contract_test.dart
//
// 契约测试:下载音质选项的取值必须与内置音源插件的质量映射一致。
// 背景:此前「标准」传 standard(插件映射到 320k)、「高品」传 high(实际 FLAC)
// —— 标注与实际不符。这里把映射钉住,避免以后又对不上。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('下载选项取值必须存在于内置源的质量映射', () async {
    final js = await rootBundle.loadString('assets/plugins/kuwo_nianxin.js');
    for (final v in ['low', 'standard', 'high', 'super']) {
      expect(
        js.contains("'$v':"),
        isTrue,
        reason: '应用传入的 quality「$v」必须在插件映射里,否则会回退到 128k',
      );
    }
    // 用户要的「下载 FLAC」:必须有档位映射到 flac
    expect(
      js.contains("'super': 'flac'") || js.contains("'high': 'flac'"),
      isTrue,
      reason: '必须有档位映射到 flac',
    );
  });
}
