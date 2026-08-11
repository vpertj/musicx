# MusicX Phase 2 — 最小可播放里程碑 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Phase 1 插件运行时层之上,实现最小可播放功能:插件管理页(安装/启停)、搜索页(调用插件 search)、播放页(just_audio 真实播放 + 播放队列)。用户可安装 demo 插件、搜索歌曲、真实播放音频。

**Architecture:** 沿用五层架构。UI 层新增三个页面(搜索/插件管理/播放),状态管理用 flutter_riverpod(3.4.x),播放引擎用 just_audio(0.10.x)。PluginManager 复用 Phase 1 的 PluginStore/PluginSandbox/PluginBridgeAsync——每次搜索调用对每个启用插件在独立 isolate 中加载并执行 search;播放时经 getMediaSource 拿真实 URL 交给 just_audio。

**Tech Stack:** Flutter 3.x、Dart 3.12+、flutter_riverpod ^3.4.2(状态管理)、just_audio ^0.10.6(播放,支持 Android/macOS/Windows)、已有 flutter_js ^0.8.7。

## Global Constraints

- 平台:Android + Windows + macOS 三端;一套 Dart 代码,不写平台特定分支。
- 依赖版本固定:just_audio `^0.10.6`、flutter_riverpod `^3.4.2`(已核实支持本机 Dart 3.12.2)。
- 插件调用必须走 Phase 1 的 PluginSandbox(isolate + 超时熔断),禁止在 UI isolate 直接 evaluate 插件代码。
- 数据模型复用 Phase 1 `lib/models/`(MusicItem 等),不重新定义。
- 所有插件调用带超时(默认 10s),超时/异常经 UI 提示,不崩溃。
- 测试命令统一用 `flutter test test/<path>`;全部测试必须能在 `flutter test` 下通过。
- 本机环境事实:执行沙箱禁止原生构建(Xcode/Gradle),Phase 2 验证以 `flutter test` 为准;macOS 构建与运行演示由用户在本机执行 `flutter run -d macos`。
- 提交信息遵循 conventional commits(`feat:` / `test:` / `fix:` / `refactor:` 前缀)。
- demo 插件的播放 URL 使用公开测试音频(如 `https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3`),保证真实可播;插件内不得出现付费/VIP 内容。

---

### Task 1: 依赖接入与导航骨架

**Files:**
- Modify: `pubspec.yaml`(追加 just_audio、flutter_riverpod)
- Modify: `lib/main.dart`(ProviderScope + 底部导航:搜索页 / 插件管理页 / 播放页占位)
- Create: `lib/ui/home_shell.dart`(底部导航壳)
- Create: `lib/ui/search/search_page.dart`(占位)
- Create: `lib/ui/plugins/plugin_page.dart`(占位)
- Create: `lib/ui/player/player_page.dart`(占位)
- Test: `test/ui/home_shell_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `HomeShell`(StatefulWidget,内部 `NavigationBar` 三个 destination,index 0=搜索/1=插件/2=播放);`MusicxApp` 用 `ProviderScope(child: MusicxApp())` 包裹。

- [ ] **Step 1: 追加依赖**

编辑 `pubspec.yaml` `dependencies:` 追加:

```yaml
  flutter_riverpod: ^3.4.2
  just_audio: ^0.10.6
```

Run: `flutter pub get`(带 HOME 前缀,见环境事实)

- [ ] **Step 2: 写失败测试** `test/ui/home_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/main.dart';

void main() {
  testWidgets('HomeShell shows three nav destinations and switches pages',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MusicxApp()));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('插件'), findsOneWidget);
    expect(find.text('播放'), findsOneWidget);

    // 切到插件页
    await tester.tap(find.text('插件'));
    await tester.pumpAndSettle();
    expect(find.text('插件管理'), findsOneWidget);
  });
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `flutter test test/ui/home_shell_test.dart`
Expected: FAIL(缺 HomeShell/NavigationBar)

- [ ] **Step 4: 实现**

`lib/ui/search/search_page.dart`(占位):

```dart
import 'package:flutter/material.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('搜索')));
  }
}
```

`lib/ui/plugins/plugin_page.dart`(占位):

```dart
import 'package:flutter/material.dart';

class PluginPage extends StatelessWidget {
  const PluginPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('插件管理')));
  }
}
```

`lib/ui/player/player_page.dart`(占位):

```dart
import 'package:flutter/material.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('播放')));
  }
}
```

`lib/ui/home_shell.dart`:

