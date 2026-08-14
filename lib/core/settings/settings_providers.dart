import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前搜索音源插件名;null 表示「自动」——按顺序尝试全部已装插件。
/// 由发现页音源切换条与「我的」页设置共同读写。
class SearchSourceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? source) => state = source;
}

final searchSourceProvider = NotifierProvider<SearchSourceNotifier, String?>(
  SearchSourceNotifier.new,
);
