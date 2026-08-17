import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 搜索历史(持久化):最近搜索的关键词,最新在前,上限 12 条。
final searchHistoryProvider =
    NotifierProvider<SearchHistoryController, List<String>>(
      SearchHistoryController.new,
    );

class SearchHistoryController extends Notifier<List<String>> {
  static const int _maxEntries = 12;

  /// 历史文件位置:用户数据目录(与歌单/插件同目录)。
  static File dataFile() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final dir = Directory('$home/.musicx');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}/search_history.json');
    }
    final dir = Directory('${Directory.systemTemp.path}/musicx_data');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/search_history.json');
  }

  @override
  List<String> build() {
    // 启动时从磁盘加载
    try {
      final f = dataFile();
      if (!f.existsSync()) return const [];
      final list = (jsonDecode(f.readAsStringSync()) as List).cast<String>();
      return list.take(_maxEntries).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 记录一次搜索:去重置顶,超限裁剪,并持久化。
  void add(String keyword) {
    final kw = keyword.trim();
    if (kw.isEmpty) return;
    final next = [kw, ...state.where((e) => e != kw)];
    state = next.take(_maxEntries).toList();
    _save();
  }

  /// 清空全部历史。
  void clear() {
    state = const [];
    _save();
  }

  /// 删除单条历史。
  void remove(String keyword) {
    state = state.where((e) => e != keyword).toList();
    _save();
  }

  void _save() {
    try {
      dataFile().writeAsStringSync(jsonEncode(state), flush: true);
    } catch (_) {
      // 持久化失败不阻断使用
    }
  }
}
