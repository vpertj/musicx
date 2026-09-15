// test/core/download/lyric_sidecar_test.dart
//
// 用户诉求:下载歌曲要连歌词一起下。这里锁住旁挂 .lrc 的命名与读写。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/download/lyric_sidecar.dart';

void main() {
  test('歌词路径:去掉扩展名后加 .lrc', () {
    expect(lrcPathFor('/music/周杰伦 - 晴天.mp3'), '/music/周杰伦 - 晴天.lrc');
    expect(lrcPathFor('/music/a.flac'), '/music/a.lrc');
    // 无扩展名:直接追加
    expect(lrcPathFor('/music/noext'), '/music/noext.lrc');
  });

  test('写入后可读回;空歌词不写文件', () async {
    final dir = Directory.systemTemp.createTempSync('mx_lrc');
    addTearDown(() => dir.deleteSync(recursive: true));
    final audio = '${dir.path}/歌手 - 歌名.mp3';

    expect(await writeLyricSidecar(audio, ''), isFalse);
    expect(await File(lrcPathFor(audio)).exists(), isFalse);

    final ok = await writeLyricSidecar(audio, '[00:01.00]第一句');
    expect(ok, isTrue);
    expect(await readLyricSidecar(audio), '[00:01.00]第一句');
  });

  test('没有旁挂文件时返回 null(不影响播放)', () async {
    final dir = Directory.systemTemp.createTempSync('mx_lrc2');
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(await readLyricSidecar('${dir.path}/none.mp3'), isNull);
  });
}
