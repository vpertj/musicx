// test/core/search/source_selection_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/search/source_selection.dart';

void main() {
  group('effectiveSearchSource', () {
    test('未选择 → 自动(null)', () {
      expect(
        effectiveSearchSource(selected: null, installedPlatforms: {'a', 'b'}),
        isNull,
      );
    });

    test('选中的源已安装 → 保持选择', () {
      expect(
        effectiveSearchSource(selected: 'b', installedPlatforms: {'a', 'b'}),
        'b',
      );
    });

    test('选中的源已不存在(改名/卸载)→ 回落自动', () {
      expect(
        effectiveSearchSource(selected: '旧名字', installedPlatforms: {'新名字'}),
        isNull,
      );
    });

    test('插件列表尚未加载完 → 不擅自改写用户选择', () {
      expect(
        effectiveSearchSource(selected: 'x', installedPlatforms: const {}),
        'x',
      );
    });

    test('改名迁移:旧名被选中时跟随到新名', () {
      expect(
        migrateSelectedSource(
          selected: '旧名字',
          from: '旧名字',
          to: '新名字',
        ),
        '新名字',
      );
      expect(
        migrateSelectedSource(selected: '别的源', from: '旧名字', to: '新名字'),
        '别的源',
      );
      expect(
        migrateSelectedSource(selected: null, from: '旧名字', to: '新名字'),
        isNull,
      );
    });
  });
}
