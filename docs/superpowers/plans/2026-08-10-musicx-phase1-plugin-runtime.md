# MusicX Phase 1 — 项目脚手架 + 插件运行时层 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 MusicX 的 Flutter 三端工程骨架,并实现插件运行时层(插件加载器 + CommonJS shim + JS↔Dart Bridge + isolate 隔离与超时熔断),使一个 MusicFree 兼容的 JS 插件能在 Dart 中被加载和调用。

**Architecture:** 五层架构中的"插件运行时层"。插件 JS 源码经 CommonJS shim 包装后注入 flutter_js 的 JavascriptRuntime(macOS 用 JavascriptCore、Android/Windows 用 QuickJS);每个插件运行在独立 Dart isolate,主 isolate 通过 JSON 消息与插件 isolate 通信;所有插件调用带超时熔断。播放引擎、状态管理、数据层、UI 在后续 Phase 实现,不在本计划范围。

**Tech Stack:** Flutter 3.x(工程)、Dart 3.12+(已装)、flutter_js ^0.8.7(JS 引擎)、flutter_test(测试)。无其他运行时依赖。

## Global Constraints

- 平台:Android + Windows + macOS 三端;一套 Dart 代码,不写平台特定分支(Phase 1 不需要平台通道)。
- flutter_js 固定 `^0.8.7`(已核实支持三端,内置 xhr/fetch→Dart http、Promise、`onMessage`/`sendMessage` 双向通道)。
- 插件协议兼容 MusicFree:插件是 CommonJS 模块,导出 `platform`(必填)、`version`(必填)、`srcUrl`(可选),函数可选:`search`、`getMediaSource`、`getLyrics`、`importMusicSheet`、`getAlbumInfo`、`getArtistInfo`。
- 所有插件调用必须走 isolate + 超时熔断(默认 10s),禁止在 UI isolate 直接 evaluate 插件代码。
- 数据模型字段名与 MusicFree basic-type 一致:MusicItem 含 `id/title/artist/album/artwork/duration/platform/songId/extra`。
- 版本对比规则与 MusicFree 一致:形如 `1.2.3`,从前往后比主版本号;新版本号大于等于本地版本才允许安装。
- 测试命令统一用 `flutter test test/<path>`;全部测试必须能在 `flutter test` 下通过(在已解决 Xcode license 的机器上)。
- 本机环境事实(执行前需解决,非计划缺陷):`git` 与 `flutter` 命令因未同意 Xcode license 被阻塞(`sudo xcodebuild -license` 后恢复);Dart SDK 可通过 `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` 直接调用。
- 提交信息遵循 conventional commits(`feat:` / `test:` / `refactor:` 前缀)。

---

### Task 1: Flutter 三端工程脚手架

**Files:**
- Create: 整个工程(在当前仓库根 `/Users/tianjun/Desktop/prog/musicx` 下生成)
- Create: `pubspec.yaml`(flutter create 生成后追加依赖)
- Create: `test/widget_test.dart`(脚手架自带,改写成冒烟测试)

**Interfaces:**
- Consumes: 无
- Produces: 可运行的 Flutter 工程,包名 `com.musicx.musicx`,三端目录 `android/`、`windows/`、`macos/` 齐备;`flutter_js: ^0.8.7` 已加入依赖。

- [ ] **Step 1: 生成工程**

```bash
cd /Users/tianjun/Desktop/prog/musicx
flutter create . --org com.musicx --project-name musicx --platforms=android,windows,macos
```

Expected: 输出 "All done!",生成 `android/`、`windows/`、`macos/`、`lib/main.dart`、`pubspec.yaml`、`test/widget_test.dart`。

- [ ] **Step 2: 追加 flutter_js 依赖**

编辑 `pubspec.yaml`,在 `dependencies:` 下追加:

```yaml
  flutter_js: ^0.8.7
```

- [ ] **Step 3: 改写冒烟测试**

用以下内容整体替换 `test/widget_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/main.dart';

void main() {
  testWidgets('App boots and shows title', (WidgetTester tester) async {
    await tester.pumpWidget(const MusicxApp());
    expect(find.text('MusicX'), findsOneWidget);
  });
}
```

- [ ] **Step 4: 修改 main.dart 显示占位标题**

将 `lib/main.dart` 中 `MyApp` 类与 `MyHomePage` 类整体替换为:

```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const MusicxApp());
}

class MusicxApp extends StatelessWidget {
  const MusicxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MusicX',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      home: const Scaffold(
        body: Center(child: Text('MusicX')),
      ),
    );
  }
}
```

- [ ] **Step 5: 运行冒烟测试**

Run: `flutter test test/widget_test.dart`
Expected: `All tests passed!`(若 flutter 命令因 Xcode license 阻塞,先运行 `sudo xcodebuild -license`,或临时用 `dart analyze lib test` 检查无编译错误)

