import 'music_item.dart';

/// 自定义歌单。
class Playlist {
  final String id;
  final String name;
  final List<MusicItem> songs;
  final DateTime createdAt;

  const Playlist({
    required this.id,
    required this.name,
    this.songs = const [],
    required this.createdAt,
  });

  Playlist copyWith({String? name, List<MusicItem>? songs}) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      songs: songs ?? this.songs,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'songs': songs.map((s) => s.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0),
      songs: ((json['songs'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MusicItem.fromJson)
          .toList(),
    );
  }
}
