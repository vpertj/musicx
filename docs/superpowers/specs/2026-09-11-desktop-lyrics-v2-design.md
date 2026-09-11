# MusicX 桌面歌词浮窗 v2 设计 ——「可调毛玻璃」

> 日期:2026-09-11
> 状态:Design(待用户审阅)
> 范围:桌面歌词浮窗的视觉质感、字号/颜色可调、自由缩放与拖动、自适应布局、配置入口与持久化
> 前置:1.6.7 已交付「浮窗 + 磨砂玻璃风」初版(`b43a8a9`)

---

## 1. 背景与目标

### 1.1 现状问题

现有浮窗(`lib/ui/desktop_lyrics/lyrics_window.dart`,263 行)已经具备独立窗口、无边框、置顶、透明、可拖动,但用户对成品明确不满意:

1. **"毛玻璃"是假的**:`_GlassCard` 用 `BackdropFilter` 做模糊。歌词窗是**独立引擎的透明窗口**,它背后是桌面而不是本引擎绘制的内容,`BackdropFilter` 没有任何东西可模糊,实际渲染结果只是一层半透明深色渐变 —— 视觉上与普通深色卡片无异,边缘生硬。
2. **字号、颜色写死**:当前句固定 `#FF5A76` / 34px,下一句固定白色 72% / 19px,没有任何调整入口。
3. **窗口无法自由缩放**:macOS 上 `window_manager` **未实现** `startResizing`(仅 Windows/Linux 有);`desktop_multi_window` 创建的 `CustomWindow` 虽然带 `.resizable`,但 Flutter 视图覆盖了整个窗口,AppKit 的边缘缩放热区被吃掉。用户实测拉不动。
4. **布局不自适应**:固定 34px/19px 双行文本 + 固定内边距,窗口拉高拉矮都长一样,拉窄则直接 ellipsis。
5. **配置无法持久化**:`settings.json` 目前由 `ThemePreferenceController._persist` **整体覆盖写**(只写 `themeMode`),任何新增设置项都会被主题切换冲掉。

### 1.2 目标

- 让卡片具备**真实可感的毛玻璃质感**(有内容被模糊、有饱和度与亮度重构、有噪点、有高光、有折射感描边)。
- 字体**颜色与大小可调**,并持久化。
- 卡片可**自由拖大缩小**,位置尺寸记忆;并可拖动摆放。
- **自适应**:字号随窗口缩放,布局随宽高自动切换,拉小不截断、拉大不溢出。
- 配置入口**两处并存**:主窗口设置页统一配置 + 浮窗上悬停快捷工具条。

### 1.3 已确认决策

| 决策点 | 结论 |
|---|---|
| 平台范围 | 先只做 macOS/Windows/Linux 通用的**纯 Dart 玻璃**;Windows 原生 Acrylic 不在本次范围 |
| 玻璃方案 | 方案 B:**模糊专辑封面作为卡片内背景** + 渐变 tint + 噪点 + 高光 + 描边 + 投影 |
| 桌面模糊 | **明确不做**:纯 Dart 方案无法模糊窗口背后的桌面(wallpaper);用户已知悉并接受 |
| 封面模糊 | **默认开启**(毛玻璃感主要来源);提供开关,关掉退化为纯彩色玻璃 |
| 工具条出现方式 | **悬停出现**(180ms 延时防误触,1.5s 无操作淡出);右键亦可唤出 |
| 自适应语义 | 字号随窗口大小缩放(带上下限)+ 布局随宽高自动切;保留「自动缩放」开关,关掉走手动字号 |
| 原生代码 | **本次不修改** `macos/`、`windows/` 任何原生代码 |
| 新增依赖 | **不新增**任何 package |

---

## 2. 设计原则

1. **模糊必须在同一引擎内发生**:只模糊"确实画在自己下方的图层",不做无效的 `BackdropFilter`。
2. **玻璃是分层的**:模糊层、tint 层、噪点层、高光层、描边层各司其职,任意一层可关(封面除外有兜底),保证任何组合下文字都清晰可读。
3. **文字永远优先**:任何配置组合、任何窗口尺寸下,歌词不得被裁切、不得不可读;对比度不足时由 tint 层兜底保底。
4. **一处定义、两处复用**:设置页预览卡与真实浮窗共用同一套渲染组件,避免"预览和实际不一样"。
5. **布局逻辑是纯函数**:自适应规则不依赖 Widget 树,可被单元测试直接覆盖。
6. **不改原生代码、不引新依赖**:全部能力在 Dart 侧完成,降低构建与跨平台风险。

---

## 3. 玻璃视觉构成

卡片自下而上分 5 层(`Stack`):

