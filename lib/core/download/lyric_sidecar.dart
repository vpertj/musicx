/// 歌词旁挂文件(.lrc)的路径与读写。
///
/// 用户诉求:下载歌曲时要**连歌词一起下载**,否则离线播放没有歌词。
/// 方案:在音频文件旁写同名 `.lrc`(如 `周杰伦 - 晴天.mp3` → `周杰伦 - 晴天.lrc`),
/// 本地播放时优先读它 —— 不依赖网络,也不改动音频文件本身。
library;

import 'dart:io';

/// 由音频路径推导同名歌词路径(去掉扩展名后加 .lrc)。
String lrcPathFor(String audioPath) {
  final dot = audioPath.lastIndexOf('.');
  final slash = audioPath.lastIndexOf(Platform.pathSeparator);
  if (dot <= slash) return '$audioPath.lrc';
  return '${audioPath.substring(0, dot)}.lrc';
}

/// 写入歌词旁挂文件(内容为空则不写)。返回是否写入成功。
Future<bool> writeLyricSidecar(String audioPath, String? lyric) async {
  final text = lyric?.trim() ?? '';
  if (text.isEmpty) return false;
  try {
    await File(lrcPathFor(audioPath)).writeAsString(text, flush: true);
    return true;
  } catch (_) {
    return false;
  }
}

/// 读取歌词旁挂文件;不存在或读取失败返回 null。
Future<String?> readLyricSidecar(String audioPath) async {
  try {
    final f = File(lrcPathFor(audioPath));
    if (!await f.exists()) return null;
    final text = await f.readAsString();
    return text.trim().isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}
