class ArtistItem {
  final String id;
  final String name;
  final String platform;
  final String? artwork;
  final Map<String, dynamic>? extra;

  const ArtistItem({
    required this.id,
    required this.name,
    required this.platform,
    this.artwork,
    this.extra,
  });

  factory ArtistItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final platform = json['platform'];
    if (id is! String || name is! String || platform is! String) {
      throw ArgumentError('ArtistItem requires id/name/platform: $json');
    }
    return ArtistItem(
      id: id,
      name: name,
      platform: platform,
      artwork: json['artwork'] as String?,
      extra: (json['extra'] as Map<String, dynamic>?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'platform': platform,
        'artwork': artwork, 'extra': extra,
      };
}
