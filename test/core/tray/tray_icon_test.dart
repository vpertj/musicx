// test/core/tray/tray_icon_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/tray/tray_service.dart'
    show trayIconAsset, trayIconIsTemplate;

void main() {
  test('macOS 用黑色模板 PNG(菜单栏自动适配深浅色)', () {
    expect(trayIconAsset(isMacOS: true), 'assets/tray_icon.png');
  });

  test('Windows 用多尺寸 ICO —— LoadImage 不支持 PNG', () {
    final asset = trayIconAsset(isMacOS: false);
    expect(asset, 'assets/tray_icon.ico');
    expect(asset.endsWith('.ico'), isTrue);
  });

  test('只有 macOS 走模板图(isTemplate 在 Windows 无效)', () {
    expect(trayIconIsTemplate(isMacOS: true), isTrue);
    expect(trayIconIsTemplate(isMacOS: false), isFalse);
  });
}