- [ ] **Step 6: 提交**

```bash
git add pubspec.yaml lib/main.dart test/widget_test.dart android windows macos
git commit -m "feat: scaffold flutter project for android/windows/macos"
```

---

### Task 2: 核心数据模型(MusicFree basic-type 兼容)

**Files:**
- Create: `lib/models/music_item.dart`
- Create: `lib/models/album_item.dart`
- Create: `lib/models/artist_item.dart`
- Create: `lib/models/music_sheet_item.dart`
- Create: `lib/models/lyric_line.dart`
- Test: `test/models/music_item_test.dart`
- Test: `test/models/lyric_line_test.dart`

**Interfaces:**
- Consumes: 无(纯 Dart)
- Produces:
  - `class MusicItem { final String id; final String title; final String? artist; final String? album; final String? artwork; final int? duration; final String platform; final String songId; final Map<String, dynamic>? extra; const MusicItem({...}); factory MusicItem.fromJson(Map<String, dynamic> json); Map<String, dynamic> toJson(); }`
  - `class LyricLine { final Duration time; final String text; factory LyricLine.fromLrc(String rawLine); }`
  - `class AlbumItem`、`class ArtistItem`、`class MusicSheetItem` 各含 `id/title/platform` 必填字段与 `artwork/extra` 可选字段,均有 `fromJson/toJson`。

- [ ] **Step 1: 编写失败测试** `test/models/music_item_test.dart` 与 `test/models/lyric_line_test.dart`:

```dart
// test/models/music_item_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/models/music_item.dart';

void main() {
  test('MusicItem fromJson → toJson roundtrip', () {
    final json = {
      'id': 'abc', 'title': '测试歌曲', 'artist': '歌手甲', 'album': '专辑乙',
      'artwork': 'http://x/a.jpg', 'duration': 210000,
      'platform': 'test-plugin', 'songId': 's1',
      'extra': {'quality': 'hq'},
    };
    final item = MusicItem.fromJson(json);
    expect(item.title, '测试歌曲');
    expect(item.platform, 'test-plugin');
    expect(item.toJson(), json);
  });

  test('MusicItem requires id/title/platform/songId', () {
    expect(() => MusicItem.fromJson({'title': 'x'}), throwsArgumentError);
  });
}
```

```dart
// test/models/lyric_line_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/models/lyric_line.dart';

void main() {
  test('LyricLine.fromLrc parses [mm:ss.xx]text', () {
    final line = LyricLine.fromLrc('[01:23.45]你好世界');
    expect(line.time, const Duration(milliseconds: 83450));
    expect(line.text, '你好世界');
  });

  test('LyricLine.fromLrc ignores metadata lines', () {
    final line = LyricLine.fromLrc('[ar:歌手]');
    expect(line.text, isEmpty);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/models/music_item_test.dart test/models/lyric_line_test.dart`
Expected: FAIL,`Error: Error: Method not found: 'MusicItem.fromJson'` 之类

- [ ] **Step 3: 实现数据模型**

`lib/models/music_item.dart`:

```dart
class MusicItem {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String? artwork;
  final int? duration;
  final String platform;
  final String songId;
  final Map<String, dynamic>? extra;

  const MusicItem({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.artwork,
    this.duration,
    required this.platform,
    required this.songId,
    this.extra,
  });

  factory MusicItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final platform = json['platform'];
    final songId = json['songId'];
    if (id is! String || title is! String || platform is! String || songId is! String) {
      throw ArgumentError('MusicItem requires id/title/platform/songId: $json');
    }
    return MusicItem(
      id: id,
      title: title,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      artwork: json['artwork'] as String?,
      duration: json['duration'] as int?,
      platform: platform,
      songId: songId,
      extra: (json['extra'] as Map<String, dynamic>?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'artist': artist, 'album': album,
        'artwork': artwork, 'duration': duration,
        'platform': platform, 'songId': songId, 'extra': extra,
      };
}
```

`lib/models/lyric_line.dart`:

```dart
class LyricLine {
  final Duration time;
  final String text;
  const LyricLine({required this.time, required this.text});

  /// 解析单行 LRC,如 `[01:23.45]歌词`;无时间戳的元信息行返回 text 为空的实例。
  factory LyricLine.fromLrc(String rawLine) {
    final match = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\](.*)').firstMatch(rawLine);
    if (match == null) {
      return const LyricLine(time: Duration.zero, text: '');
    }
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final millisRaw = match.group(3);
    var millis = 0;
    if (millisRaw != null) {
      millis = millisRaw.length == 2
          ? int.parse(millisRaw) * 10
          : int.parse(millisRaw.padRight(3, '0').substring(0, 3));
    }
    return LyricLine(
      time: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
      text: match.group(4) ?? '',
    );
  }
}
```

