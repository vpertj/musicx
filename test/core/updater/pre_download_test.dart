// test/core/updater/pre_download_test.dart
//
// 用户实测:下载完成后被系统以「已安装更高版本」拒绝 —— 说明交给系统的包比
// 已装的低。这里锁住「下载前先用直链版本号拦一道」的逻辑。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/updater/install_decision.dart';

void main() {
  test('从直链解析版本号', () {
    expect(
      versionFromAssetUrl(
        'https://github.com/vpertj/musicx/releases/download/v1.7.35/MusicX-1.7.35.apk',
      ),
      '1.7.35',
    );
    expect(versionFromAssetUrl('https://x/y/MusicX-1.7.30-setup.exe'), '1.7.30');
    expect(versionFromAssetUrl('https://x/y/no-version-here.bin'), isNull);
  });

  test('直链版本比已装高 → 可以下载', () {
    expect(
      decidePreDownload(
        assetUrl: '.../download/v1.7.35/MusicX-1.7.35.apk',
        installedVersion: '1.7.31',
        expectedLatest: '1.7.35',
      ),
      PreDownloadDecision.proceed,
    );
  });

  test('直链版本等于已装版本 → 判为检查结果过期(不再白下载)', () {
    expect(
      decidePreDownload(
        assetUrl: '.../download/v1.7.31/MusicX-1.7.31.apk',
        installedVersion: '1.7.31',
        expectedLatest: '1.7.35',
      ),
      PreDownloadDecision.staleCheck,
    );
  });

  test('直链版本低于已装版本 → 判为过期(正是「已安装更高版本」的来源)', () {
    expect(
      decidePreDownload(
        assetUrl: '.../download/v1.7.30/MusicX-1.7.30.apk',
        installedVersion: '1.7.31',
        expectedLatest: '1.7.35',
      ),
      PreDownloadDecision.staleCheck,
    );
  });

  test('直链版本与最新版本不一致 → 检查结果不可信', () {
    expect(
      decidePreDownload(
        assetUrl: '.../download/v1.7.33/MusicX-1.7.33.apk',
        installedVersion: '1.7.31',
        expectedLatest: '1.7.35',
      ),
      PreDownloadDecision.staleCheck,
    );
  });

  test('直链无版本号时不拦(交给下载后的严格校验)', () {
    expect(
      decidePreDownload(
        assetUrl: 'https://x/y/latest.apk',
        installedVersion: '1.7.31',
        expectedLatest: '1.7.35',
      ),
      PreDownloadDecision.proceed,
    );
  });
}
