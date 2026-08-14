class MusicSheetItem {
  final String id;
  final String title;
  final String platform;
  final String? artwork;
  final Map<String, dynamic>? extra;

  const MusicSheetItem({
    required this.id,
    required this.title,
    required this.platform,
    this.artwork,
    this.extra,
  });

  factory MusicSheetItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final platform = json['platform'];
    if (id is! String || title is! String || platform is! String) {
      throw ArgumentError('MusicSheetItem requires id/title/platform: $json');
    }
    return MusicSheetItem(
      id: id,
      title: title,
      platform: platform,
      artwork: json['artwork'] as String?,
      extra: (json['extra'] as Map<String, dynamic>?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'platform': platform,
    'artwork': artwork,
    'extra': extra,
  };
}
