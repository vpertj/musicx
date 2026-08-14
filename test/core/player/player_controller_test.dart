import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/models/music_item.dart';

void main() {
  // 控制器 build 会实例化 PlayerService(just_audio),需要绑定平台通道
  TestWidgetsFlutterBinding.ensureInitialized();

  MusicItem _song(int i) =>
      MusicItem(id: '$i', title: '歌$i', platform: 'demo', songId: '$i');

  test('playFromList sets queue and current index', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(playerControllerProvider.notifier);
    ctrl.playFromList([_song(1), _song(2)], 0);
    final s = container.read(playerControllerProvider);
    expect(s.queue, hasLength(2));
    expect(s.currentIndex, 0);
    expect(s.queue[0].title, '歌1');
  });

  test('next/previous move index within bounds', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(playerControllerProvider.notifier);
    ctrl.playFromList([_song(1), _song(2)], 0);
    ctrl.next();
    expect(container.read(playerControllerProvider).currentIndex, 1);
    ctrl.next();
    expect(container.read(playerControllerProvider).currentIndex, 1); // 不越界
    ctrl.previous();
    ctrl.previous();
    expect(container.read(playerControllerProvider).currentIndex, 0); // 不越界
  });
}
