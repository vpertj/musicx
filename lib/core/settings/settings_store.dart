import 'dart:convert';
import 'dart:io';

/// settings.json 的合并写存储。
///
/// 旧实现在 `_persist` 中**整体覆盖写**文件,任何新增设置项都会被其它设置项
/// 冲掉;因此所有读写必须经由 [SettingsStore]:[merge] 只覆盖传入的 key。
///
/// 只做一层浅合并:当前全部设置项都是标量或一层嵌套 map,无需深合并。
class SettingsStore {
  SettingsStore(this.file);

  final File file;

  /// 读取全部设置;文件不存在或损坏时返回空 map(不抛异常)。
  Map<String, dynamic> readAll() {
    try {
      if (!file.existsSync()) return const {};
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) return Map<String, dynamic>.of(decoded);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return const {};
  }

  /// 合并写入:只覆盖 [patch] 中出现的 key。
  void merge(Map<String, dynamic> patch) {
    if (patch.isEmpty) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(<String, dynamic>{...readAll(), ...patch}));
    } catch (_) {}
  }
}