`lib/models/album_item.dart`、`lib/models/artist_item.dart`、`lib/models/music_sheet_item.dart` 三者结构相同,仅类名与必填字段不同(AlbumItem: `id/title/platform`;ArtistItem: `id/name/platform`(json 字段 `name`);MusicSheetItem: `id/title/platform`),均为 `id` + `title`/`name` + `platform` 必填 + `artwork/extra` 可选 + `fromJson/toJson` 的不可变类。ArtistItem 的 title 字段在 json 里叫 `name`。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/models/music_item_test.dart test/models/lyric_line_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/models test/models
git commit -m "feat: add musicfree-compatible basic data models"
```

---

### Task 3: 插件元数据解析与版本对比

**Files:**
- Create: `lib/core/plugins/plugin_info.dart`
- Test: `test/core/plugins/plugin_info_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class PluginInfo { final String platform; final String version; final String? srcUrl; final String hash; final String path; final bool enabled; const PluginInfo({...}); factory PluginInfo.fromJsMeta(Map<String, dynamic> meta, {required String hash, required String path, bool enabled = true}); }`
  - `int compareVersions(String a, String b)` — 返回 `-1/0/1`;`a < b` 返回 -1;格式 `x.y.z`,非数字段按 0 处理。

- [ ] **Step 1: 编写失败测试** `test/core/plugins/plugin_info_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_info.dart';

