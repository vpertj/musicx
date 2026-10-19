import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// 通知栏 / 锁屏要展示的当前曲目信息。
///
/// 为什么单独成类:播放服务只管"放什么地址",元数据由控制层给;用值对象而不是
/// 一串可选参数,避免调用点漏传或顺序搞错。
class NowPlaying {
  const NowPlaying({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.artwork,
    this.duration,
  });

  /// 唯一标识(通知栏据此去重;同一首歌重复播也用不同值更安全)。
  final String id;
  final String title;
  final String? artist;
  final String? album;

  /// 封面地址(http/https/file)。
  final String? artwork;
  final Duration? duration;

  MediaItem toMediaItem() {
    final art = artwork?.trim() ?? '';
    final artUri = art.isEmpty ? null : Uri.tryParse(art);
    return MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artUri: artUri != null && artUri.hasScheme ? artUri : null,
    );
  }
}

class PlayerService {
  final AudioPlayer _player = AudioPlayer();
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _completed = StreamController<void>.broadcast();

  PlayerService() {
    _player.playerStateStream.listen((state) {
      if (!_playing.isClosed) _playing.add(state.playing);
      if (state.processingState == ProcessingState.completed) {
        if (!_completed.isClosed) _completed.add(null);
      }
    });
    _player.positionStream.listen((pos) {
      if (!_position.isClosed) _position.add(pos);
    });
    _player.durationStream.listen((d) {
      if (!_duration.isClosed) _duration.add(d);
    });
  }

  Stream<bool> get playingStream => _playing.stream;
  Stream<Duration> get positionStream => _position.stream;
  Stream<Duration?> get durationStream => _duration.stream;
  Stream<void> get completedStream => _completed.stream;
  Duration? get duration => _player.duration;

  /// 播放指定地址。
  ///
  /// 必须带 [NowPlaying] 元数据:just_audio_background 要求每个音源都挂
  /// [MediaItem] 标签 —— 通知栏/锁屏的标题、封面、以及"锁屏下继续播"都依赖它。
  /// (此前用 setUrl,没有前台服务也没有元数据,息屏后播放会被系统冻结。)
  Future<void> playUrl(String url, {NowPlaying? nowPlaying}) async {
    // 先停止旧播放,避免加载被打断抛 PlayerInterruptedException
    await _player.stop();
    final source = AudioSource.uri(
      Uri.parse(url),
      tag: (nowPlaying ??
              NowPlaying(id: url, title: ''))
          .toMediaItem(),
    );
    await _player.setAudioSource(source);
    // 注意:just_audio 的 play() 要等暂停/播完才返回,不能 await,
    // 否则后续状态更新永远执行不到。播放状态经 playerStateStream 回调。
    // 捕获其 Future 异常,避免播放失败时被静默吞掉(至少记录日志)。
    unawaited(
      _player.play().catchError((Object e) {
        debugPrint('MusicX: 播放失败: $e');
      }),
    );
  }

  Future<void> pause() async {
    if (_player.playing) {
      await _player.pause();
    }
  }

  Future<void> resume() async {
    await _player.play();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> stop() async {
    await _player.stop();
  }

  void dispose() {
    _playing.close();
    _position.close();
    _duration.close();
    _completed.close();
    _player.dispose();
  }
}
