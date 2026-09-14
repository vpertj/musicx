import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:musicx/core/plugins/plugin_info.dart';
import 'package:musicx/core/plugins/plugin_sandbox.dart';
import 'package:musicx/core/plugins/auto_source_order.dart';
import 'package:musicx/core/plugins/plugin_store.dart';
import 'package:musicx/core/plugins/preview_detector.dart';
import 'package:musicx/core/search/original_filter.dart';
import 'package:musicx/core/plugins/result_normalizer.dart';
import 'package:musicx/core/plugins/search_failure.dart';
import 'package:musicx/core/utils/app_paths.dart';
import 'package:musicx/models/plugin_source.dart';

class PluginManager {
  final Directory rootDir;
  final PluginStore _store;
  final PluginSandbox _sandbox;
  final http.Client _client;

  /// 音频总字节数探测(试听片段检测用)。测试注入假探针,免开真实 socket;
  /// 生产为 null,走 [_audioTotalBytes] 的 dart:io 默认实现。
  final Future<int> Function(String url)? audioTotalBytesProbe;

  /// 共享的 dart:io HttpClient(短音频检测/URL 规范化复用,避免每次新建)。
  /// 延迟初始化;随 manager 生命周期存活,不主动关闭。
  HttpClient? _dartIoClient;
  HttpClient get _dartIo => _dartIoClient ??= HttpClient();

  PluginManager(
    this.rootDir, {
    http.Client? client,
    HttpClient? dartIoClient,
    this.audioTotalBytesProbe,
  }) : _store = PluginStore(rootDir),
       _sandbox = PluginSandbox(),
       _client = client ?? http.Client(),
       // 命名参数无法用私有 initializing formal,忽略该 lint
       // ignore: prefer_initializing_formals
       _dartIoClient = dartIoClient;

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
  ///
  /// 安全:仅接受 https 下载,拒绝明文 http(避免 DNS 劫持注入脚本)。
  Future<PluginInfo> installFromUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw ArgumentError('无效的插件地址:仅支持 https,拒绝明文 http:$url');
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

  /// 安装随 App 打包的内置音源:内容已由调用方从 asset 读出。
  ///
  /// 与 [installFromUrl] 同样做元数据轻量校验(platform/version 必须存在),
  /// 校验不过不落盘。
  Future<PluginInfo> installBundledJs(
    String body, {
    required String source,
  }) async {
    final meta = _store.parseMeta(body);
    final platform = meta['platform'];
    final version = meta['version'];
    if (platform is! String ||
        platform.isEmpty ||
        version is! String ||
        version.isEmpty) {
      throw ArgumentError('内置音源内容无效(缺少 platform/version):$source');
    }
    final path = await _writePlugin(body, source: source);
    return PluginInfo.fromJsMeta(
      meta,
      hash: await _store.sha256Of(File(path)),
      path: path,
    );
  }

