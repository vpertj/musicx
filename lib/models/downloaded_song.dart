import 'music_item.dart';

/// 已下载的歌曲记录。
class DownloadedSong {
  final MusicItem song;
  final String filePath;
  final String quality;
  final DateTime time;

  const DownloadedSong({
    required this.song,
    required this.filePath,
    required this.quality,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
    'song': song.toJson(),
    'filePath': filePath,
    'quality': quality,
    'time': time.millisecondsSinceEpoch,
  };

  factory DownloadedSong.fromJson(Map<String, dynamic> json) {
    return DownloadedSong(
      song: MusicItem.fromJson((json['song'] as Map).cast<String, dynamic>()),
      filePath: json['filePath'] as String,
      quality: (json['quality'] as String?) ?? 'standard',
      time: DateTime.fromMillisecondsSinceEpoch(
        (json['time'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
