import 'dart:async';
import 'package:just_audio/just_audio.dart';

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

  Future<void> playUrl(String url) async {
    // 先停止旧播放,避免加载被打断抛 PlayerInterruptedException
    await _player.stop();
    await _player.setUrl(url);
    // 注意:just_audio 的 play() 要等暂停/播完才返回,不能 await,
    // 否则后续状态更新永远执行不到。播放状态经 playerStateStream 回调。
    unawaited(_player.play());
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
