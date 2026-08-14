import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/models/playlist.dart';

/// 音乐库状态:我喜欢的音乐 + 自定义歌单。
class LibraryState {
  final List<MusicItem> favorites;
  final List<Playlist> playlists;

  const LibraryState({this.favorites = const [], this.playlists = const []});

  LibraryState copyWith({
    List<MusicItem>? favorites,
    List<Playlist>? playlists,
  }) {
    return LibraryState(
      favorites: favorites ?? this.favorites,
      playlists: playlists ?? this.playlists,
    );
  }
}

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);

class LibraryController extends Notifier<LibraryState> {
  /// 数据文件位置:用户数据目录(稳定)。
  static File dataFile() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final dir = Directory('$home/.musicx');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}/library.json');
    }
    final dir = Directory('${Directory.systemTemp.path}/musicx_data');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/library.json');
  }

  @override
  LibraryState build() {
    // 启动时从磁盘加载
    try {
      final file = dataFile();
      if (file.existsSync()) {
        final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final favorites = ((map['favorites'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MusicItem.fromJson)
            .toList();
        final playlists = ((map['playlists'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Playlist.fromJson)
            .toList();
        return LibraryState(favorites: favorites, playlists: playlists);
      }
    } catch (_) {
      // 数据损坏则从空库开始
    }
    return const LibraryState();
  }

  void _save(LibraryState s) {
    try {
      dataFile().writeAsStringSync(
        jsonEncode({
          'favorites': s.favorites.map((e) => e.toJson()).toList(),
          'playlists': s.playlists.map((e) => e.toJson()).toList(),
        }),
      );
    } catch (_) {
      // 持久化失败不阻塞
    }
  }

  void _update(LibraryState next) {
    state = next;
    _save(next);
  }

  /// 喜欢/取消喜欢(按 id+platform 判重)。
  void toggleFavorite(MusicItem song) {
    final favs = List<MusicItem>.of(state.favorites);
    final idx = favs.indexWhere(
      (s) => s.id == song.id && s.platform == song.platform,
    );
    if (idx >= 0) {
      favs.removeAt(idx);
    } else {
      favs.insert(0, song);
    }
    _update(state.copyWith(favorites: favs));
  }

  bool isFavorite(MusicItem song) {
    return state.favorites.any(
      (s) => s.id == song.id && s.platform == song.platform,
    );
  }

  /// 新建歌单。
  Playlist createPlaylist(String name) {
    final p = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now(),
    );
    _update(state.copyWith(playlists: [...state.playlists, p]));
    return p;
  }

  /// 重命名歌单。
  void renamePlaylist(String id, String name) {
    _update(
      state.copyWith(
        playlists: [
          for (final p in state.playlists)
            if (p.id == id) p.copyWith(name: name) else p,
        ],
      ),
    );
  }

  /// 删除歌单。
  void deletePlaylist(String id) {
    _update(
      state.copyWith(
        playlists: state.playlists.where((p) => p.id != id).toList(),
      ),
    );
  }

  /// 添加歌曲到歌单(已存在则忽略)。
  void addSongToPlaylist(String playlistId, MusicItem song) {
    _update(
      state.copyWith(
        playlists: [
          for (final p in state.playlists)
            if (p.id == playlistId)
              p.songs.any((s) => s.id == song.id && s.platform == song.platform)
                  ? p
                  : p.copyWith(songs: [...p.songs, song])
            else
              p,
        ],
      ),
    );
  }

  /// 从歌单移除歌曲。
  void removeSongFromPlaylist(String playlistId, MusicItem song) {
    _update(
      state.copyWith(
        playlists: [
          for (final p in state.playlists)
            if (p.id == playlistId)
              p.copyWith(
                songs: p.songs
                    .where(
                      (s) => !(s.id == song.id && s.platform == song.platform),
                    )
                    .toList(),
              )
            else
              p,
        ],
      ),
    );
  }
}
