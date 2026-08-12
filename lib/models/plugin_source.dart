/// 订阅源中的插件条目(MusicFree 兼容格式)。
class PluginSource {
  final String name;
  final String url;
  final String version;

  const PluginSource({
    required this.name,
    required this.url,
    required this.version,
  });

  factory PluginSource.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final url = json['url'];
    final version = json['version'] ?? '';
    if (name is! String || name.isEmpty || url is! String || url.isEmpty) {
      throw const FormatException('plugin source requires name and url');
    }
    return PluginSource(name: name, url: url, version: version);
  }
}
