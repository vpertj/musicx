# MusicX

插件化、跨平台的免费音乐播放器(Flutter)。

## 当前进度

- **Phase 1(已完成)**:插件运行时层——CommonJS 插件加载、JS↔Dart 桥、isolate 隔离与超时熔断、MusicFree 兼容数据模型。
- **Phase 2(最小可播放里程碑)**:插件管理、搜索、播放(just_audio)与播放队列。

## 运行

```bash
flutter pub get
flutter run -d macos   # 或 android / windows
```

1. 在"插件"页点击 + ,输入示例插件路径 `example/plugins/demo_plugin.js` 安装;
2. 切到"搜索"页,输入任意关键词(如 `SoundHelix`),回车;
3. 点击结果歌曲,即开始播放(示例插件返回 SoundHelix 公开测试音频)。

## 测试

```bash
flutter test
```

## 架构

五层:UI(Flutter)→ 状态管理(Riverpod)→ 插件运行时层(QuickJS)→ 播放引擎(just_audio)→ 数据层(Drift,Phase 3)。

## 协议合规

自研实现,插件协议兼容 MusicFree(CommonJS 模块导出 platform/version/search/getMediaSource 等),不复制其源码(规避 AGPL 传染)。