  /// 拉取订阅源(plugins.json),返回插件条目列表。
  /// 兼容 { "plugins": [...] } 与顶层直接为数组两种格式。
  /// 仅接受 https 订阅源。
  Future<List<PluginSource>> fetchPluginSources(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw ArgumentError('无效的订阅源地址:仅支持 https:$url');
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
    final resp = await _client
        .get(uri, headers: const {'user-agent': 'MusicX/1.0'})
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw HttpException('下载失败:HTTP ${resp.statusCode}');
    }
    return utf8.decode(resp.bodyBytes);
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
  ///
  /// 安全:仅匹配 `field:` 出现在对象顶层键位置(排除注释/嵌套),且
  /// value 用 [encodeJsString] 转义,防止引号/反斜杠破坏 JS 语法。
  String _replaceField(
    String tail,
    String field,
    String value, {
    bool insertIfMissing = false,
  }) {
    // 匹配 `field: "val"` 或 `field: 'val'`,要求 field 前是行首/空白/逗号/花括号
    // (排除注释里的同名键,注释多出现在行首 `//` 后,不在键位置)。
    final fieldRe = RegExp(
      '(?:^|[\\s,{])$field(\\s*:\\s*)(["\'])([^"\']*)\\2',
      multiLine: true,
    );
    final m = fieldRe.firstMatch(tail);
    if (m != null) {
      // 整段替换为规范化的 `field: "encoded"`(引号风格统一为双引号,JS 语义不变)。
      final head = tail.substring(0, m.start);
      // 保留 field 前的一个分隔字符(空白/逗号/花括号)以维持格式。
      final suffix = tail.substring(m.end);
      return '$head$field: ${encodeJsString(value)}$suffix';
    }
    if (!insertIfMissing) {
      throw ArgumentError('插件文件中未找到 $field 字段');
    }
    // 在 platform 字段所在行之后补插新字段(值已转义)。
    final pm = RegExp('platform\\s*:\\s*["\'][^"\']*["\']').firstMatch(tail);
    if (pm == null) {
      throw ArgumentError('插件文件中未找到 platform 字段');
    }
    final lineEnd = tail.indexOf('\n', pm.end);
    final insertText = '$field: ${encodeJsString(value)}';
    if (lineEnd < 0) {
      // platform 行无换行(单行导出):紧跟其后补逗号与字段
      return tail.replaceRange(pm.end, pm.end, ', $insertText');
    }
    // 在 platform 行的换行之后另起一行插入
    return tail.replaceRange(lineEnd + 1, lineEnd + 1, '  $insertText,\n');
  }

