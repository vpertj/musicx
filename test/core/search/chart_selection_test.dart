// test/core/search/chart_selection_test.dart
//
// 用户反馈:「首页热歌不是热歌、新歌不是新歌,推荐内容不对」。
//
// 根因不是数据造假(插件调的是各音源官方榜单接口),而是**选榜方式**:
// 此前盲取插件返回的第一个榜单,并把它展示在固定标题「热门推荐」下。
// 不同音源返回顺序不同(有的第一个是「会员飙升榜」甚至「万物DJ榜」),
// 于是用户看到的根本不是热歌榜,标题也看不出区别。
//
// 这里锁死按名称优先挑榜、并把选中项排到首位的契约。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/chart_selection.dart';

Map<String, dynamic> chart(String title, {String id = 'x'}) => {
  'title': title,
  'id': id,
  'platform': 'kuwo',
};

void main() {
  group('pickDefaultChartIndex:优先挑真正的热歌榜', () {
    test('酷我式顺序:第一个就是热歌榜 → 选 0', () {
      final lists = [
        chart('酷我热歌榜'),
        chart('酷我飙升榜'),
        chart('酷我新歌榜'),
      ];
      expect(pickDefaultChartIndex(lists), 0);
    });

    test('热歌榜不在首位时也要挑中它(而非盲取第一个)', () {
      // 实测某音源第一个是「会员飙升榜」,直接取 0 会展示错榜
      final lists = [
        chart('会员飙升榜'),
        chart('会员爱听排行榜'),
        chart('酷我热歌榜'),
        chart('网红新歌榜'),
      ];
      expect(
        pickDefaultChartIndex(lists),
        2,
        reason: '必须按名称匹配热歌榜,不能盲取第一个',
      );
    });

    test('没有热歌榜时退而求其次选飙升榜', () {
      final lists = [chart('万物DJ榜'), chart('飙升榜'), chart('新歌榜')];
      expect(pickDefaultChartIndex(lists), 1);
    });

    test('只有新歌榜时选新歌榜', () {
      final lists = [chart('车载歌曲榜'), chart('新歌榜')];
      expect(pickDefaultChartIndex(lists), 1);
    });

    test('都没有命中 → 回落 0(不因匹配失败而空着)', () {
      final lists = [chart('古风音乐榜'), chart('KTV点唱榜')];
      expect(pickDefaultChartIndex(lists), 0);
    });

    test('空列表安全返回 0', () {
      expect(pickDefaultChartIndex(const []), 0);
    });

    test('title 缺失或为空不崩溃', () {
      final lists = <Map<String, dynamic>>[
        {'id': 'a'},
        {'title': '', 'id': 'b'},
        chart('热歌榜', id: 'c'),
      ];
      expect(pickDefaultChartIndex(lists), 2);
    });

    test('「热歌」优先于「飙升」(即便飙升排在更前)', () {
      final lists = [chart('飙升榜'), chart('热歌榜')];
      expect(pickDefaultChartIndex(lists), 1);
    });
  });

  group('selectChartsForHome:选中项排首位 + 限个数', () {
    test('把默认选中的榜排到第一个(芯片高亮位置与内容一致)', () {
      final lists = [
        chart('会员飙升榜'),
        chart('酷我热歌榜'),
        chart('新歌榜'),
        chart('华语榜'),
      ];
      final picked = selectChartsForHome(lists);
      expect(
        picked.first['title'],
        '酷我热歌榜',
        reason: '首位应是默认展示的榜,否则芯片高亮与下方内容对不上',
      );
    });

    test('其余榜单按原顺序补足,不重复', () {
      final lists = [
        chart('会员飙升榜'),
        chart('酷我热歌榜'),
        chart('新歌榜'),
      ];
      final picked = selectChartsForHome(lists);
      expect(picked.map((e) => e['title']).toList(), [
        '酷我热歌榜',
        '会员飙升榜',
        '新歌榜',
      ]);
    });

    test('超过上限时截断到 kMaxChartChips', () {
      final lists = [for (var i = 0; i < 12; i++) chart('榜单$i')];
      final picked = selectChartsForHome(lists);
      expect(picked.length, kMaxChartChips);
    });

    test('不足上限时全取', () {
      final lists = [chart('热歌榜'), chart('新歌榜')];
      expect(selectChartsForHome(lists).length, 2);
    });

    test('空列表返回空', () {
      expect(selectChartsForHome(const []), isEmpty);
    });
  });
}