| 层 | 内容 | 可配置项 | 兜底 |
|---|---|---|---|
| ① 背景层 | 专辑封面 `Image.network(artwork)` → `BoxFit.cover` 放大 → `ColorFiltered`(饱和度提升 + 亮度压低)→ `ImageFiltered(blur)` | `showArtwork`、`blurSigma` | 无封面/加载失败/开关关闭 → 用当前文字色生成柔光斑渐变 |
| ② tint 层 | 暗色渐变压暗(左上偏亮、右下偏深),保证文字对比度 | `glassTint`(0–100 → 遮罩 alpha) | — |
| ③ 噪点层 | `CustomPainter` 绘制确定性噪点(固定随机种子),`RepaintBoundary` 缓存 | 固定低透明度 | — |
| ④ 高光层 | 左上斜向白色高光 + 1px 内描边(`Colors.white` 低透明度)、大圆角 | `cornerRadius` | — |
| ⑤ 歌词层 | 左侧律动竖条 + 当前句(彩色 + 光晕)+ 下一句 | `textColor`、`nextColor`、`fontSize`、`autoScale`、`showNext` | — |

- 卡片外层再套 `ClipRRect` 与自绘投影;窗口内保留 `18/14/18/22` 内边距,该边距同时充当**投影空间**与**缩放热区**。
- 模糊实现要点:封面图**包裹在 `ImageFiltered` 内**(模糊自己的子树),而不是像现状那样用 `BackdropFilter` 去模糊一个空背景。这是本设计成立的关键 —— `BackdropFilter` 只能模糊"同一引擎内已经绘制在它下方的图层",现状的透明窗口下该区域为空,所以模糊完全无效;封面模糊层则确有内容可模糊。
- 若封面层与歌词层需要共用一次模糊结果(如噪点层也参与),可改用 `Stack` + 底部封面 + `BackdropFilter` 包裹上层,两种写法择一,以实机性能为准。
- 性能:模糊层用 `RepaintBoundary` 隔离,歌词每 250ms 更新时不触发模糊层重绘;模糊中值(sigma)不随窗口尺寸线性放大,避免大窗口下 GPU 开销失控。

---

## 4. 自适应布局规则

新增纯函数模块 `lib/ui/desktop_lyrics/lyrics_layout.dart`:

```dart
LyricsLayout resolveLyricsLayout({
  required Size windowSize,
  required DesktopLyricsSettings settings,
  required String current,
  required String next,
});

class LyricsLayout {
  final double fontSize;      // 当前句最终字号(已夹取)
  final bool showNext;        // 是否显示下一句
  final Axis direction;       // 纵向堆叠 / 横向并排
  final EdgeInsets padding;   // 卡片内边距
  final double accentBarWidth;// 左侧竖条宽度
  final double cardRadius;    // 卡片圆角
}
```

规则:

1. **缩放系数**:`autoScale` 开启时 `scale = clamp(windowHeight / 190, 0.55, 2.2)`;关闭时 `scale = 1.0`。
   最终 `fontSize = clamp(settings.fontSize * scale, 12, 120)`。以 190 为基准是既有默认高度,保证老用户视觉不变。
2. **行数**:`windowHeight < 120` → 只显示当前句;`windowHeight >= 120 && settings.showNext` → 显示下一句。
3. **排布方向**:仅当 `showNext` 为真时,若 `windowWidth / windowHeight >= 6` 且当前句与下一句并排实测放得下 → 横向并排(`Axis.horizontal`);否则纵向堆叠(`Axis.vertical`)。
4. **溢出保护**:用 `TextPainter` 实测当前句宽度;放不下则**逐档降低字号**(步进 1px)直到下限 12;仍放不下才允许 `TextOverflow.ellipsis`。
5. **等比派生**:卡片内边距、左侧竖条宽度、圆角均按 `scale` 等比派生并夹取,保证小窗不臃肿、大窗不局促。

---

## 5. 交互:拖动、缩放、几何持久化

### 5.1 拖动

- 保留 `onPanStart → windowManager.startDragging()`(macOS 已验证可用)。
- 拖动只在**卡片主体区域**生效;悬浮工具条区域不触发拖动。

### 5.2 自由缩放(纯 Dart)

- 在窗口内边距区域布置 **8 个透明热区**:上/下/左/右 4 条边 + 4 个角,厚度 8px。
- 每个热区用 `MouseRegion` 设置对应光标(`resizeUpDown` / `resizeLeftRight` / `resizeUpLeftDownRight` / `resizeUpRightDownLeft`)。
- `onPanUpdate` 累加 delta → 计算目标 `Rect`(拖左/上边时同步移动原点)→ `windowManager.setBounds()`。
- **节流**:同一时刻只允许一个 `setBounds` 在途,新目标覆盖旧目标(丢弃中间帧),避免快速拖动时调用积压导致滞后。
- **夹取**:最小 `320 × 90`;最大不超过当前显示器工作区。
- 缩放期间禁用歌词文本的命中测试,避免手势竞争。

