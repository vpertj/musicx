# MusicX 设计文档 —— Flutter 跨平台插件化音乐播放器

日期:2026-08-10
状态:已获用户确认(技术选型、总体架构、插件运行时层、功能范围与数据模型)

## 1. 背景与目标

开发一款与 [MusicFree](https://github.com/maotoumao/MusicFree) 类似的插件化音乐播放器,支持 **Android、Windows、macOS** 三端。核心设计理念沿用 MusicFree:播放器本体不含任何音源,搜索/播放/歌单/歌词等功能全部由第三方 **JS 插件** 提供。

**与 MusicFree 的关键差异**:
- 技术栈:MusicFree 用 React Native,本项目用 **Flutter + 内嵌 QuickJS**
- 平台:MusicFree 仅 Android/鸿蒙,本项目覆盖 Android + Windows + macOS 桌面
- 安全性:MusicFree 插件与主程序共享 JS 上下文(其作者自认是安全弱点);本项目插件运行在**独立 isolate** 并有超时熔断

**协议合规**:本项目为自研实现,**不复制 MusicFree 源码**;仅兼容其插件协议(接口约定与数据结构属于设计思想,不受 AGPL-3.0 版权保护),从而规避 AGPL 传染,同时可复用其插件生态。

## 2. 技术选型(已确认)

| 层 | 选型 | 说明 |
|---|---|---|
| UI 框架 | Flutter | 一套代码覆盖 Android/Windows/macOS |
| 插件运行时 | flutter_js / quickjs_engine(内嵌 QuickJS) | 运行 MusicFree 兼容的 CommonJS JS 插件;支持 xhr/fetch/Promise |
| 音频播放 | just_audio | 三端均支持 URL/文件/流/播放列表 |
| 状态管理 | Riverpod | 播放队列、播放器状态、插件状态、设置/主题 |
| 本地存储 | Drift(SQLite)+ 文件系统 | 歌单、收藏、历史、设置、歌词/封面缓存、插件文件 |

选型依据:
- 用户熟悉 Flutter/Dart,学习成本最低
- Flutter 官方支持全部三个目标平台
- 已存在用 Flutter 复刻 MusicFree 架构的先例(Flutter + just_audio 全端构建通过)
- QuickJS 引擎(flutter_js/quickjs_engine)在 Android/Windows/macOS 均有实现,支持插件所需的网络能力

## 3. 总体架构

```
┌───────────────────────────────────────────────────────┐
│                     UI 层 (Flutter)                    │
│   主界面/搜索/歌单/播放页/歌词页/设置  —— 纯 Dart 组件   │
├───────────────────────────────────────────────────────┤
│                 状态管理层 (Riverpod)                   │
│   播放队列 · 播放器状态 · 插件状态 · 设置/主题           │
├───────────────────────────────────────────────────────┤
│              插件运行时层 (QuickJS 引擎)                │
│   插件加载器 · CommonJS shim · JS↔Dart Bridge           │
│   ★ 本项目最核心、工作量最大的模块                      │
├───────────────────────────────────────────────────────┤
│                 播放引擎层 (just_audio)                 │
│   音频播放 · 队列控制 · 音量/进度 · 锁屏/后台播放        │
├───────────────────────────────────────────────────────┤
│                数据层 (Drift + 文件系统)                │
│   歌单/收藏/播放历史 · 歌词缓存 · 插件文件存储 · 设置    │
└───────────────────────────────────────────────────────┘
```

**设计原则**:
- **单向数据流**:UI 只通过状态管理层读写数据;插件运行时层被上层调用,不反向依赖 UI
- **层间隔离**:每层独立可测;插件层可脱离 UI 单独做协议测试
- **三端共享同一套代码**,仅平台相关初始化(窗口标题、系统托盘等)走平台通道
- **插件与 UI 线程隔离**:插件运行在独立 Dart isolate,崩溃/死循环不影响 UI

## 4. 插件运行时层(核心难点)

### 4.1 插件加载流程
1. **扫描**:启动时扫描插件目录(Android: `app_support/plugins`;桌面: 应用数据目录 `plugins/`),收集 `*.js` 文件
2. **解析**:Dart 侧轻量解析 CommonJS 导出结构,读取元数据:`platform`(插件名)、`version`、`srcUrl`(更新地址)
3. **加载**:将 JS 源码注入 QuickJS 运行时,执行 `module.exports` 得到插件实例
4. **实例驻留**:插件实例在 isolate 生命周期内持续存在(与 MusicFree 一致)

### 4.2 CommonJS shim
MusicFree 插件是 `module.exports = {...}` 的 CommonJS 模块。QuickJS 原生不识别 `module`/`require`,需要 Dart 侧注入:
- 提供 `module`、`exports`、`require` 三个全局对象
- `require` 支持:插件经 webpack 构建后通常为单文件打包,多数 `require` 已在构建期内联;对少数运行时 `require`,用**白名单映射**(预置 axios/cheerio 等常用纯 JS 库,或桥接到 Dart 侧实现)

### 4.3 JS↔Dart 双向通信(Bridge)
- **同步纯计算**(如 `getMediaSource`):序列化参数 → QuickJS 执行 → JSON 返回
- **异步网络**(插件内 fetch/xhr):经 onMessage 通道转发给 **Dart 侧**(用 dio 发真实 HTTP),完成后回传结果注入 JS Promise —— 网络统一由 Dart 控制,便于加超时/重试/代理/日志
- **大对象**(歌词全文、歌单数组):走 JSON 序列化,限制单次调用返回体积(防内存炸弹)

### 4.4 隔离与熔断
- 插件运行在独立 isolate,UI 永不阻塞
- 每次插件调用带超时(默认 10s,可配置),超时熔断该次调用
- JS 异常捕获后转 Dart 错误类型;连续失败 N 次标记插件"不健康",UI 提示可禁用

## 5. 功能范围(MVP,按依赖排序)

1. **插件管理**:安装(本地文件/网络 URL)、卸载、更新、启停 —— 地基,最先做
2. **搜索**:音乐/专辑/作者(走插件 `search`)
3. **播放**:播放队列、上一首/下一首、进度、音量、播放模式(顺序/随机/单曲循环)—— 走 just_audio
4. **歌单**:导入(插件 `importMusicSheet`)、本地歌单管理(建/删/增曲)、收藏
5. **歌词**:播放页滚动歌词(插件 `getLyrics`),缓存本地
6. **本地音乐**:内置"本地文件"插件(与 MusicFree 同思路,本地播放也走插件),支持导入本地音频
7. **设置**:主题(浅色/深色)、自定义背景、播放偏好、插件目录

## 6. 核心数据模型(对齐 MusicFree basic-type)

```
MusicItem     : { id, title, artist, album, artwork, duration,
                  platform(来源插件), songId(插件内ID), extra }
AlbumItem     : { id, title, artist, artwork, platform, ... }
ArtistItem    : { id, name, avatar, platform, ... }
MusicSheetItem: { id, title, artwork, platform, ... }
LyricLine     : { time, text }
PluginInfo    : { platform, version, srcUrl, enabled, hash, path }
```

## 7. 本地存储(Drift/SQLite)

- `plugins` 表:已安装插件元数据 + 启停状态
- `playlists` / `playlist_songs`:本地歌单与条目(歌曲冗余存 JSON,保证离线可用)
- `favorites`、`play_history`
- `settings`(KV):主题、播放偏好等
- 歌词/封面缓存:文件系统目录

## 8. 错误处理

| 场景 | 策略 |
|---|---|
| 插件超时/死循环 | isolate 隔离 + 10s 超时熔断 |
| 插件 JS 异常 | 捕获转 Dart 错误,不影响主程序 |
| 插件连续失败 | 标记不健康,UI 提示可禁用 |
| 网络失败 | dio 统一重试策略 + 用户可见错误提示 |
| 单次返回过大 | Bridge 层限制返回体积 |

## 9. 测试策略

- **插件协议单测**:Dart 侧用固定 JS fixture 验证 shim 与 Bridge 的协议正确性(等价于 MusicFree 在 Node 里调试插件的思路)
- **状态管理层单测**:Riverpod 逻辑(队列、播放模式、收藏)纯 Dart 测试
- **播放引擎冒烟**:just_audio 在各平台的 URL/文件播放冒烟
- **三端构建验证**:Android/Windows/macOS 构建产物通过

## 10. 已知风险与缓解

| 风险 | 缓解 |
|---|---|
| QuickJS CommonJS shim 工作量 | 插件多为 webpack 单文件打包,require 已内联;白名单兜底 |
| 插件生态兼容性 | 数据模型严格对齐 basic-type,先跑通 2-3 个真实 MusicFree 插件验证 |
| Flutter 桌面端音频/后台行为 | 分平台冒烟;锁屏/后台播放按 Android 优先,桌面降级为窗口内播放 |
| 第三方插件安全 | 不健康熔断 + 安装来源提示 + 后续可加签名校验 |

## 11. 后续实施顺序(转入 writing-plans)

1. 项目脚手架(Flutter 三端工程 + CI 构建)
2. 插件运行时层(加载器 + shim + Bridge + 隔离熔断)—— 最大工作量,优先攻坚
3. 播放引擎层接入 just_audio
4. 状态管理层 + 数据层
5. MVP 各功能页面
6. 验证:2-3 个真实插件端到端跑通