void main() {
  test('compareVersions orders correctly', () {
    expect(compareVersions('1.2.4', '1.2.3'), 1);
    expect(compareVersions('2.0.0', '1.99.99'), 1);
    expect(compareVersions('1.2.3', '1.2.3'), 0);
    expect(compareVersions('1.2', '1.2.3'), -1);
    expect(compareVersions('0.9', '0.10'), -1);
  });

  test('PluginInfo.fromJsMeta maps fields', () {
    final info = PluginInfo.fromJsMeta(
      {'platform': 'demo', 'version': '0.1.0', 'srcUrl': 'http://x/p.js'},
      hash: 'deadbeef',
      path: '/tmp/plugins/x.js',
    );
    expect(info.platform, 'demo');
    expect(info.version, '0.1.0');
    expect(info.srcUrl, 'http://x/p.js');
    expect(info.enabled, isTrue);
  });

  test('PluginInfo rejects missing platform/version', () {
    expect(() => PluginInfo.fromJsMeta({'platform': 'x'}, hash: 'h', path: 'p'),
        throwsArgumentError);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/plugins/plugin_info_test.dart`
Expected: FAIL,`Method not found: 'compareVersions'`

- [ ] **Step 3: 实现**

`lib/core/plugins/plugin_info.dart`:

```dart
class PluginInfo {
  final String platform;
  final String version;
  final String? srcUrl;
  final String hash;
  final String path;
  final bool enabled;

  const PluginInfo({
    required this.platform,
    required this.version,
    this.srcUrl,
    required this.hash,
    required this.path,
    this.enabled = true,
  });

  factory PluginInfo.fromJsMeta(
    Map<String, dynamic> meta, {
    required String hash,
    required String path,
    bool enabled = true,
  }) {
    final platform = meta['platform'];
    final version = meta['version'];
    if (platform is! String || platform.isEmpty ||
        version is! String || version.isEmpty) {
      throw ArgumentError('Plugin requires non-empty platform and version: $meta');
    }
    return PluginInfo(
      platform: platform,
      version: version,
      srcUrl: meta['srcUrl'] as String?,
      hash: hash,
      path: path,
      enabled: enabled,
    );
  }
}

/// 版本对比,规则与 MusicFree 一致:分段比较,非数字段按 0。
int compareVersions(String a, String b) {
  final as = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final bs = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final len = as.length > bs.length ? as.length : bs.length;
  for (var i = 0; i < len; i++) {
    final av = i < as.length ? as[i] : 0;
    final bv = i < bs.length ? bs[i] : 0;
    if (av != bv) return av > bv ? 1 : -1;
  }
  return 0;
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/core/plugins/plugin_info_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/core/plugins/plugin_info.dart test/core/plugins/plugin_info_test.dart
git commit -m "feat: add plugin metadata model and version compare"
```

---

### Task 4: 插件目录扫描(PluginStore)

**Files:**
- Create: `lib/core/plugins/plugin_store.dart`
- Test: `test/core/plugins/plugin_store_test.dart`

**Interfaces:**
- Consumes: `PluginInfo`、`compareVersions`(Task 3)
- Produces:
  - `class PluginStore { PluginStore(this.rootDir); final Directory rootDir; List<File> scanPluginFiles(); Future<PluginInfo> loadMeta(File file); Future<String> sha256Of(File file); }`
  - 扫描规则:遍历 `rootDir` 下所有 `*.js` 文件(非递归)。

- [ ] **Step 1: 编写失败测试** `test/core/plugins/plugin_store_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_store.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('musicx_test');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('scanPluginFiles finds only .js files', () {
    File('${tmp.path}/a.js').writeAsStringSync('// x');
    File('${tmp.path}/b.txt').writeAsStringSync('// y');
    File('${tmp.path}/sub/c.js').writeAsStringSync('// z');
    Directory('${tmp.path}/sub').createSync();
    final store = PluginStore(tmp);
    final files = store.scanPluginFiles().map((f) => f.path.split('/').last).toList();
    expect(files, ['a.js']);
  });

  test('loadMeta extracts platform/version from CommonJS export', () async {
    final f = File('${tmp.path}/demo.js');
    f.writeAsStringSync('module.exports = { platform: "demo", version: "0.2.0", srcUrl: "http://x" };');
    final info = await PluginStore(tmp).loadMeta(f);
    expect(info.platform, 'demo');
    expect(info.version, '0.2.0');
    expect(info.srcUrl, 'http://x');
    expect(info.path, f.path);
    expect(info.hash, isNotEmpty);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/plugins/plugin_store_test.dart`
Expected: FAIL,`Method not found: 'PluginStore'`

- [ ] **Step 3: 实现**

`lib/core/plugins/plugin_store.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'plugin_info.dart';

class PluginStore {
  final Directory rootDir;
  PluginStore(this.rootDir);

  List<File> scanPluginFiles() {
    if (!rootDir.existsSync()) return [];
    return rootDir
        .listSync(followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'))
        .toList();
  }

  Future<PluginInfo> loadMeta(File file) async {
    final hash = await sha256Of(file);
    final meta = _extractMeta(await file.readAsString());
    return PluginInfo.fromJsMeta(meta, hash: hash, path: file.path);
  }

  Future<String> sha256Of(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// 轻量解析:匹配顶层 `platform`/`version`/`srcUrl` 字符串字面量,
  /// 不执行 JS(元数据解析阶段不加载插件)。
  Map<String, dynamic> _extractMeta(String source) {
    final re = RegExp(r'(platform|version|srcUrl)\s*:\s*["\']([^"\']+)["\']');
    final meta = <String, dynamic>{};
    for (final m in re.allMatches(source)) {
      meta.putIfAbsent(m.group(1)!, () => m.group(2));
    }
    return meta;
  }
}
```

Note: 需要 `crypto` 包。在 `pubspec.yaml` 的 `dependencies:` 追加:

```yaml
  crypto: ^3.0.3
```

- [ ] **Step 4: 运行 pub get 并测试**

Run: `flutter pub get && flutter test test/core/plugins/plugin_store_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add pubspec.yaml pubspec.lock lib/core/plugins/plugin_store.dart test/core/plugins/plugin_store_test.dart
git commit -m "feat: add plugin directory scanning and meta extraction"
```

---

### Task 5: 插件加载器 + CommonJS shim(核心)

**Files:**
- Create: `lib/core/plugins/plugin_loader.dart`
- Create: `lib/core/plugins/js_runtime_factory.dart`
- Test: `test/core/plugins/plugin_loader_test.dart`

**Interfaces:**
- Consumes: `PluginInfo`(Task 3)
- Produces:
  - `class PluginLoader { PluginLoader(this.runtime); final JavascriptRuntime runtime; Future<Map<String, dynamic>> loadPlugin(String source) → 返回插件导出的元数据(platform/version/srcUrl)与可用函数名列表; }`
  - `class JsRuntimeFactory { static JavascriptRuntime create() → 调用 getJavascriptRuntime() 的封装,便于测试替换; }`
  - shim 常量 `String cjsShim(String source)` — 把插件源码包进 `(function(module, exports, require){ ... })(...)`,并把 `module.exports` 挂到 `globalThis.__musicx_export`。

- [ ] **Step 1: 编写失败测试** `test/core/plugins/plugin_loader_test.dart`:

```dart
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';

void main() {
  test('loadPlugin wraps CommonJS and exposes metadata', () {
    final runtime = JsRuntimeFactory.create();
    final loader = PluginLoader(runtime);
    final result = loader.loadPlugin(
      'module.exports = { platform: "demo", version: "0.1.0", srcUrl: "http://x", search: function(){ return []; } };',
    );
    expect(result['platform'], 'demo');
    expect(result['version'], '0.1.0');
    final funcs = (result['functions'] as List).cast<String>();
    expect(funcs, contains('search'));
    expect(funcs, isNot(contains('platform')));
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/plugins/plugin_loader_test.dart`
Expected: FAIL(若本机 flutter 被 Xcode license 阻塞,该任务验证需在 license 解决后执行;临时可用 `dart analyze lib/core/plugins test/core/plugins` 检查编译)

- [ ] **Step 3: 实现 shim 与加载器**

`lib/core/plugins/js_runtime_factory.dart`:

```dart
import 'package:flutter_js/flutter_js.dart';

class JsRuntimeFactory {
  static JavascriptRuntime create() => getJavascriptRuntime();
}
```

`lib/core/plugins/plugin_loader.dart`:

```dart
import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'js_runtime_factory.dart';

/// 把 CommonJS 插件源码包进 IIFE,提供 module/exports/require,
/// 并把导出挂到 globalThis.__musicx_export 供 Bridge 调用。
String cjsShim(String source) => '''
var __musicx_module = { exports: {} };
(function (module, exports, require) {
$source
})(__musicx_module, __musicx_module.exports, function (name) {
  throw new Error("require() not supported at load time: " + name);
});
globalThis.__musicx_export = __musicx_module.exports;
''';

class PluginLoader {
  final JavascriptRuntime runtime;
  PluginLoader(this.runtime);

  factory PluginLoader.create() => PluginLoader(JsRuntimeFactory.create());

  /// 加载插件,返回 { platform, version, srcUrl?, functions: [...] }。
  Map<String, dynamic> loadPlugin(String source) {
    runtime.evaluate(cjsShim(source));
    final metaRaw = runtime.evaluate(
      'JSON.stringify({ meta: (globalThis.__musicx_export.platform !== undefined && globalThis.__musicx_export.version !== undefined) ? { platform: globalThis.__musicx_export.platform, version: globalThis.__musicx_export.version, srcUrl: globalThis.__musicx_export.srcUrl || null } : null, functions: Object.keys(globalThis.__musicx_export).filter(function(k){ return typeof globalThis.__musicx_export[k] === "function"; }) })',
    );
    final decoded = jsonDecode(metaRaw.stringResult) as Map<String, dynamic>;
    final meta = decoded['meta'] as Map<String, dynamic>?;
    if (meta == null) {
      throw ArgumentError('Plugin does not export required platform/version');
    }
    return {
      ...meta,
      'functions': decoded['functions'],
    };
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/core/plugins/plugin_loader_test.dart`
Expected: `All tests passed!`(macOS 测试直接可跑;Windows/Linux 需按 flutter_js 文档设置引擎动态库路径)

- [ ] **Step 5: 提交**

```bash
git add lib/core/plugins/plugin_loader.dart lib/core/plugins/js_runtime_factory.dart test/core/plugins/plugin_loader_test.dart
git commit -m "feat: add commonjs shim and plugin loader"
```

---

### Task 6: JS↔Dart Bridge(插件函数调用)

**Files:**
- Create: `lib/core/plugins/plugin_bridge.dart`
- Test: `test/core/plugins/plugin_bridge_test.dart`

**Interfaces:**
- Consumes: `PluginLoader`(Task 5)
- Produces:
  - `class PluginBridge { PluginBridge(this.runtime); Map<String, dynamic> callSync(String method, Map<String, dynamic> args); }`
  - 同步调用语义:`callSync('getMediaSource', {'id': 'x'})` 执行 `globalThis.__musicx_export.getMediaSource(args)`,返回其返回值的 JSON 解码结果;函数不存在或抛异常时抛 `PluginCallException`(含 method 与原因)。
  - `class PluginCallException implements Exception { final String method; final String reason; }`

- [ ] **Step 1: 编写失败测试** `test/core/plugins/plugin_bridge_test.dart`:

```dart
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_bridge.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';

void main() {
  late JavascriptRuntime runtime;
  setUp(() {
    runtime = JsRuntimeFactory.create();
    PluginLoader(runtime).loadPlugin(
      'module.exports = { platform: "demo", version: "0.1.0", '
      'getMediaSource: function(item){ return { url: "http://media/" + item.id }; }, '
      'boom: function(){ throw new Error("kaboom"); } };',
    );
  });

  test('callSync invokes plugin function with JSON args', () {
    final bridge = PluginBridge(runtime);
    final result = bridge.callSync('getMediaSource', {'id': 'song1'});
    expect(result['url'], 'http://media/song1');
  });

  test('callSync throws PluginCallException on missing method', () {
    final bridge = PluginBridge(runtime);
    expect(() => bridge.callSync('nope', {}), throwsA(isA<PluginCallException>()));
  });

  test('callSync wraps JS exceptions', () {
    final bridge = PluginBridge(runtime);
    expect(
      () => bridge.callSync('boom', {}),
      throwsA(isA<PluginCallException>().having((e) => e.reason, 'reason', contains('kaboom'))),
    );
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/plugins/plugin_bridge_test.dart`
Expected: FAIL,`Method not found: 'PluginBridge'`

- [ ] **Step 3: 实现**

`lib/core/plugins/plugin_bridge.dart`:

```dart
import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';

class PluginCallException implements Exception {
  final String method;
  final String reason;
  const PluginCallException(this.method, this.reason);
  @override
  String toString() => 'PluginCallException($method): $reason';
}

class PluginBridge {
  final JavascriptRuntime runtime;
  PluginBridge(this.runtime);

  Map<String, dynamic> callSync(String method, Map<String, dynamic> args) {
    // jsonEncode(method) 生成合法的 JS 字符串字面量(含引号与转义),
    // argsJson 同理,两者直接嵌入 JS 源码。
    final methodKey = jsonEncode(method);
    final argsJson = jsonEncode(args);
    final js = '''
(function(){
  var fn = globalThis.__musicx_export && globalThis.__musicx_export[$methodKey];
  if (typeof fn !== "function") { return JSON.stringify({ error: "method not found: " + $methodKey }); }
  try {
    var out = fn(JSON.parse($argsJson));
    return JSON.stringify({ value: out === undefined ? null : out });
  } catch (e) {
    return JSON.stringify({ error: String(e && e.message || e) });
  }
})()
''';
    final raw = runtime.evaluate(js).stringResult;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded.containsKey('error')) {
      throw PluginCallException(method, decoded['error'] as String);
    }
    final value = decoded['value'];
    if (value is! Map<String, dynamic>) {
      throw PluginCallException(method, 'plugin returned non-object value');
    }
    return value;
  }
}
```

Note: 关键写法是 `${jsonEncode(method)}` 与 `$argsJson` —— 二者都是完整的 JS 表达式片段(分别含引号的字符串字面量与 JSON 对象字面量),直接插入模板字符串即可,不需要额外的拼接。`sendMessage` 同名机制说明:该方法名由 flutter_js 内部提供(`onMessage` 与 `sendMessage` 是一对)。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/core/plugins/plugin_bridge_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/core/plugins/plugin_bridge.dart test/core/plugins/plugin_bridge_test.dart
git commit -m "feat: add sync JS-Dart bridge with error wrapping"
```

---

### Task 7: 异步调用通道(Promise + sendMessage)

**Files:**
- Create: `lib/core/plugins/plugin_bridge_async.dart`
- Test: `test/core/plugins/plugin_bridge_async_test.dart`

**Interfaces:**
- Consumes: `PluginBridge`(Task 6)
- Produces:
  - `class PluginBridgeAsync { PluginBridgeAsync(this.runtime); Future<Map<String, dynamic>> callAsync(String method, Map<String, dynamic> args, {Duration timeout = const Duration(seconds: 10)}); }`
  - 语义:插件函数返回 Promise,resolve 值经 `sendMessage('__musicx_async_result', JSON.stringify({id, value}))` 回传 Dart;超时抛 `PluginAsyncTimeoutException`。
  - `class PluginAsyncTimeoutException implements Exception { final String method; }`

- [ ] **Step 1: 编写失败测试** `test/core/plugins/plugin_bridge_async_test.dart`:

```dart
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_bridge_async.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';

void main() {
  test('callAsync resolves Promise result via message channel', () async {
    final runtime = JsRuntimeFactory.create();
    PluginLoader(runtime).loadPlugin(
      'module.exports = { platform: "demo", version: "0.1.0", '
      'search: function(q){ return new Promise(function(resolve){ setTimeout(function(){ resolve({ list: [q.keyword] }); }, 30); }); } };',
    );
    final bridge = PluginBridgeAsync(runtime);
    final result = await bridge.callAsync('search', {'keyword': '周杰伦'});
    expect(result['list'], ['周杰伦']);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/plugins/plugin_bridge_async_test.dart`
Expected: FAIL,`Method not found: 'PluginBridgeAsync'`

- [ ] **Step 3: 实现**

`lib/core/plugins/plugin_bridge_async.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';

class PluginAsyncTimeoutException implements Exception {
  final String method;
  const PluginAsyncTimeoutException(this.method);
}

class PluginBridgeAsync {
  final JavascriptRuntime runtime;
  PluginBridgeAsync(this.runtime);

  Future<Map<String, dynamic>> callAsync(
    String method,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final completer = Completer<Map<String, dynamic>>();

    void onResult(dynamic payload) {
      final msg = payload as List;
      if (msg.isEmpty || msg[0] != id) return;
      final data = jsonDecode(msg[1] as String) as Map<String, dynamic>;
      if (data.containsKey('error')) {
        completer.completeError(PluginCallException(method, data['error'] as String));
      } else {
        completer.complete(data['value'] as Map<String, dynamic>);
      }
    }

    runtime.onMessage('__musicx_async_result', onResult);
    try {
      final argsJson = jsonEncode(args);
      final js = '''
(function(){
  var fn = globalThis.__musicx_export && globalThis.__musicx_export[${jsonEncode(method)}];
  if (typeof fn !== "function") {
    sendMessage('__musicx_async_result', JSON.stringify({ id: ${jsonEncode(id)}, error: "method not found" }));
    return;
  }
  try {
    var p = fn(JSON.parse($argsJson));
    if (p && typeof p.then === "function") {
      p.then(function(v){
        sendMessage('__musicx_async_result', JSON.stringify({ id: ${jsonEncode(id)}, value: v === undefined ? null : v }));
      }, function(e){
        sendMessage('__musicx_async_result', JSON.stringify({ id: ${jsonEncode(id)}, error: String(e && e.message || e) }));
      });
    } else {
      sendMessage('__musicx_async_result', JSON.stringify({ id: ${jsonEncode(id)}, value: p === undefined ? null : p }));
    }
  } catch (e) {
    sendMessage('__musicx_async_result', JSON.stringify({ id: ${jsonEncode(id)}, error: String(e && e.message || e) }));
  }
})()
''';
      runtime.evaluate(js);
      return await completer.future.timeout(timeout,
          onTimeout: () => throw PluginAsyncTimeoutException(method));
    } finally {
      runtime.onMessage('__musicx_async_result', (_) {});
    }
  }
}
```

Note: 若所选 flutter_js 版本中 `onMessage` 返回 `StreamSubscription` 而不是可替换回调,则改为保存 subscription 并在 `finally` 中 `cancel()`;测试通过为准。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/core/plugins/plugin_bridge_async_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/core/plugins/plugin_bridge_async.dart test/core/plugins/plugin_bridge_async_test.dart
git commit -m "feat: add async plugin call channel via sendMessage"
```

---

### Task 8: isolate 隔离 + 超时熔断(PluginSandbox)

**Files:**
- Create: `lib/core/plugins/plugin_sandbox.dart`
- Test: `test/core/plugins/plugin_sandbox_test.dart`

**Interfaces:**
- Consumes: `PluginBridge`(Task 6)、`PluginBridgeAsync`(Task 7)
- Produces:
  - `class PluginSandbox { Future<T> isolate<T>(Future<T> Function() fn, {Duration timeout}); }`
  - 语义:在独立 isolate 中运行 `fn`(内部创建独立 JavascriptRuntime),主 isolate 等待结果;超时 kill 该 isolate 并抛 `PluginIsolateTimeoutException`。

- [ ] **Step 1: 编写失败测试** `test/core/plugins/plugin_sandbox_test.dart`:

```dart
import 'dart:async';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_bridge.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';
import 'package:musicx/core/plugins/plugin_sandbox.dart';

void main() {
  test('runs plugin call inside isolate and returns value', () async {
    final sandbox = PluginSandbox();
    final value = await sandbox.isolate(() async {
      final runtime = JsRuntimeFactory.create();
      PluginLoader(runtime).loadPlugin(
        'module.exports = { platform: "demo", version: "0.1.0", '
        'getMediaSource: function(){ return { url: "http://ok" }; } };',
      );
      return PluginBridge(runtime).callSync('getMediaSource', {});
    });
    expect(value['url'], 'http://ok');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/plugins/plugin_sandbox_test.dart`
Expected: FAIL,`Method not found: 'PluginSandbox'`

- [ ] **Step 3: 实现**

`lib/core/plugins/plugin_sandbox.dart`:

```dart
import 'dart:async';
import 'dart:isolate';

class PluginIsolateTimeoutException implements Exception {
  final Duration timeout;
  const PluginIsolateTimeoutException(this.timeout);
}

class PluginSandbox {
  Future<T> isolate<T>(
    Future<T> Function() fn, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final result = await Isolate.run(fn).timeout(
      timeout,
      onTimeout: () => throw PluginIsolateTimeoutException(timeout),
    );
    return result;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/core/plugins/plugin_sandbox_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/core/plugins/plugin_sandbox.dart test/core/plugins/plugin_sandbox_test.dart
git commit -m "feat: add isolate sandbox with timeout"
```

---

### Task 9: 端到端验证——真实 MusicFree 插件跑通

**Files:**
- Create: `example/plugins/demo_plugin.js`(一个模拟 MusicFree 协议的本地插件)
- Create: `test/core/plugins/e2e_plugin_test.dart`
- Modify: `lib/main.dart`(临时入口,展示"搜索 → 拿播放地址"流程;Phase 1 验证后恢复为占位 UI)

**Interfaces:**
- Consumes: PluginStore(Task 4)、PluginLoader(Task 5)、PluginBridge(Task 6)、PluginBridgeAsync(Task 7)、PluginSandbox(Task 8)
- Produces: 一条可重复的端到端路径:**目录扫描 → 元数据解析 → 加载 → search → getMediaSource**,证明 MusicFree 兼容插件可在 Dart 侧完整调用。

- [ ] **Step 1: 编写模拟插件** `example/plugins/demo_plugin.js`:

```js
module.exports = {
  platform: "demo-source",
  version: "0.1.0",
  srcUrl: "",
  search: function (query) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({
          isEnd: true,
          data: [
            { id: "d1", title: "示例歌曲", artist: "演示歌手", album: "演示专辑",
              artwork: "", duration: 180000, platform: "demo-source", songId: "d1", extra: {} }
          ]
        });
      }, 20);
    });
  },
  getMediaSource: function (musicItem) {
    return { url: "https://example.com/audio/" + musicItem.songId + ".mp3" };
  }
};
```

- [ ] **Step 2: 编写失败测试** `test/core/plugins/e2e_plugin_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_bridge.dart';
import 'package:musicx/core/plugins/plugin_bridge_async.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';
import 'package:musicx/core/plugins/plugin_sandbox.dart';

void main() {
  test('e2e: load demo plugin, search, then resolve media source', () async {
    final sandbox = PluginSandbox();
    final song = await sandbox.isolate(() async {
      final runtime = JsRuntimeFactory.create();
      final loader = PluginLoader(runtime);
      final meta = loader.loadPlugin('''
module.exports = { platform: "demo-source", version: "0.1.0", srcUrl: "",
  search: function (query) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({ isEnd: true, data: [ { id: "d1", title: "示例歌曲", artist: "演示歌手",
          album: "演示专辑", artwork: "", duration: 180000, platform: "demo-source", songId: "d1", extra: {} } ] });
      }, 20);
    });
  },
  getMediaSource: function (musicItem) { return { url: "https://example.com/audio/" + musicItem.songId + ".mp3" }; }
};
''');
      expect(meta['platform'], 'demo-source');

      final asyncBridge = PluginBridgeAsync(runtime);
      final searchResult = await asyncBridge.callAsync('search', {'keyword': '示例'});
      final first = (searchResult['data'] as List).first as Map<String, dynamic>;

      final bridge = PluginBridge(runtime);
      final media = bridge.callSync('getMediaSource', first);
      return {'title': first['title'], 'url': media['url']};
    });

    expect(song['title'], '示例歌曲');
    expect(song['url'], 'https://example.com/audio/d1.mp3');
  });
}
```

- [ ] **Step 3: 运行测试确认通过**

Run: `flutter test test/core/plugins/e2e_plugin_test.dart`
Expected: `All tests passed!`——证明搜索(Promise 异步)与取播放地址(同步)在 isolate 沙箱内端到端跑通。

- [ ] **Step 4: 提交**

```bash
git add example/plugins/demo_plugin.js test/core/plugins/e2e_plugin_test.dart
git commit -m "test: e2e plugin search + media source flow"
```

---

## Self-Review

**1. Spec 覆盖(对照设计文档):**
- 插件加载流程(扫描→解析→加载→驻留)✅ Task 4(扫描/解析)、Task 5(加载 shim)、Task 6/7(调用驻留实例)
- CommonJS shim ✅ Task 5
- JS↔Dart Bridge(同步 + 异步网络)✅ Task 6(同步)、Task 7(异步 Promise + sendMessage;xhr/fetch 由 flutter_js 内置转发到 Dart http)
- 隔离与熔断 ✅ Task 8(isolate + 超时)
- 插件元数据与版本对比(安装校验前置)✅ Task 3
- 数据模型对齐 basic-type ✅ Task 2
- 播放引擎/状态管理/数据层/UI → 后续 Phase(设计文档第 11 节第 3-5 项),不在本计划范围,已与用户确认分 Phase。

**2. 占位符扫描:** 已检查全文,无 TBD/TODO;所有代码步骤给出完整代码;Task 6/7 中的 Note 是 API 差异说明而非占位符(实现以测试通过为准)。

**3. 类型一致性:**
- `PluginLoader.loadPlugin` 返回 `Map<String, dynamic>`,Task 6/7/9 均按此消费 ✅
- `PluginBridge.callSync` 返回 `Map<String, dynamic>`,Task 8/9 一致 ✅
- `PluginBridgeAsync.callAsync` 返回 `Future<Map<String, dynamic>>`,Task 9 一致 ✅
- `compareVersions` 在 Task 3 定义,Task 4 依赖声明一致 ✅
- `PluginCallException` 在 Task 6 定义,Task 7 引用一致 ✅