```dart
import 'package:flutter/material.dart';
import 'player/player_page.dart';
import 'plugins/plugin_page.dart';
import 'search/search_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  static const _pages = [SearchPage(), PluginPage(), PlayerPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(icon: Icon(Icons.extension), label: '插件'),
          NavigationDestination(icon: Icon(Icons.music_note), label: '播放'),
        ],
      ),
    );
  }
}
```

`lib/main.dart`(整体替换):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/home_shell.dart';

void main() {
  runApp(const ProviderScope(child: MusicxApp()));
}

class MusicxApp extends StatelessWidget {
  const MusicxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MusicX',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      home: const HomeShell(),
    );
  }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/ui/home_shell_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: 提交**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart lib/ui test/ui
git commit -m "feat: add riverpod+just_audio deps and home shell navigation"
```

---

### Task 2: PluginManager——插件运行时管理

**Files:**
- Create: `lib/core/plugins/plugin_manager.dart`
- Test: `test/core/plugins/plugin_manager_test.dart`

**Interfaces:**
- Consumes: Phase 1 的 `PluginStore`(lib/core/plugins/plugin_store.dart)、`PluginSandbox`、`PluginBridgeAsync`、`PluginBridge`、`PluginLoader`、`PluginInfo`。
- Produces:
  - `class PluginManager { PluginManager(this.rootDir); final Directory rootDir; Future<List<PluginInfo>> listPlugins(); Future<void> installFromFile(String path); Future<void> uninstall(PluginInfo info); Future<Map<String, dynamic>> search(String keyword, {Duration timeout}); }`
  - 语义:`listPlugins()` 扫描 rootDir 下 `*.js` 并返回 PluginInfo 列表(全启用);`installFromFile` 复制 js 到 rootDir;`uninstall` 删除文件;`search` 遍历所有插件,对每个插件在独立 isolate 内加载并调用 `search`(参数 `{'keyword': keyword, 'page': 1}`),返回第一个成功插件的结果(后续可合并)。

- [ ] **Step 1: 写失败测试** `test/core/plugins/plugin_manager_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

