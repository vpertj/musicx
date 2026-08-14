import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:musicx/core/search/search_controller.dart'
    show pluginManagerProvider;
import 'package:musicx/models/downloaded_song.dart';
import 'package:musicx/models/music_item.dart';

/// 下载管理:下载歌曲、记录列表、本地删除。状态持久化到 ~/.musicx/downloads.json。
final downloadControllerProvider =
    NotifierProvider<DownloadController, List<DownloadedSong>>(
      DownloadController.new,
    );

class DownloadController extends Notifier<List<DownloadedSong>> {
  /// 下载目录:优先 ~/Downloads/MusicX(沙箱已关闭),退回临时目录。
  static Directory downloadDir() {
    final home = Platform.environment['HOME'];
    final candidates = <Directory>[
      if (home != null) Directory('$home/Downloads/MusicX'),
      Directory('${Directory.systemTemp.path}/musicx_downloads'),
    ];
    for (final d in candidates) {
      try {
        if (!d.existsSync()) d.createSync(recursive: true);
        final probe = File('${d.path}/.write_test');
        probe.writeAsStringSync('ok');
        probe.deleteSync();
        return d;
      } catch (_) {
        // 尝试下一个
      }
    }
    return Directory.systemTemp;
  }

  static File _dataFile() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final dir = Directory('$home/.musicx');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}/downloads.json');
    }
    return File('${Directory.systemTemp.path}/musicx_data/downloads.json');
  }

  @override
  List<DownloadedSong> build() {
    try {
      final f = _dataFile();
      if (f.existsSync()) {
        final list = (jsonDecode(f.readAsStringSync()) as List)
            .whereType<Map<String, dynamic>>()
            .map(DownloadedSong.fromJson)
            .where((d) => File(d.filePath).existsSync()) // 文件丢失则过滤
            .toList();
        return list;
      }
    } catch (_) {}
    return [];
  }

  void _save() {
    try {
      _dataFile().writeAsStringSync(
        jsonEncode(state.map((d) => d.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// 下载歌曲,加入列表并返回保存路径。
  Future<String> download(MusicItem song, String quality) async {
    final manager = ref.read(pluginManagerProvider);
    final media = await manager.resolveMediaSource(
      song.toJson(),
      quality: quality,
      timeout: const Duration(seconds: 15),
    );
    final url = media['url'] as String;
    if (url.isEmpty) {
      throw Exception('无法解析播放地址(可能为付费/下架歌曲)');
    }

    final client = http.Client();
    try {
      final resp = await client
          .get(Uri.parse(url), headers: const {'user-agent': 'MusicX/1.0'})
          .timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) {
        throw HttpException('下载失败:HTTP ${resp.statusCode}');
      }
      final dir = downloadDir();
      final base = '${song.artist ?? '未知歌手'} - ${song.title}';
      final safe = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final file = File('${dir.path}/$safe.mp3');
      await file.writeAsBytes(resp.bodyBytes, flush: true);

      state = [
        DownloadedSong(
          song: song,
          filePath: file.path,
          quality: quality,
          time: DateTime.now(),
        ),
        ...state.where((d) => d.filePath != file.path),
      ];
      _save();
      return file.path;
    } finally {
      client.close();
    }
  }

  /// 删除下载记录及本地文件。
  void remove(DownloadedSong item) {
    try {
      final f = File(item.filePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    state = state.where((d) => d.filePath != item.filePath).toList();
    _save();
  }
}
