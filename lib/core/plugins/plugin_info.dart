class PluginInfo {
  final String platform;
  final String version;
  final String? srcUrl;
  final String hash;
  final String path;
  final bool enabled;

  const PluginInfo({
    required this.platform,
    required this.version,
    this.srcUrl,
    required this.hash,
    required this.path,
    this.enabled = true,
  });

  factory PluginInfo.fromJsMeta(
    Map<String, dynamic> meta, {
    required String hash,
    required String path,
    bool enabled = true,
  }) {
    final platform = meta['platform'];
    final version = meta['version'];
    if (platform is! String || platform.isEmpty ||
        version is! String || version.isEmpty) {
      throw ArgumentError('Plugin requires non-empty platform and version: $meta');
    }
    return PluginInfo(
      platform: platform,
      version: version,
      srcUrl: meta['srcUrl'] as String?,
      hash: hash,
      path: path,
      enabled: enabled,
    );
  }
}

/// 版本对比,规则与 MusicFree 一致:分段比较,非数字段按 0。
int compareVersions(String a, String b) {
  final as = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final bs = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final len = as.length > bs.length ? as.length : bs.length;
  for (var i = 0; i < len; i++) {
    final av = i < as.length ? as[i] : 0;
    final bv = i < bs.length ? bs[i] : 0;
    if (av != bv) return av > bv ? 1 : -1;
  }
  return 0;
}