  /// 生成合法的 JS 字符串字面量(带双引号),转义引号/反斜杠/控制字符。
  ///
  /// 用 [jsonEncode] 实现:JSON 字符串字面量与 JS 字符串字面量在引号、
  /// 反斜杠、控制字符的转义规则上兼容,可安全插入 JS 源码而不破坏语法。
  static String encodeJsString(String value) => jsonEncode(value);

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
    // 自动模式:优先完整歌曲源 + 跳过已知失效音源 + 同平台去重
    final ordered = platform != null
        ? plugins
        : _prioritizeAutoPlugins(plugins);
    final failures = <SearchFailure>[];
    Map<String, dynamic>? fallback; // 首个成功但质量存疑的结果
    for (final plugin in ordered) {
      if (platform != null && plugin.platform != platform) continue;
      try {
        final source = await File(plugin.path).readAsString();
        final result = await _sandbox.callPlugin(source, 'search', [
          keyword,
          page,
          'music',
        ], timeout: timeout);
        // 宿主补全:MusicFree 协议中 platform/songId 由宿主填充,
        // 插件结果往往缺省(如 bilibili 只返回 id)。
        _normalizeResults(result, platform: plugin.platform);

        // 指定平台:直接用它的结果(用户明确要这个源)。
        if (platform != null) return result;

        // 自动模式:做一次「结果质量校验」。实测网易云搜「晴天 周杰伦」
        // 首屏 20 条全是翻唱号(没有一条周杰伦),而腾讯音乐同一查询是干净的
        // 正版列表 —— 这种结果直接返回给用户,就是「搜出来全是翻唱」。
        // 因此:查询带歌手词却一条都匹配不上时,继续试下一个源;
        // 所有源都这样,再退回第一个结果(不能什么都不给)。
        if (_looksLikeSearchResults(result, keyword)) return result;
        fallback ??= result;
      } catch (e) {
        // 单插件失败不阻断整体;循环继续,但记下原因供报错使用
        failures.add(SearchFailure(platform: plugin.platform, error: e));
      }
    }
    if (fallback != null) return fallback;
    throw Exception(describeSearchFailures(failures));
  }

  /// 结果质量校验:查询含歌手词时,结果里至少要有一条歌手命中。
  bool _looksLikeSearchResults(Map<String, dynamic> result, String keyword) {
    final data = (result['data'] as List?) ?? const [];
    if (data.isEmpty) return false;
    return isArtistMatchedResults([
      for (final raw in data)
        if (raw is Map)
          (
            title: '${raw['title'] ?? ''}',
            artist: '${raw['artist'] ?? ''}',
            album: '${raw['album'] ?? ''}',
          ),
    ], keyword);
  }

  /// 自动模式插件排序与过滤:
  /// - 已知失效音源(官方 API 已死且无代理兜底)直接跳过,避免拖慢搜索
  /// - 同平台多个变体只保留一个(如多个『酷我』),减少重复请求
  /// - 其余按优先级排序(netease/kuwo 优先)

  /// 测试音源是否可用:执行一次搜索 + 播放地址解析。
  /// 返回 (是否可用, 详情)。供设置页『测试』按钮使用。
  Future<({bool ok, String detail})> testPlugin(String platform) async {
    final sw = Stopwatch()..start();
    try {
      final r = await search('晴天', platform: platform, page: 1);
      final data = (r['data'] as List?) ?? [];
      if (data.isEmpty) {
        return (ok: false, detail: '搜索无结果');
      }
      final song = Map<String, dynamic>.from(data.first as Map);
      final media = await resolveMediaSource(song);
      final url = media['url'] as String? ?? '';
      if (url.isEmpty) return (ok: false, detail: '解析播放地址为空');
      sw.stop();
      return (
        ok: true,
        detail: '可用 · ${sw.elapsedMilliseconds}ms · ${song['title'] ?? ''}',
      );
    } catch (e) {
      sw.stop();
      return (ok: false, detail: '失效 · ${sw.elapsedMilliseconds}ms · $e');
    }
  }

  List<PluginInfo> _prioritizeAutoPlugins(List<PluginInfo> plugins) {
    // 归类与排序收敛在纯函数里(auto_source_order),按上游地址/文件名归类,
    // 用户改名(如「网易云音乐」→「网yi」)后依然能排到正确优先级。
    final identities = [
      for (final p in plugins)
        SourceIdentity(
          platform: p.platform,
          srcUrl: p.srcUrl ?? '',
          fileName: p.path.split('/').last,
        ),
    ];
    final ordered = orderAutoSourceIdentities(identities);
    final byPlatform = {for (final p in plugins) p.platform: p};
    return [
      for (final id in ordered)
        if (byPlatform[id.platform] != null) byPlatform[id.platform]!,
    ];
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
      normalizeResultItem(item, platform: platform);
    }
  }

  /// 媒体地址缓存:预取/重试/切回同一首歌时直接命中,不再走插件解析
  /// (解析要起 isolate + 多次网络请求,秒级耗时;缓存命中近瞬时)。
  /// 取流地址通常带签名时效,TTL 取 10 分钟足够短。
  static const Duration _mediaCacheTtl = Duration(minutes: 10);
  final Map<String, ({Map<String, dynamic> result, DateTime expiry})>
  _mediaCache = {};

  String _mediaCacheKey(Map<String, dynamic> musicItem, String quality) =>
      '${musicItem['platform']}|${musicItem['songId'] ?? musicItem['id']}|$quality';

  /// 根据 musicItem 解析真实播放地址(走插件 getMediaSource)。
  /// 命中缓存近瞬时返回;未命中走 [_resolveMediaSourceUncached] 并写缓存。
  /// [quality]: 音质(low/standard/high/super),默认 standard。
  Future<Map<String, dynamic>> resolveMediaSource(
    Map<String, dynamic> musicItem, {
    String quality = 'standard',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final key = _mediaCacheKey(musicItem, quality);
    final hit = _mediaCache[key];
    if (hit != null && DateTime.now().isBefore(hit.expiry)) {
      return hit.result;
    }
    final result = await _resolveMediaSourceUncached(
      musicItem,
      quality: quality,
      timeout: timeout,
    );
    _mediaCache[key] = (
      result: result,
      expiry: DateTime.now().add(_mediaCacheTtl),
    );
    // 简单上限:防止长会话膨胀(FIFO 淘汰)
    while (_mediaCache.length > 64) {
      _mediaCache.remove(_mediaCache.keys.first);
    }
    return result;
  }

  /// 预取播放地址(只预热缓存,不抛错 —— 供切歌提速,失败不影响播放)。
  Future<void> prefetchMediaSource(
    Map<String, dynamic> musicItem, {
    String quality = 'standard',
  }) async {
    try {
      await resolveMediaSource(musicItem, quality: quality);
    } catch (_) {
      // 预取失败静默:真正切歌时会按原流程重试
    }
  }

  Future<Map<String, dynamic>> _resolveMediaSourceUncached(
    Map<String, dynamic> musicItem, {
    required String quality,
    required Duration timeout,
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
          // 第一轮同样做试听检测:网易/腾讯对 VIP 歌返回 20~45 秒试听,
          // 命中则落入后续轮次换完整版(与二/三轮判定口径一致)。
          if (await _isPreviewAudio(result['url'] as String, musicItem)) {
            continue;
          }
          return result;
        }
      } catch (_) {
        // 继续尝试下一个
      }
    }

    // 第二轮降级:同平台其它插件(关键词匹配,如『酷我(独家音源)』→『酷我(念心音源)』)
    // 候选排序:代理型音源(念心/met 等第三方中转,通常返回完整音频)优先,
    // 避免先命中官方 CDN 的『请在手机客户端播放』提示音(短音频)。
    if (wantPlatform != null) {
      final base = wantPlatform.split('(').first.trim();
      if (base.isNotEmpty) {
        final candidates =
            plugins.where((p) {
              if (p.platform == wantPlatform) return false; // 已试过
              return p.platform == base || p.platform.startsWith(base);
            }).toList()..sort(
              (a, b) =>
                  _proxyScore(b.platform).compareTo(_proxyScore(a.platform)),
            );
        for (final plugin in candidates) {
          try {
            final result = await _callGetMediaSource(
              plugin,
              musicItem,
              quality,
              timeout,
            );
            final url = result['url'] as String?;
            if (url == null || url.isEmpty) continue;
            // 试听片段/提示音检测:结合歌曲时长判断,跳过并继续换源
            if (await _isPreviewAudio(url, musicItem)) continue;
            return result;
          } catch (_) {
            // 继续
          }
        }
      }
    }

    // 第三轮:跨源换源。QQ/网易的 VIP 歌曲常只给 20 秒试听,
    // 同一首歌在其它音源(酷我/念心等)往往是完整版,故按「歌名+歌手」
    // 到其它已装音源里找同曲再取流。
    final cross = await _resolveFromOtherSources(
      plugins: plugins,
      musicItem: musicItem,
      quality: quality,
      timeout: timeout,
    );
    if (cross != null) return cross;

    throw Exception(
      '该歌曲在已装音源中只找到试听片段(通常需要登录或会员),'
      '可在设置里换用其它音源后重试',
    );
  }

  /// 跨源换源:按歌名+歌手在其它音源里搜索同一首歌并取流。
  ///
  /// 只在同平台候选都拿不到完整音频时调用(见 [resolveMediaSource] 第三轮)。
  Future<Map<String, dynamic>?> _resolveFromOtherSources({
    required List<PluginInfo> plugins,
    required Map<String, dynamic> musicItem,
    required String quality,
    required Duration timeout,
  }) async {
    final title = (musicItem['title'] as String?)?.trim() ?? '';
    final artist = (musicItem['artist'] as String?)?.trim() ?? '';
    final wantPlatform = musicItem['platform'] as String?;
    if (title.isEmpty) return null;
    final keyword = artist.isEmpty ? title : '$title $artist';

    // 到其它音源里搜(自动顺序:网易 → 腾讯 → 酷我 …)
    for (final plugin in _prioritizeAutoPlugins(plugins)) {
      if (plugin.platform == wantPlatform) continue;
      try {
        final source = await File(plugin.path).readAsString();
        final found = await _sandbox.callPlugin(source, 'search', [
          keyword,
          1,
          'music',
        ], timeout: timeout);
        final data = (found['data'] as List?) ?? const [];
        for (final raw in data) {
          if (raw is! Map) continue;
          final candidate = Map<String, dynamic>.from(raw);
          // 与主链路一致地归一化:platform/songId 补全 + 时长量纲(酷我等
          // 源返回「秒」)。此前漏了这步,duration=267 被当成 267ms,
          // 试听检测的「应有体积」算成几 KB,任何片段都被判为完整曲放行。
          normalizeResultItem(candidate, platform: plugin.platform);
          if (!_sameSong(candidate, musicItem)) continue;
          final result = await _callGetMediaSource(
            plugin,
            candidate,
            quality,
            timeout,
          );
          final url = result['url'] as String?;
          if (url == null || url.isEmpty) continue;
          if (await _isPreviewAudio(url, candidate)) continue;
          return result;
        }
      } catch (_) {
        // 单个音源失败不影响其它音源
      }
    }
    return null;
  }

  /// 判断两个结果是否为同一首歌:歌名归一化后相等,且歌手有交集。
  bool _sameSong(Map<String, dynamic> a, Map<String, dynamic> b) {
    String norm(Object? v) => (v as String? ?? '').toLowerCase().replaceAll(
      RegExp(r'[\s\(\)\[\]【】\-—_·.,，、]'),
      '',
    );
    final ta = norm(a['title']);
    final tb = norm(b['title']);
    if (ta.isEmpty || ta != tb) return false;
    final aa = norm(a['artist']);
    final ab = norm(b['artist']);
    if (aa.isEmpty || ab.isEmpty) return true;
    if (aa == ab) return true;
    // 歌手串常见「A/B」「A、B」「A feat. B」,做包含判断
    return aa.contains(ab) || ab.contains(aa);
  }

  /// 代理型音源评分:越高的越优先尝试。
  /// 官方 CDN 直链(kuwo.cn 等)常返回『请在手机客户端播放』提示音,
  /// 第三方代理(nxinxz/meting 等)通常返回完整音频。
  int _proxyScore(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('念心') || p.contains('nxinxz') || p.contains('met')) {
      return 10;
    }
    if (p.contains('代理') || p.contains('proxy')) return 8;
    if (p == 'kuwo' || p.contains('酷我') || p.contains('kuwo')) return 3;
    return 0;
  }

  /// 试听片段/提示音检测:取真实音频体积,结合歌曲时长判断。
  ///
  /// 两点实测教训:
  /// - 仅用「小于 256KB」会漏掉 20 秒试听(128kbps ≈ 320KB);
  /// - 这些 CDN 对 HEAD 请求返回 0/-1(或 403),所以必须用
  ///   `GET + Range: bytes=0-0` 读 `Content-Range` 里的总长度。
  Future<bool> _isPreviewAudio(
    String url,
    Map<String, dynamic> musicItem,
  ) async {
    final bytes = audioTotalBytesProbe != null
        ? await audioTotalBytesProbe!(url)
        : await _audioTotalBytes(url);
    final durationMs = (musicItem['duration'] as num?)?.toInt();
    final verdict = bytes <= 0
        ? false
        : looksLikePreview(contentLength: bytes, durationMs: durationMs);
    // 诊断:真机上曾出现「片段被当成完整曲返回」,把边界数值打出来便于定位
    // (体积探测失败会静默放过,光看结果无法区分)。
    debugPrint(
      'MusicX 试听检测: bytes=$bytes durationMs=$durationMs '
      'preview=$verdict host=${Uri.tryParse(url)?.host}',
    );
    return verdict;
  }

  /// 读取音频真实总字节数;失败返回 -1(调用方按「未知」处理)。
  Future<int> _audioTotalBytes(String url) async {
    try {
      final req = await _dartIo
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 6));
      // 只要 1 字节,但响应头会带上整段长度
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      req.followRedirects = true;
      final resp = await req.close();
      final range = resp.headers.value(HttpHeaders.contentRangeHeader);
      final len = resp.contentLength;
      await resp.drain<void>();
      if (range != null && range.contains('/')) {
        final total = int.tryParse(range.split('/').last.trim());
        if (total != null && total > 0) return total;
      }
      return len;
    } catch (_) {
      return -1;
    }
  }

  /// 调用单个插件的 getMediaSource,统一处理 URL 规范化。
  Future<Map<String, dynamic>> _callGetMediaSource(
    PluginInfo plugin,
    Map<String, dynamic> musicItem,
    String quality,
    Duration timeout,
  ) async {
    final source = await File(plugin.path).readAsString();
    final result = await _sandbox.callPlugin(source, 'getMediaSource', [
      // 还原插件专属字段(如 QQ 的 songmid/strMediaMid),否则部分插件取不到流
      pluginItem(musicItem),
      quality,
    ], timeout: timeout);
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
    // 同平台降级:歌曲 platform 可能是『酷我』,而插件名为『酷我(独家音源)』
    // 等变体,精确串匹配会漏掉;参照 resolveMediaSource 用 base 关键词匹配。
    final base = wantPlatform?.split('(').first.trim();
    for (final plugin in plugins) {
      final matches =
          wantPlatform == null ||
          plugin.platform == wantPlatform ||
          (base != null &&
              base.isNotEmpty &&
              (plugin.platform == base || plugin.platform.startsWith(base)));
      if (!matches) continue;
      // 上游歌词接口会偶发失败:安卓模拟器实测酷我歌词接口返回 null,
      // 插件抛 `cannot read property 'lrclist' of null`,一次失败就返回空
      // 会让用户看到「没有歌词」。故单插件重试一次再放弃(仍是毫秒级)。
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final source = await File(plugin.path).readAsString();
          final result = await _sandbox.callPlugin(source, 'getLyric', [
            // 关键:tx.js 的歌词接口用 musicItem.songmid,该字段只存在于
            // 插件原始结果中,必须从 extra 还原,否则歌词为空。
            pluginItem(musicItem),
          ], timeout: timeout);
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
        } catch (e) {
          // 该插件无歌词或失败,继续下一个;记录日志便于诊断。
          if (attempt == 2) {
            debugPrint('MusicX 歌词: [${plugin.platform}] getLyric 失败: $e');
          }
        }
      }
    }
    // 跨源歌词兜底:本平台的源都拿不到歌词时(上游接口偶发返回 null、
    // 或该源本身无歌词),按「歌名+歌手」到其它已装音源找同一首歌的歌词。
    // 与取流的跨源换源同一思路:实测酷我歌词接口会偶发返回 null,
    // 只重试同源仍会让用户看到「暂无歌词」。
    final cross = await _lyricFromOtherSources(
      plugins: plugins,
      musicItem: musicItem,
      timeout: timeout,
      excludePlatform: wantPlatform,
    );
    if (cross != null && cross.isNotEmpty) return cross;

    debugPrint(
      'MusicX 歌词: 未获取到 "${musicItem['title']}" '
      '(platform=$wantPlatform) 的歌词',
    );
    return '';
  }

  /// 到其它音源找同一首歌的歌词;找不到返回 null。
  Future<String?> _lyricFromOtherSources({
    required List<PluginInfo> plugins,
    required Map<String, dynamic> musicItem,
    required Duration timeout,
    String? excludePlatform,
  }) async {
    final title = (musicItem['title'] as String?)?.trim() ?? '';
    final artist = (musicItem['artist'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;
    final keyword = artist.isEmpty ? title : '$title $artist';

    for (final plugin in _prioritizeAutoPlugins(plugins)) {
      if (plugin.platform == excludePlatform) continue;
      try {
        final source = await File(plugin.path).readAsString();
        final found = await _sandbox.callPlugin(source, 'search', [
          keyword,
          1,
          'music',
        ], timeout: timeout);
        final data = (found['data'] as List?) ?? const [];
        for (final raw in data) {
          if (raw is! Map) continue;
          final candidate = Map<String, dynamic>.from(raw);
          normalizeResultItem(candidate, platform: plugin.platform);
          if (!_sameSong(candidate, musicItem)) continue;
          final lyric = await _sandbox.callPlugin(source, 'getLyric', [
            pluginItem(candidate),
          ], timeout: timeout);
          final rawLrc = lyric['rawLrc'];
          if (rawLrc is String && rawLrc.isNotEmpty) {
            debugPrint(
              'MusicX 歌词: 跨源命中 ${plugin.platform} '
              '(${candidate['title']}) ${rawLrc.length} 字符',
            );
            return rawLrc;
          }
        }
      } catch (_) {
        // 单个音源失败继续尝试其它音源
      }
    }
    return null;
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
    final client = _dartIo;
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
    }
  }

  /// 插件目录:应用数据目录下的 plugins(macOS 为 ~/.musicx/plugins)。
  static Directory pluginsDir() => AppPaths.plugins;
}
