import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_info.dart';

void main() {
  test('compareVersions orders correctly', () {
    expect(compareVersions('1.2.4', '1.2.3'), 1);
    expect(compareVersions('2.0.0', '1.99.99'), 1);
    expect(compareVersions('1.2.3', '1.2.3'), 0);
    expect(compareVersions('1.2', '1.2.3'), -1);
    expect(compareVersions('0.9', '0.10'), -1);
  });

  test('PluginInfo.fromJsMeta maps fields', () {
    final info = PluginInfo.fromJsMeta(
      {'platform': 'demo', 'version': '0.1.0', 'srcUrl': 'http://x/p.js'},
      hash: 'deadbeef',
      path: '/tmp/plugins/x.js',
    );
    expect(info.platform, 'demo');
    expect(info.version, '0.1.0');
    expect(info.srcUrl, 'http://x/p.js');
    expect(info.enabled, isTrue);
  });

  test('PluginInfo rejects missing platform/version', () {
    expect(() => PluginInfo.fromJsMeta({'platform': 'x'}, hash: 'h', path: 'p'),
        throwsArgumentError);
  });
}