### 5.3 几何持久化

- 拖动/缩放**结束**后 debounce 600ms,把 `Rect` 写入 `settings.bounds`。
- 浮窗打开时还原上次几何;**还原前夹取到当前可见屏幕范围内**,防止拔掉外接显示器后窗口跑到屏幕外无法找回。
- 未记录几何时使用默认 `880 × 190` 与既有默认位置。

### 5.4 关闭

- 悬浮工具条提供关闭按钮,沿用既有 `kLyricsCloseMethod` 通道关闭浮窗。

---

## 6. 配置入口与数据流

### 6.1 主窗口:设置 → 外观 → 「桌面歌词」

- 位于既有 `_SettingsSection.appearance` 分组下,新增「桌面歌词」`_SettingsGroup`。
- 内容:实时预览卡(与浮窗共用渲染组件)+ 颜色(预设色板 + HSV 自定义)+ 字号滑杆 + 「自动缩放」开关 + 「显示下一句」开关 + 「显示封面」开关 + 玻璃浓度/模糊强度/圆角滑杆 + 「恢复默认」。
- 任一改动:立即写入 provider 持久化,并即时推送到已打开的浮窗。
- **非桌面平台(Android)隐藏该分组**:`DesktopLyricsService.supported == false` 时不渲染「桌面歌词」区块,避免出现点了没反应的无效入口;配置本身仍保留在 `settings.json` 中不受影响。

### 6.2 浮窗:悬停快捷工具条

- 鼠标进入浮窗 180ms 后淡入;移出或 1.5s 无操作淡出。
- 内容:字号 `−/+`、3 个快捷颜色、下一句开关、重置尺寸、关闭。
- 工具条自身为半透明玻璃样式,不遮挡当前句。

### 6.3 数据流

```
主窗口                                浮窗(独立引擎)
  DesktopLyricsSettingsProvider
        │ ref.listen
        ▼
  DesktopLyricsService.pushStyle() ──▶ 下行通道 musicx_desktop_lyrics
                                        (unidirectional,handler = 浮窗)
                                        ↳ setState 应用样式
  浮窗工具条改动 ──▶ 上行通道 musicx_desktop_lyrics_up
                    (unidirectional,handler = 主窗口)
                    ↳ 写回 provider 持久化(形成闭环)
```

- 下行通道沿用既有 `kLyricsChannelName`,新增 `style` 方法与 `artwork` 字段。
- 上行通道**新建**:`desktop_multi_window` 的 `unidirectional` 模式只允许一个引擎注册 handler,因此反向通信必须用**独立通道**,不改用 `bidirectional`(其配对语义在子窗口场景下不确定,风险高)。
- 浮窗打开时立即推一次当前样式与封面,避免默认样式闪现。
- `main.dart` 歌词分支补 `AppPaths.init()`,使浮窗启动时可直接读一次 `settings.json` 作为首帧样式。

---

## 7. 设置层重构

### 7.1 合并写存储(修复既有缺陷)

新增 `lib/core/settings/settings_store.dart`:

```dart
class SettingsStore {
  Map<String, dynamic> readAll();
  void merge(Map<String, dynamic> patch); // 读-改-写,只覆盖传入 key
}
```

- `ThemePreferenceController._persist` 改为 `store.merge({'themeMode': ...})`,**修掉主题切换冲掉其它设置**的缺陷。
- 对外 API(`themePreferenceProvider`、`setDark`/`setLight`)不变,既有 3 个主题测试无需修改。

### 7.2 歌词设置模型

新增 `lib/core/settings/desktop_lyrics_settings.dart`:

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `textColor` | `Color` | `0xFFFF5A76` | 当前句颜色 |
| `nextColor` | `Color` | 白 72% | 下一句颜色 |
| `fontSize` | `double` | `34` | 基准字号(自动缩放时作为基准值) |
| `autoScale` | `bool` | `true` | 字号随窗口缩放 |
| `showNext` | `bool` | `true` | 显示下一句 |
| `showArtwork` | `bool` | `true` | 封面模糊层开关 |
| `glassTint` | `int` | `45` | 暗色遮罩浓度 0–100 |
| `blurSigma` | `double` | `38` | 封面模糊强度 0–60 |
| `cornerRadius` | `double` | `26` | 卡片圆角 |
| `bounds` | `Rect?` | `null` | 上次窗口位置尺寸 |