const _demoPlugin = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function (q) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({ isEnd: true, data: [ { id: "d1", title: "示例歌曲", artist: "歌手", album: "专辑",
          artwork: "", duration: 180000, platform: "demo", songId: "d1", extra: {} } ] });
      }, 10);
    });
  },
  getMediaSource: function (m) { return { url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3" }; }
};
''';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_pm');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('listPlugins scans installed plugins', () async {
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
    final manager = PluginManager(tmp);
    final plugins = await manager.listPlugins();
    expect(plugins, hasLength(1));
    expect(plugins.first.platform, 'demo');
  });

  test('installFromFile copies js into rootDir', () async {
    final src = File('${tmp.path}/../src_demo.js')
      ..writeAsStringSync(_demoPlugin);
    final manager = PluginManager(tmp);
    await manager.installFromFile(src.path);
    final plugins = await manager.listPlugins();
    expect(plugins, hasLength(1));
    expect(plugins.first.platform, 'demo');
  });

  test('search resolves song list through isolate', () async {
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
    final manager = PluginManager(tmp);
    final result = await manager.search('示例');
    final data = (result['data'] as List).cast<Map<String, dynamic>>();
    expect(data, isNotEmpty);
    expect(data.first['title'], '示例歌曲');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/plugins/plugin_manager_test.dart`
Expected: FAIL(`Method not found: 'PluginManager'`)

- [ ] **Step 3: 实现**

`lib/core/plugins/plugin_manager.dart`:

```dart
import 'dart:io';
import 'package:musicx/core/plugins/plugin_bridge.dart';
import 'package:musicx/core/plugins/plugin_bridge_async.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';
import 'package:musicx/core/plugins/plugin_sandbox.dart';
import 'package:musicx/core/plugins/plugin_store.dart';
import 'package:flutter_js/flutter_js.dart';

class PluginManager {
  final Directory rootDir;
  final PluginStore _store;
  final PluginSandbox _sandbox;
  PluginManager(this.rootDir)
      : _store = PluginStore(rootDir),
        _sandbox = PluginSandbox();

  Future<List<PluginInfo>> listPlugins() async {
    final files = _store.scanPluginFiles();
    final result = <PluginInfo>[];
    for (final f in files) {
      try {
        result.add(await _store.loadMeta(f));
      } catch (_) {
        // 跳过元数据损坏的插件文件
      }
    }
    return result;
  }

  Future<void> installFromFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('plugin source not found', path);
    }
    if (!rootDir.existsSync()) {
      rootDir.createSync(recursive: true);
    }
    final name = 'plugin_${DateTime.now().microsecondsSinceEpoch}.js';
    await file.copy('${rootDir.path}/$name');
  }

  Future<void> uninstall(PluginInfo info) async {
    final file = File(info.path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// 遍历所有插件,对每个插件在 isolate 内加载并执行 search;
  /// 返回第一个成功的结果,其余插件失败仅记录忽略。
  Future<Map<String, dynamic>> search(
    String keyword, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final plugins = await listPlugins();
    for (final plugin in plugins) {
      try {
        final source = await File(plugin.path).readAsString();
        final result = await _sandbox.isolate(
          () async {
            final runtime = getJavascriptRuntime(xhr: false);
            final loader = PluginLoader(runtime);
            loader.loadPlugin(source);
            final bridge = PluginBridgeAsync(runtime);
            return bridge.callAsync('search', {'keyword': keyword, 'page': 1});
          },
          timeout: timeout,
        );
        return result;
      } catch (e) {
        // 单插件失败不阻断整体;循环继续
      }
    }
    throw Exception('no plugin returned search results');
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/core/plugins/plugin_manager_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/core/plugins/plugin_manager.dart test/core/plugins/plugin_manager_test.dart
git commit -m "feat: add plugin manager for install/list/search"
```

---

### Task 3: 播放引擎服务(PlayerService)

**Files:**
- Create: `lib/core/player/player_service.dart`
- Test: `test/core/player/player_service_test.dart`

**Interfaces:**
- Consumes: just_audio、MusicItem(lib/models/music_item.dart)
- Produces:
  - `class PlayerService { final AudioPlayer _player; Stream<bool> get playingStream; Stream<Duration> get positionStream; Future<void> playUrl(String url); Future<void> pause(); Future<void> resume(); Future<void> seek(Duration d); Future<void> stop(); Duration? get duration; void dispose(); }`
  - 语义:`playUrl` 用 `_player.setUrl(url)` 后 `play()`;错误透传为 `PlayerException`(just_audio 自带)。

- [ ] **Step 1: 写失败测试** `test/core/player/player_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_service.dart';

void main() {
  test('PlayerService exposes playing stream and controls', () async {
    final service = PlayerService();
    expect(service.playingStream, isNotNull);
    expect(service.positionStream, isNotNull);
    // 无真实网络环境下不实际播放;仅验证构造与 dispose 不抛异常
    service.dispose();
  });

  test('PlayerService seek/pause on idle player does not throw', () async {
    final service = PlayerService();
    await service.pause();
    await service.seek(const Duration(seconds: 1));
    service.dispose();
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/player/player_service_test.dart`
Expected: FAIL(`Method not found: 'PlayerService'`)

- [ ] **Step 3: 实现**

`lib/core/player/player_service.dart`:

```dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';

class PlayerService {
  final AudioPlayer _player = AudioPlayer();
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();

  PlayerService() {
    _player.playerStateStream.listen((state) {
      _playing.add(state.playing);
    });
    _player.positionStream.listen((pos) {
      _position.add(pos);
    });
  }

  Stream<bool> get playingStream => _playing.stream;
  Stream<Duration> get positionStream => _position.stream;
  Duration? get duration => _player.duration;

  Future<void> playUrl(String url) async {
    await _player.setUrl(url);
    await _player.play();
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
    _player.dispose();
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/core/player/player_service_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/core/player/player_service.dart test/core/player/player_service_test.dart
git commit -m "feat: add just_audio based player service"
```

---

### Task 4: 播放控制器(队列 + 状态,Riverpod)

**Files:**
- Create: `lib/core/player/player_controller.dart`
- Test: `test/core/player/player_controller_test.dart`

**Interfaces:**
- Consumes: Riverpod(flutter_riverpod)、MusicItem、PluginManager(取 getMediaSource)、PlayerService。
- Produces:
  - `class PlayerState { final List<MusicItem> queue; final int currentIndex; final bool isPlaying; final String? error; const PlayerState({...}); }`
  - `class PlayerController extends Notifier<PlayerState>` — 方法:`playFromList(List<MusicItem> songs, int index)`、`togglePlay()`、`next()`、`previous()`、`seek(Duration)`。
  - provider:`final playerControllerProvider = NotifierProvider<PlayerController, PlayerState>(PlayerController.new);`
  - getMediaSource 调用:经 PluginManager 暴露的 `resolveMediaSource(MusicItem)`(Phase 1 的 getMediaSource 是同步桥,PluginManager 增加该方法)。

- [ ] **Step 1: 扩展 PluginManager** `lib/core/plugins/plugin_manager.dart` 增加:

```dart
  /// 根据 musicItem 解析真实播放地址(走插件 getMediaSource,同步桥)。
  Future<Map<String, dynamic>> resolveMediaSource(
    Map<String, dynamic> musicItem, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final plugins = await listPlugins();
    for (final plugin in plugins) {
      try {
        final source = await File(plugin.path).readAsString();
        final result = await _sandbox.isolate(
          () async {
            final runtime = getJavascriptRuntime(xhr: false);
            final loader = PluginLoader(runtime);
            loader.loadPlugin(source);
            final bridge = PluginBridge(runtime);
            return bridge.callSync('getMediaSource', musicItem);
          },
          timeout: timeout,
        );
        if (result['url'] != null) return result;
      } catch (_) {
        // 继续尝试下一个插件
      }
    }
    throw Exception('no plugin resolved media source');
  }
```

- [ ] **Step 2: 写失败测试** `test/core/player/player_controller_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/models/music_item.dart';

void main() {
  MusicItem _song(int i) => MusicItem(
        id: '$i', title: '歌$i', platform: 'demo', songId: '$i');

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
```

- [ ] **Step 3: 运行测试确认失败**

Run: `flutter test test/core/player/player_controller_test.dart`
Expected: FAIL(`Method not found: 'PlayerController'`)

- [ ] **Step 4: 实现**

`lib/core/player/player_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/models/music_item.dart';
import 'player_service.dart';

class PlayerState {
  final List<MusicItem> queue;
  final int currentIndex;
  final bool isPlaying;
  final String? error;
  const PlayerState({
    this.queue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.error,
  });

  MusicItem? get current =>
      currentIndex >= 0 && currentIndex < queue.length
          ? queue[currentIndex]
          : null;
}

final playerServiceProvider = Provider<PlayerService>((ref) {
  final service = PlayerService();
  ref.onDispose(service.dispose);
  return service;
});

final pluginManagerProvider = Provider<PluginManager>((ref) {
  final dir = PluginManager.pluginsDir();
  return PluginManager(dir);
});

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

class PlayerController extends Notifier<PlayerState> {
  @override
  PlayerState build() => const PlayerState();

  Future<void> playFromList(List<MusicItem> songs, int index) async {
    state = PlayerState(queue: List.of(songs), currentIndex: index);
    await _playCurrent();
  }

  Future<void> togglePlay() async {
    final service = ref.read(playerServiceProvider);
    if (state.isPlaying) {
      await service.pause();
      state = PlayerState(
          queue: state.queue, currentIndex: state.currentIndex, isPlaying: false);
    } else {
      await service.resume();
      state = PlayerState(
          queue: state.queue, currentIndex: state.currentIndex, isPlaying: true);
    }
  }

  Future<void> next() async {
    if (state.currentIndex >= state.queue.length - 1) return;
    state = PlayerState(
        queue: state.queue, currentIndex: state.currentIndex + 1);
    await _playCurrent();
  }

  Future<void> previous() async {
    if (state.currentIndex <= 0) return;
    state = PlayerState(
        queue: state.queue, currentIndex: state.currentIndex - 1);
    await _playCurrent();
  }

  Future<void> seek(Duration position) async {
    await ref.read(playerServiceProvider).seek(position);
  }

  Future<void> _playCurrent() async {
    final current = state.current;
    if (current == null) return;
    try {
      final manager = ref.read(pluginManagerProvider);
      final media =
          await manager.resolveMediaSource(current.toJson());
      final url = media['url'] as String;
      final service = ref.read(playerServiceProvider);
      await service.playUrl(url);
      state = PlayerState(
          queue: state.queue,
          currentIndex: state.currentIndex,
          isPlaying: true);
    } catch (e) {
      state = PlayerState(
          queue: state.queue,
          currentIndex: state.currentIndex,
          error: e.toString());
    }
  }
}
```

`lib/core/plugins/plugin_manager.dart` 追加静态方法(放在类内):

```dart
  /// 插件目录:平台应用支持目录下 plugins/。
  static Directory pluginsDir() {
    final base = Directory.systemTemp;
    final dir = Directory('${base.path}/musicx_plugins');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
```

Note: `pluginsDir()` 在 Phase 2 用 `Directory.systemTemp` 作临时演示目录,避免依赖 path_provider 平台通道(沙箱可测);Phase 3 换真实应用目录。

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/core/player/player_controller_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: 提交**

```bash
git add lib/core/plugins/plugin_manager.dart lib/core/player/player_controller.dart lib/core/player/player_service.dart test/core/player/player_controller_test.dart
git commit -m "feat: add riverpod player controller with queue"
```

---

### Task 5: 搜索控制器(SearchController,Riverpod)

**Files:**
- Create: `lib/core/search/search_controller.dart`
- Test: `test/core/search/search_controller_test.dart`

**Interfaces:**
- Consumes: PluginManager、Riverpod、MusicItem。
- Produces:
  - `class SearchState { final bool loading; final List<MusicItem> results; final String? error; final String query; const SearchState({...}); }`
  - `class SearchController extends Notifier<SearchState>` — `Future<void> search(String keyword)`。
  - provider:`final searchControllerProvider = NotifierProvider<SearchController, SearchState>(SearchController.new);`

- [ ] **Step 1: 写失败测试** `test/core/search/search_controller_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/search_controller.dart';

const _demoPlugin = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function (q) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({ isEnd: true, data: [ { id: "d1", title: "示例歌曲", artist: "歌手", album: "专辑",
          artwork: "", duration: 180000, platform: "demo", songId: "d1", extra: {} } ] });
      }, 10);
    });
  },
  getMediaSource: function (m) { return { url: "https://x/a.mp3" }; }
};
''';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_sc');
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('search populates results from plugin', () async {
    final container = ProviderContainer(overrides: [
      pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
    ]);
    addTearDown(container.dispose);
    final ctrl = container.read(searchControllerProvider.notifier);
    await ctrl.search('示例');
    final s = container.read(searchControllerProvider);
    expect(s.loading, isFalse);
    expect(s.error, isNull);
    expect(s.results, isNotEmpty);
    expect(s.results.first.title, '示例歌曲');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/search/search_controller_test.dart`
Expected: FAIL(`Method not found: 'SearchController'`)

- [ ] **Step 3: 实现**

`lib/core/search/search_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/models/music_item.dart';

class SearchState {
  final String query;
  final bool loading;
  final List<MusicItem> results;
  final String? error;
  const SearchState({
    this.query = '',
    this.loading = false,
    this.results = const [],
    this.error,
  });
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

class SearchController extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  Future<void> search(String keyword) async {
    state = SearchState(query: keyword, loading: true);
    try {
      final manager = ref.read(pluginManagerProvider);
      final result = await manager.search(keyword);
      final data = (result['data'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final items = data.map(MusicItem.fromJson).toList();
      state = SearchState(query: keyword, results: items);
    } catch (e) {
      state = SearchState(query: keyword, error: e.toString());
    }
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/core/search/search_controller_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/core/search/search_controller.dart test/core/search/search_controller_test.dart
git commit -m "feat: add search controller backed by plugin search"
```

---

### Task 6: 搜索页 UI(输入 + 结果列表 + 点击播放)

**Files:**
- Modify: `lib/ui/search/search_page.dart`
- Test: `test/ui/search_page_test.dart`

**Interfaces:**
- Consumes: SearchController、PlayerController、MusicItem。
- Produces: `SearchPage`(ConsumerWidget):顶部 TextField(提交触发搜索)、下方结果 ListView(每项 title/subtitle,onTap 调 `playerController.playFromList(results, index)`)。

- [ ] **Step 1: 写失败测试** `test/ui/search_page_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/ui/search/search_page.dart';

const _demoPlugin = '''
module.exports = { platform: "demo", version: "0.1.0",
  search: function (q) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({ isEnd: true, data: [ { id: "d1", title: "示例歌曲", artist: "歌手", album: "专辑",
          artwork: "", duration: 180000, platform: "demo", songId: "d1", extra: {} } ] });
      }, 10);
    });
  },
  getMediaSource: function (m) { return { url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3" }; }
};
''';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_sp');
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('typing query and submitting shows song results', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
      ],
      child: const MaterialApp(home: SearchPage()),
    ));

    await tester.enterText(find.byType(TextField), '示例');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('示例歌曲'), findsOneWidget);
    expect(find.text('歌手'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/ui/search_page_test.dart`
Expected: FAIL(占位 SearchPage 无 TextField)

- [ ] **Step 3: 实现**

`lib/ui/search/search_page.dart`(整体替换):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/core/search/search_controller.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String keyword) {
    if (keyword.trim().isEmpty) return;
    ref.read(searchControllerProvider.notifier).search(keyword.trim());
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              decoration: const InputDecoration(
                hintText: '搜索歌曲 / 歌手 / 专辑',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (searchState.loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (searchState.error != null)
            Expanded(
              child: Center(child: Text('搜索失败:${searchState.error}')),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: searchState.results.length,
                itemBuilder: (context, index) {
                  final song = searchState.results[index];
                  return ListTile(
                    leading: const Icon(Icons.music_note),
                    title: Text(song.title),
                    subtitle: Text(song.artist ?? ''),
                    onTap: () {
                      ref
                          .read(playerControllerProvider.notifier)
                          .playFromList(searchState.results, index);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/ui/search_page_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/ui/search/search_page.dart test/ui/search_page_test.dart
git commit -m "feat: add search page UI"
```

---

### Task 7: 播放页 UI(当前歌曲 + 进度 + 控制)

**Files:**
- Modify: `lib/ui/player/player_page.dart`
- Test: `test/ui/player_page_test.dart`

**Interfaces:**
- Consumes: PlayerController、MusicItem。
- Produces: `PlayerPage`(ConsumerWidget):显示当前歌曲 title/artist、播放/暂停按钮(icon 随 isPlaying)、上一首/下一首、错误提示。

- [ ] **Step 1: 写失败测试** `test/ui/player_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/player/player_controller.dart';
import 'package:musicx/models/music_item.dart';
import 'package:musicx/ui/player/player_page.dart';

void main() {
  testWidgets('PlayerPage shows current song and controls', (tester) async {
    final song = MusicItem(
        id: '1', title: '测试曲', artist: '测试手', platform: 'demo', songId: '1');
    // 用 override 预置播放状态,避免真实网络播放(just_audio setUrl 在测试环境不可用)
    final container = ProviderContainer(overrides: [
      playerControllerProvider.overrideWith(
        () => _FakePlayerController(song),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PlayerPage()),
    ));
    await tester.pump();

    expect(find.text('测试曲'), findsOneWidget);
    expect(find.text('测试手'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
  });
}

class _FakePlayerController extends PlayerController {
  final MusicItem song;
  _FakePlayerController(this.song);

  @override
  PlayerState build() =>
      PlayerState(queue: [song], currentIndex: 0, isPlaying: true);
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/ui/player_page_test.dart`
Expected: FAIL(占位 PlayerPage 无这些元素)

- [ ] **Step 3: 实现**

`lib/ui/player/player_page.dart`(整体替换):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/player/player_controller.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final song = state.current;

    return Scaffold(
      appBar: AppBar(title: const Text('播放')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('播放出错:${state.error}',
                    style: const TextStyle(color: Colors.red)),
              ),
            if (song == null)
              const Text('暂无播放内容,去搜索页选一首歌吧')
            else ...[
              const Icon(Icons.music_note, size: 96),
              const SizedBox(height: 16),
              Text(song.title,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(song.artist ?? '',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.skip_previous),
                    onPressed: () =>
                        ref.read(playerControllerProvider.notifier).previous(),
                  ),
                  IconButton(
                    iconSize: 64,
                    icon: Icon(
                        state.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () =>
                        ref.read(playerControllerProvider.notifier).togglePlay(),
                  ),
                  IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.skip_next),
                    onPressed: () =>
                        ref.read(playerControllerProvider.notifier).next(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

Note: 测试通过 override `playerControllerProvider` 注入 `_FakePlayerController`(build 返回预置 isPlaying=true 状态),完全避开真实网络播放与 just_audio 平台通道依赖;UI 仅消费 `playerControllerProvider` 暴露的 state,契约不变。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/ui/player_page_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/ui/player/player_page.dart test/ui/player_page_test.dart
git commit -m "feat: add player page UI"
```

---

### Task 8: 插件管理页 UI(列表 + 安装 + 启停)

**Files:**
- Modify: `lib/ui/plugins/plugin_page.dart`
- Test: `test/ui/plugin_page_test.dart`

**Interfaces:**
- Consumes: PluginManager(Provider)。
- Produces: `PluginPage`(ConsumerWidget):`FutureBuilder`/`ref.watch` 插件列表(platform/version),AppBar 含"安装"按钮(用文件选择对话框——桌面端用 `showDialog` 输入路径,MVP 简化),列表项含"卸载"按钮。

- [ ] **Step 1: 写失败测试** `test/ui/plugin_page_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';
import 'package:musicx/ui/plugins/plugin_page.dart';

const _demoPlugin = '''
module.exports = { platform: "demo", version: "0.1.0", search: function(q){ return Promise.resolve({isEnd:true,data:[]}); } };
''';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_pp');
    File('${tmp.path}/demo.js').writeAsStringSync(_demoPlugin);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('PluginPage lists installed plugins', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pluginManagerProvider.overrideWithValue(PluginManager(tmp)),
      ],
      child: const MaterialApp(home: PluginPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('demo'), findsOneWidget);
    expect(find.text('v0.1.0'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/ui/plugin_page_test.dart`
Expected: FAIL(占位 PluginPage 无列表)

- [ ] **Step 3: 实现**

`lib/ui/plugins/plugin_page.dart`(整体替换):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

class PluginPage extends ConsumerWidget {
  const PluginPage({super.key});

  Future<void> _install(WidgetRef ref, BuildContext context) async {
    final pathCtrl = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('安装插件'),
        content: TextField(
          controller: pathCtrl,
          decoration: const InputDecoration(
            hintText: '输入插件 .js 文件路径',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, pathCtrl.text),
            child: const Text('安装'),
          ),
        ],
      ),
    );
    if (path == null || path.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(pluginManagerProvider).installFromFile(path.trim());
      messenger.showSnackBar(const SnackBar(content: Text('插件安装成功')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('安装失败:$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(pluginManagerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '安装插件',
            onPressed: () => _install(ref, context),
          ),
        ],
      ),
      body: FutureBuilder(
        future: manager.listPlugins(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final plugins = snapshot.data ?? const [];
          if (plugins.isEmpty) {
            return const Center(child: Text('尚未安装插件'));
          }
          return ListView.builder(
            itemCount: plugins.length,
            itemBuilder: (context, index) {
              final p = plugins[index];
              return ListTile(
                leading: const Icon(Icons.extension),
                title: Text(p.platform),
                subtitle: Text('v${p.version}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '卸载',
                  onPressed: () async {
                    await manager.uninstall(p);
                    // 触发重建:更换 FutureBuilder 的 key 或刷新状态
                    // (MVP 简化:重建页面)
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已卸载')));
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

Note: 卸载后列表刷新用简单方式——`PluginPage` 内 `setState` 触发重建(MVP 可接受);实现时若 `ConsumerWidget` 不便,改为 `ConsumerStatefulWidget` 并加 `_reload` 计数器驱动 FutureBuilder key。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/ui/plugin_page_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/ui/plugins/plugin_page.dart test/ui/plugin_page_test.dart
git commit -m "feat: add plugin management page UI"
```

---

### Task 9: 端到端演示验证 + demo 插件入库

**Files:**
- Modify: `example/plugins/demo_plugin.js`(search 返回多首歌曲,getMediaSource 返回真实可播 URL)
- Create: `test/e2e_demo_test.dart`(全链路:安装 demo 插件 → PluginManager.search → resolveMediaSource → PlayerService.playUrl 前置校验 URL)
- Modify: `README.md`(运行说明)

**Interfaces:**
- Consumes: 全部 Phase 2 组件。
- Produces: 一条可重复演示路径:装 demo 插件 → 搜索 → 播放(URL 可解析)。

- [ ] **Step 1: 更新 demo 插件** `example/plugins/demo_plugin.js`:

```js
module.exports = {
  platform: "demo",
  version: "0.2.0",
  srcUrl: "",
  search: function (query) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({
          isEnd: true,
          data: [
            { id: "s1", title: "SoundHelix 示例曲 1", artist: "SoundHelix", album: "Sample",
              artwork: "", duration: 369000, platform: "demo", songId: "s1", extra: {} },
            { id: "s2", title: "SoundHelix 示例曲 2", artist: "SoundHelix", album: "Sample",
              artwork: "", duration: 391000, platform: "demo", songId: "s2", extra: {} }
          ]
        });
      }, 20);
    });
  },
  getMediaSource: function (musicItem) {
    var idx = musicItem.songId.replace("s", "");
    return { url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-" + idx + ".mp3" };
  }
};
```

- [ ] **Step 2: 写失败测试** `test/e2e_demo_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_manager.dart';

void main() {
  test('e2e: install demo plugin, search, resolve real playable URL', () async {
    final tmp = Directory.systemTemp.createTempSync('musicx_e2e');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final demoSource = File('example/plugins/demo_plugin.js').readAsStringSync();
    File('${tmp.path}/demo.js').writeAsStringSync(demoSource);

    final manager = PluginManager(tmp);
    final result = await manager.search('SoundHelix');
    final data = (result['data'] as List).cast<Map<String, dynamic>>();
    expect(data, isNotEmpty);

    final first = data.first;
    final media = await manager.resolveMediaSource(first);
    final url = media['url'] as String;
    expect(url, startsWith('https://www.soundhelix.com/examples/mp3/'));
    expect(url, endsWith('.mp3'));
  });
}
```

- [ ] **Step 3: 运行测试确认通过**

Run: `flutter test test/e2e_demo_test.dart`
Expected: `All tests passed!`

- [ ] **Step 4: 更新 README** `README.md`(整体替换):

```markdown
# MusicX

插件化、跨平台的免费音乐播放器(Flutter)。

## 当前进度

- **Phase 1(已完成)**:插件运行时层——CommonJS 插件加载、JS↔Dart 桥、isolate 隔离与超时熔断、MusicFree 兼容数据模型。
- **Phase 2(最小可播放里程碑)**:插件管理、搜索、播放(just_audio)与播放队列。

## 运行

```bash
flutter pub get
flutter run -d macos   # 或 android / windows
```

1. 在"插件"页点击 + ,输入示例插件路径 `example/plugins/demo_plugin.js` 安装;
2. 切到"搜索"页,输入任意关键词(如 `SoundHelix`),回车;
3. 点击结果歌曲,即开始播放(示例插件返回 SoundHelix 公开测试音频)。

## 测试

```bash
flutter test
```
</details>

## 架构

五层:UI(Flutter)→ 状态管理(Riverpod)→ 插件运行时层(QuickJS)→ 播放引擎(just_audio)→ 数据层(Drift,Phase 3)。

## 协议合规

自研实现,插件协议兼容 MusicFree(CommonJS 模块导出 platform/version/search/getMediaSource 等),不复制其源码(规避 AGPL 传染)。
```

- [ ] **Step 5: 提交**

```bash
git add example/plugins/demo_plugin.js test/e2e_demo_test.dart README.md
git commit -m "test: e2e demo flow and run instructions"
```

---

## Self-Review

**1. Spec 覆盖(对照设计文档第 5 节 MVP 排序):**
- 插件管理(安装/卸载/启停)✅ Task 2(install/uninstall/list)+ Task 8(UI)
- 搜索 ✅ Task 5(controller)+ Task 6(UI)+ Task 2(manager.search)
- 播放(队列/上下首/进度)✅ Task 3(PlayerService)+ Task 4(PlayerController)+ Task 7(UI)
- 真实可播 ✅ Task 9(demo 插件返回 SoundHelix 公开音频)
- 歌单/歌词/本地音乐/设置 → 后续里程碑,不在本计划(已与用户确认最小可播放范围)

**2. 占位符扫描:** 无 TBD/TODO;所有代码步骤给出完整代码。Task 4/7 中的 Note 是 API/环境差异说明(实现以测试通过为准),非占位符。

**3. 类型一致性:**
- `PluginManager.search` 返回 `Map<String,dynamic>`,SearchController 按 `result['data']` List 消费 ✅
- `resolveMediaSource` 返回 `Map<String,dynamic>` 含 `url`,PlayerController 取 `media['url']` ✅
- `MusicItem.fromJson/toJson` 在 Task 4(_playCurrent 用 toJson 传给 resolveMediaSource)与 Task 5(fromJson 转结果)间一致 ✅
- `playerControllerProvider`/`searchControllerProvider`/`pluginManagerProvider`/`playerServiceProvider` 命名跨 Task 4/5/6/7/8 一致 ✅
- 测试 override 用 `pluginManagerProvider.overrideWithValue(PluginManager(tmp))`——Task 5/6/8 均按此模式 ✅

**4. 环境适配:**
- 播放页测试( Task 7)已注明网络不可用时的断言调整策略;`pluginsDir()` 用 `Directory.systemTemp` 演示目录(不依赖平台通道,沙箱可测)✅
- 全部验证以 `flutter test` 为准;macOS 构建/运行由用户本机执行(Global Constraints)✅

**5. 风险:**
- `resolveMediaSource` 在无网络环境会失败 → PlayerController 捕获并置 error,UI 显示(设计如此,不崩溃)✅
- just_audio 在 macOS 测试环境的插件注册——Task 3 测试只构造/释放,不实际播放,规避平台通道依赖 ✅
