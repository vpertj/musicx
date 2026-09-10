import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 应用数据目录(跨平台统一)。
///
/// - **macOS**:保持 `~/.musicx`(兼容既有用户数据与已安装插件,避免升级后丢失)。
/// - **Windows / Android / 其他**:使用系统应用支持目录(path_provider),
///   不再依赖 `Platform.environment['HOME']`(Android 上该变量不可靠)。
///
/// 生产环境在 `main()` 中调用 [init] 完成初始化;测试或未初始化时
/// 退回临时目录(`${systemTemp}/musicx_data`),避免污染真实配置。
class AppPaths {
  AppPaths._();

  static Directory? _base;
  static Directory? _downloads;

  /// 初始化基础数据目录。应在 `runApp` 前 await 一次。
  static Future<void> init() async {
    try {
      if (Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) {
          _base = _ensure(Directory('$home/.musicx'));
        }
      }
      _base ??= _ensure(await getApplicationSupportDirectory());
    } catch (_) {
      // 平台不支持 / 插件不可用:保持 null,退回临时目录。
      _base = null;
    }
    try {
      _downloads = await getDownloadsDirectory();
    } catch (_) {
      _downloads = null;
    }
  }

  static Directory _ensure(Directory dir) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 基础数据目录(settings / library / search_history / downloads 等)。
  static Directory get base {
    final b = _base;
    if (b != null) return _ensure(b);
    return _ensure(Directory('${Directory.systemTemp.path}/musicx_data'));
  }

  /// 插件目录。
  static Directory get plugins => _ensure(Directory('${base.path}/plugins'));

  /// 数据目录下的文件。
  static File file(String name) => File('${base.path}/$name');

  /// 系统下载目录(可能为 null;调用方需回退)。
  static Directory? get downloadsBase => _downloads;
}
