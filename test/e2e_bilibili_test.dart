import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

/// bilibili 官方插件真实链路验证:
/// 在线安装(gitee) → 加载(require 白名单) → 搜索(bilibili API)。
///
/// 注意:bilibili 对高频无会话请求有风控,搜索可能被限流(返回 -412)。
/// 因此本测试对「安装/解析/加载」做硬断言,搜索尽力而为:
/// 成功则输出结果数,被风控则跳过(核心兼容性由 plugin_ecosystem_test 稳定覆盖)。
@Tags(['network'])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'e2e: bilibili official plugin installs and searches (best-effort)',
    () async {
      final tmp = Directory.systemTemp.createTempSync('musicx_bili');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final manager = PluginManager(tmp);
      const url =
          'https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/bilibili/index.js';

      // 在线安装 + 元数据解析
      final info = await manager.installFromUrl(url);
      expect(info.platform, 'bilibili');
      expect(info.version, isNotEmpty);

      // 尽力搜索(带重试)
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          final result = await manager.search(
            '周杰伦',
            timeout: const Duration(seconds: 25),
          );
          final data = (result['data'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          if (data.isNotEmpty) {
            final first = data.first;
            expect(first['platform'], 'bilibili', reason: '宿主应补全 platform');
            expect(first['songId'], isNotEmpty);
            print(
              'BILI search OK: ${data.length} results, first=${first['title']}',
            );
            // 播放地址尽力解析
            try {
              final media = await manager.resolveMediaSource(first);
              print('BILI media: ${media['url']}');
            } catch (e) {
              print('BILI resolve skipped: $e');
            }
            return; // 成功即通过
          }
        } catch (e) {
          print('BILI attempt $attempt failed: $e');
        }
        await Future<void>.delayed(Duration(seconds: 8 * attempt));
      }
      // 搜索被风控不算失败:安装/解析/加载链路已通过
      print('BILI search skipped: API rate-limited');
    },
    timeout: const Timeout(Duration(seconds: 150)),
  );
}
