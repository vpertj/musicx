import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:musicx/core/plugins/plugin_bridge_async.dart';
import 'package:musicx/core/plugins/plugin_info.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';
import 'package:musicx/core/plugins/plugin_sandbox.dart';
import 'package:musicx/core/plugins/plugin_store.dart';
import 'package:musicx/models/plugin_source.dart';

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
    await _writePlugin(await file.readAsString(), source: path);
  }

  /// 在线安装:从 [url] 下载插件 JS 并保存到插件目录。
  /// 下载后仅做元数据轻量校验(platform/version 存在),完整加载校验
  /// 由 listPlugins/搜索时执行。
  Future<PluginInfo> installFromUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw ArgumentError('无效的插件地址:$url');
    }
    final body = await _downloadText(uri);
    final meta = _store.parseMeta(body);
    final platform = meta['platform'];
    final version = meta['version'];
    if (platform is! String ||
        platform.isEmpty ||
        version is! String ||
        version.isEmpty) {
      throw ArgumentError('下载内容不是有效的插件(缺少 platform/version):$url');
    }
    final path = await _writePlugin(body, source: url);
    return PluginInfo.fromJsMeta(
      meta,
      hash: await _store.sha256Of(File(path)),
      path: path,
    );
  }

  /// 拉取订阅源(plugins.json),返回插件条目列表。
  /// 兼容 { "plugins": [...] } 与顶层直接为数组两种格式。
  Future<List<PluginSource>> fetchPluginSources(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw ArgumentError('无效的订阅源地址:$url');
    }
    final body = await _downloadText(uri);
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      throw FormatException('订阅源不是有效的 JSON:${e.message}');
    }
    final List<dynamic> raw;
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map && decoded['plugins'] is List) {
      raw = decoded['plugins'] as List;
    } else {
      throw const FormatException('订阅源缺少 plugins 列表');
    }
    final sources = <PluginSource>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        sources.add(PluginSource.fromJson(Map<String, dynamic>.from(item)));
      } on FormatException {
        // 跳过格式错误的条目
      }
    }
    if (sources.isEmpty) {
      throw const FormatException('订阅源中没有可用的插件');
    }
    return sources;
  }

  /// 判断某平台插件是否已安装(供订阅源列表显示状态)。
  Future<bool> isInstalled(String platform) async {
    final plugins = await listPlugins();
    return plugins.any((p) => p.platform == platform);
  }

  Future<String> _downloadText(Uri uri) async {
    final client = http.Client();
    try {
      final resp = await client
          .get(uri, headers: const {'user-agent': 'MusicX/1.0'})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        throw HttpException('下载失败:HTTP ${resp.statusCode}');
      }
      return utf8.decode(resp.bodyBytes);
    } finally {
      client.close();
    }
  }

  Future<String> _writePlugin(String body, {required String source}) async {
    if (!rootDir.existsSync()) {
      rootDir.createSync(recursive: true);
    }
    final name = 'plugin_${DateTime.now().microsecondsSinceEpoch}.js';
    final file = File('${rootDir.path}/$name');
    await file.writeAsString(body, flush: true);
    return file.path;
  }

  Future<void> uninstall(PluginInfo info) async {
    final file = File(info.path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// 编辑已安装音源:修改音源名称(platform)与订阅地址(srcUrl)。
  /// 直接改写插件 JS 文件中的顶层字段(仅作用于最后一个 module.exports 之后,
  /// 与元数据解析 parseMeta 规则保持一致)。srcUrl 缺失时自动补插。
  Future<void> updatePlugin(
    PluginInfo info, {
    required String name,
    required String srcUrl,
  }) async {
    final newName = name.trim();
    if (newName.isEmpty) {
      throw ArgumentError('音源名称不能为空');
    }
    final file = File(info.path);
    if (!file.existsSync()) {
      throw FileSystemException('plugin file not found', info.path);
    }
    final source = await file.readAsString();
    final idx = source.lastIndexOf('module.exports');
    if (idx < 0) {
      throw ArgumentError('插件文件缺少 module.exports,无法编辑');
    }
    final head = source.substring(0, idx);
    var tail = source.substring(idx);

    if (newName != info.platform) {
      tail = _replaceField(tail, 'platform', newName);
    }
    final newUrl = srcUrl.trim();
    if (newUrl != (info.srcUrl ?? '')) {
      tail = _replaceField(tail, 'srcUrl', newUrl, insertIfMissing: true);
    }

    await file.writeAsString(head + tail, flush: true);
  }

  /// 替换 [tail] 中 [field] 字段的字符串字面量;字段不存在时若 [insertIfMissing]
  /// 为 true 则在 platform 行之后补插。
  String _replaceField(
    String tail,
    String field,
    String value, {
    bool insertIfMissing = false,
  }) {
    final re = RegExp('($field\\s*:\\s*["\'])[^"\']*(["\'])');
    final m = re.firstMatch(tail);
    if (m != null) {
      return tail.replaceRange(
        m.start,
        m.end,
        '${m.group(1)}$value${m.group(2)}',
      );
    }
    if (!insertIfMissing) {
      throw ArgumentError('插件文件中未找到 $field 字段');
    }
    // 在 platform 字段所在行之后补插新字段。
    final pm = RegExp('platform\\s*:\\s*["\'][^"\']*["\']').firstMatch(tail);
    if (pm == null) {
      throw ArgumentError('插件文件中未找到 platform 字段');
    }
    final lineEnd = tail.indexOf('\n', pm.end);
    if (lineEnd < 0) {
      // platform 行无换行(单行导出):紧跟其后补逗号与字段
      return tail.replaceRange(pm.end, pm.end, ', $field: "$value"');
    }
    // 在 platform 行的换行之后另起一行插入
    return tail.replaceRange(lineEnd + 1, lineEnd + 1, '  $field: "$value",\n');
  }

  /// 搜索歌曲。[platform] 指定音源插件(不传则按顺序尝试全部,
  /// 第一个成功返回);若指定插件失败则抛错。[page] 从 1 开始。
  Future<Map<String, dynamic>> search(
    String keyword, {
    String? platform,
    int page = 1,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final plugins = await listPlugins();
    if (platform != null && plugins.every((p) => p.platform != platform)) {
      throw Exception('plugin not installed: $platform');
    }
    // 自动模式优先完整歌曲源,避免默认命中 iTunes 30 秒试听
    final ordered = platform != null ? plugins : [...plugins]
      ..sort((a, b) {
        int prio(String p) => switch (p) {
          'netease' => 0,
          'kuwo' => 1,
          _ => 10,
        };
        return prio(a.platform).compareTo(prio(b.platform));
      });
    for (final plugin in ordered) {
      if (platform != null && plugin.platform != platform) continue;
      try {
        final source = await File(plugin.path).readAsString();
        final result = await _sandbox.isolate(() async {
          final runtime = JsRuntimeFactory.createIsolateSafe();
          final loader = PluginLoader(runtime);
          loader.loadPlugin(source);
          final bridge = PluginBridgeAsync(runtime);
          // MusicFree 协议:search(keyword, page, type) 位置参数
          return bridge.callAsync('search', [keyword, page, 'music']);
        }, timeout: timeout);
        // 宿主补全:MusicFree 协议中 platform/songId 由宿主填充,
        // 插件结果往往缺省(如 bilibili 只返回 id)。
        _normalizeResults(result, platform: plugin.platform);
        return result;
      } catch (_) {
        // 单插件失败不阻断整体;循环继续
      }
    }
    throw Exception('no plugin returned search results');
  }

  /// 补全搜索结果:platform 一律写入当前插件名(保证改名后播放路由一致,
  /// 避免插件内硬编码旧名导致 getMediaSource 匹配失败);
  /// songId 缺省时取 id。
  void _normalizeResults(
    Map<String, dynamic> result, {
    required String platform,
  }) {
    final data = result['data'];
    if (data is! List) return;
    for (final item in data) {
      if (item is! Map) continue;
      // 始终覆盖为当前插件名,插件内硬编码的旧 platform 不参与路由
      item['platform'] = platform;
      final songId = item['songId'];
      if (songId is! String || songId.isEmpty) {
        item['songId'] = item['id'];
      }
    }
  }

  /// 根据 musicItem 解析真实播放地址(走插件 getMediaSource)。
  /// 按 musicItem.platform 匹配对应插件,避免跨源错误调用
  /// (如用网易云 songId 去酷我接口拿到错误提示)。
  /// [quality]: 音质(low/standard/high/super),默认 standard。
  /// 根据 musicItem 解析真实播放地址(走插件 getMediaSource)。
  /// 按 musicItem.platform 匹配对应插件,避免跨源错误调用;
  /// 若精确匹配的插件解析失败(如酷我独家音源官方 API 失效),
  /// 自动降级尝试同平台其它插件(platform 包含相同关键词)。
  /// [quality]: 音质(low/standard/high/super),默认 standard。
  Future<Map<String, dynamic>> resolveMediaSource(
    Map<String, dynamic> musicItem, {
    String quality = 'standard',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final plugins = await listPlugins();
    final wantPlatform = musicItem['platform'] as String?;

    // 第一轮:精确匹配指定插件
    for (final plugin in plugins) {
      if (wantPlatform != null && plugin.platform != wantPlatform) continue;
      try {
        final result = await _callGetMediaSource(
          plugin,
          musicItem,
          quality,
          timeout,
        );
        if (result['url'] != null && (result['url'] as String).isNotEmpty) {
          return result;
        }
      } catch (_) {
        // 继续尝试下一个
      }
    }

    // 第二轮降级:同平台其它插件(关键词匹配,如『酷我(独家音源)』→『酷我』『酷我(念心音源)』)
    if (wantPlatform != null) {
      // 提取平台关键词:取括号前的主名,如『酷我』『酷狗』『网易音乐』
      final base = wantPlatform.split('(').first.trim();
      if (base.isNotEmpty) {
        for (final plugin in plugins) {
          if (plugin.platform == wantPlatform) continue; // 已试过
          if (plugin.platform != base && !plugin.platform.startsWith(base)) {
            continue;
          }
          try {
            final result = await _callGetMediaSource(
              plugin,
              musicItem,
              quality,
              timeout,
            );
            if (result['url'] != null && (result['url'] as String).isNotEmpty) {
              return result;
            }
          } catch (_) {
            // 继续
          }
        }
      }
    }

    throw Exception(
      'no plugin resolved media source: ${wantPlatform ?? 'auto'}',
    );
  }

  /// 调用单个插件的 getMediaSource,统一处理 URL 规范化。
  Future<Map<String, dynamic>> _callGetMediaSource(
    PluginInfo plugin,
    Map<String, dynamic> musicItem,
    String quality,
    Duration timeout,
  ) async {
    final source = await File(plugin.path).readAsString();
    final result = await _sandbox.isolate(() async {
      final runtime = JsRuntimeFactory.createIsolateSafe();
      final loader = PluginLoader(runtime);
      loader.loadPlugin(source);
      final bridge = PluginBridgeAsync(runtime);
      // MusicFree 协议:getMediaSource(musicItem, quality) 位置参数
      return bridge.callAsync('getMediaSource', [musicItem, quality]);
    }, timeout: timeout);
    final raw = result['url'] as String?;
    if (raw == null || raw.isEmpty) {
      throw Exception('plugin returned empty url');
    }
    result['url'] = await _normalizeMediaUrl(raw);
    return result;
  }

  /// 按 musicItem.platform 匹配插件获取歌词源 URL,再由 Dart 侧下载解析。
  /// 不在插件内解析:flutter_js XHR 桥会把多行 JSON 的 \n 转义破坏。
  Future<String> resolveLyric(
    Map<String, dynamic> musicItem, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final plugins = await listPlugins();
    final wantPlatform = musicItem['platform'] as String?;
    for (final plugin in plugins) {
      if (wantPlatform != null && plugin.platform != wantPlatform) continue;
      try {
        final source = await File(plugin.path).readAsString();
        final result = await _sandbox.isolate(() async {
          final runtime = JsRuntimeFactory.createIsolateSafe();
          final loader = PluginLoader(runtime);
          loader.loadPlugin(source);
          final bridge = PluginBridgeAsync(runtime);
          // MusicFree 协议:getLyric(musicItem) 位置参数
          return bridge.callAsync('getLyric', [musicItem]);
        }, timeout: timeout);
        // MusicFree 协议:插件可返回 `rawLrc`(歌词纯文本)或 `url`(歌词源地址)
        final rawLrc = result['rawLrc'];
        if (rawLrc is String && rawLrc.isNotEmpty) {
          return rawLrc;
        }
        final url = result['url'];
        if (url is String && url.isNotEmpty) {
          final client = http.Client();
          try {
            final resp = await client
                .get(
                  Uri.parse(url),
                  headers: const {
                    'user-agent': 'Mozilla/5.0',
                    'referer': 'https://music.163.com/',
                  },
                )
                .timeout(timeout);
            if (resp.statusCode == 200) {
              final body = utf8.decode(resp.bodyBytes);
              // 歌词接口返回 JSON,提取 lrc.lyric 字段
              try {
                final map = jsonDecode(body);
                if (map is Map && map['lrc'] is Map) {
                  final lrc = (map['lrc'] as Map)['lyric'];
                  if (lrc is String && lrc.isNotEmpty) return lrc;
                }
              } catch (_) {
                // 非 JSON(如直接 LRC 文本),原样返回
              }
              return body;
            }
          } finally {
            client.close();
          }
        }
      } catch (_) {
        // 该插件无歌词或失败,继续下一个
      }
    }
    return '';
  }

  /// 把插件返回的播放地址规范化:
  /// 1. 跟随重定向(如网易云 media/outer/url 的 302),返回最终音频地址
  /// 2. 不再强制 http→https:酷狗等 CDN 的 https 证书不匹配或返回 403,
  ///    强制转 https 反而导致播放一会就中断。明文 http 已通过 Info.plist
  ///    的 ATS 例外(NSAllowsArbitraryLoads)放行。
  /// 规范化失败时返回原地址,交由播放器自行处理。
  Future<String> _normalizeMediaUrl(String url) async {
    var u = url.trim();
    if (u.isEmpty) return u;
    final client = HttpClient();
    try {
      var current = Uri.parse(u);
      for (var i = 0; i < 5; i++) {
        final req = await client
            .openUrl('HEAD', current)
            .timeout(const Duration(seconds: 4));
        req.followRedirects = false;
        req.headers.set('user-agent', 'Mozilla/5.0');
        // 用目标自身域名做 referer,避免写死 music.163.com 导致其它源被拒
        req.headers.set('referer', '${current.scheme}://${current.host}/');
        final resp = await req.close();
        final code = resp.statusCode;
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (code >= 300 && code < 400 && loc != null) {
          current = current.resolve(loc);
          continue;
        }
        break;
      }
      return current.toString();
    } catch (_) {
      return u;
    } finally {
      client.close(force: true);
    }
  }

  /// 插件目录:用户数据目录(稳定,不随沙箱/临时目录变化)。
  static Directory pluginsDir() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final dir = Directory('$home/.musicx/plugins');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }
    final dir = Directory('${Directory.systemTemp.path}/musicx_plugins');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}