- 提供 `copyWith` / `toJson` / `fromJson` / `clamp()`。
- `clamp()` 收敛所有数值到合法区间,配合 `fromJson` 的 try/catch,保证手工改坏 `settings.json` 不会让界面崩溃或不可用。
- `desktopLyricsSettingsProvider = NotifierProvider<DesktopLyricsSettingsController, DesktopLyricsSettings>`,写入统一走 `SettingsStore.merge`。

---

## 8. 文件与改动范围

| 文件 | 改动 |
|---|---|
| `lib/core/settings/settings_store.dart` | **新增**:合并写 JSON 存储 |
| `lib/core/settings/desktop_lyrics_settings.dart` | **新增**:设置模型 + provider |
| `lib/core/settings/settings_providers.dart` | `ThemePreferenceController` 改用 `SettingsStore.merge` |
| `lib/ui/desktop_lyrics/lyrics_layout.dart` | **新增**:自适应布局纯函数 |
| `lib/ui/desktop_lyrics/lyrics_glass.dart` | **新增**:玻璃分层渲染组件(浮窗与预览共用) |
| `lib/ui/desktop_lyrics/lyrics_window.dart` | 重写:应用设置、缩放热区、悬浮工具条、封面层 |
| `lib/ui/desktop_lyrics/desktop_lyrics_service.dart` | 新增 `pushStyle`、上行通道 handler、几何持久化 |
| `lib/ui/plugins/plugin_page.dart` | 外观分组下新增「桌面歌词」配置区 + 实时预览 |
| `lib/main.dart` | 歌词分支补 `AppPaths.init()` 与首帧样式读取 |
| `test/core/settings/settings_store_test.dart` | **新增**:合并写不冲掉其它 key |
| `test/core/settings/desktop_lyrics_settings_test.dart` | **新增**:默认值、持久化往返、越界夹取 |
| `test/ui/desktop_lyrics/lyrics_layout_test.dart` | **新增**:缩放上下限、矮窗单行、超长句降级、宽扁窗横排 |

---

## 9. 验收标准

1. 播放歌曲时打开浮窗,卡片背景能看到**被模糊、被提饱和的专辑封面**,叠加压暗、噪点、高光与描边 —— 视觉上具备明确毛玻璃质感;不再存在"模糊无效"的 `BackdropFilter`。
2. 无封面 / 无网络时卡片退化为柔和彩色玻璃,不出现破图或纯黑块。
3. 主题色与字号可在设置页调整并**立即在浮窗生效**;重启应用后保持。
4. 浮窗可拖四边与四角**自由缩放**,光标形态正确、拖动跟手无明显滞后;窗口有最小尺寸限制。
5. 字号随窗口缩放而变;窗口高度 <120 时只显示当前句;宽扁窗口改为横向并排;当前句过长时自动降字号而非直接截断。
6. 位置与尺寸重启后保持;换到更小的屏幕后窗口仍可见可操作。
7. 浮窗悬停出现工具条,可改字号/颜色/下一句/重置尺寸/关闭,改动回写主窗口持久化。
8. 设置页改动**不会冲掉**主题等既有设置;反向亦然。
9. `flutter analyze` 无新增告警;`flutter test` 全绿;新增测试覆盖第 8 节列出的三个测试文件。
10. macOS 上实际构建启动、打开歌词浮窗截图验证通过(不播放时验证兜底渐变,播放时验证封面模糊)。

---

## 10. 非目标(不在此次范围)

- **不模糊桌面壁纸**:纯 Dart 方案做不到,需 macOS `NSVisualEffectView` / Windows Acrylic,已明确排除。
- **不修改任何原生代码**(`macos/`、`windows/`),不新增第三方依赖。
- 不做点击穿透、不做多显示器独立歌词、不做歌词字体族切换、不做卡拉OK逐字高亮。
- 不改动歌词数据解析与播放器逻辑(`player_controller` / `lyric_line` 等)。
- 不改动播放页内部的全屏歌词视图(那是另一套 UI)。

---

## 11. 风险与未决项

| 风险 | 影响 | 应对 |
|---|---|---|
| `windowManager.setBounds` 在 macOS 上经平台通道往返,快速拖动可能滞后 | 缩放手感 | 单次在途节流 + 最新目标覆盖;实机验证,若明显滞后则降级为拖拽结束后一次性提交 |
| 子窗口内 `Image.network` 会重新下载封面(引擎级图片缓存不共享) | 多一次网络请求 | 复用主窗口已解析到的封面 URL;失败走兜底渐变 |
| 反向上行通道需主窗口先注册 handler | 工具条改动可能丢失 | 浮窗打开前先注册;上行失败时静默忽略,不阻塞 UI |
| 模糊层在大窗口(如全屏宽)下 GPU 开销 | 掉帧 | 模糊 sigma 不随尺寸线性放大 + `RepaintBoundary` 隔离 + 实机验证 |
