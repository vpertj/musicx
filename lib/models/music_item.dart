class MusicItem {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String? artwork;
  final int? duration;
  final String platform;
  final String songId;
  final Map<String, dynamic>? extra;

  const MusicItem({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.artwork,
    this.duration,
    required this.platform,
    required this.songId,
    this.extra,
  });

  factory MusicItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final platform = json['platform'];
    final songId = json['songId'];
    if (id is! String || title is! String || platform is! String || songId is! String) {
      throw ArgumentError('MusicItem requires id/title/platform/songId: $json');
    }
    return MusicItem(
      id: id,
      title: title,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      artwork: json['artwork'] as String?,
      duration: json['duration'] as int?,
      platform: platform,
      songId: songId,
      extra: (json['extra'] as Map<String, dynamic>?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'artist': artist, 'album': album,
        'artwork': artwork, 'duration': duration,
        'platform': platform, 'songId': songId, 'extra': extra,
      };
}
