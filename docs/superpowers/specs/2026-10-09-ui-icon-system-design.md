# MusicX 图标系统与设置页视觉重做 设计

> 日期:2026-10-09
> 状态:Design(用户已确认:Tabler + 分两版)
> 范围:全局图标层(159 处 / 71 个语义 / 15 个文件)、设计 token、设置页视觉重做;第二版铺其余页面
> 触发:用户反馈「设置界面不好看」,并问「图标库能否换成 NutUI」

---

## 1. 背景与现状

### 1.1 用户诉求

1. 设置页不好看。
2. 能否把图标库换成 NutUI。

### 1.2 现状取证

- `grep -rho "Icons\.[a-zA-Z_]*" lib | sort -u | wc -l` → **71 个不同图标**、**159 处引用**、**15 个文件**:
  `plugin_page.dart` 44、`search_page.dart` 25、`player_page.dart` 19、`library_page.dart` 14、
  `home_shell.dart` 14、`update_row.dart` 7、`lyrics_window.dart` 7、`download_page.dart` 5,其余零散。
- 全部是 Material 的 `_rounded` / `_outlined` 变体,**没有第三方图标依赖**;`pubspec.yaml` 只有
  `cupertino_icons` 与 Material 字体。
- 71 个语义里有 **8 组「选中/未选中」配对**:
  `settings`、`explore`、`favorite`/`favorite_border`、`library_music`、`lyrics`、
  `download_for_offline`、`palette`、`light_mode`/`dark_mode`。

### 1.3 NutUI 图标为什么不用

NutUI 是 Vue/React 生态的组件库,图标形态是 [`@nutui/icons-vue`](https://www.npmjs.com/package/@nutui/icons-vue/v/0.0.13?activeTab=dependents)(SVG 组件)与网页端 iconfont 字体,
**没有 Flutter 包**。要在 Flutter 使用只能自行打包其 iconfont `.ttf` 并以 codePoint 引用,
字形仅约两百个、命名对不上 Flutter 常量,且此类自导入字体在移动端易踩坑
(同类问题见 [nutui-uniapp#422](https://github.com/nutui-uniapp/nutui-uniapp/issues/422))。
结论:**不用 NutUI 字形,用 Tabler 实现同等「线性轻盈」观感。**

### 1.4 图标集选型:Tabler(已确认)

| 候选 | 图标数 | 变体 | 结论 |
|---|---|---|---|
| **Tabler** `flutter_tabler_icons` | ~5800 | **线性 + filled** | **采用**:8 组配对能原样表达 |
| Lucide `lucide_icons_flutter` | 1776+ | 仅单笔画 | 不采用:选中态只能靠颜色区分,底部导航会糊 |
| NutUI iconfont | ~200 | 单色字体 | 不采用:见 1.3 |

两个包均已 `flutter pub add --dry-run` 验证可解析。

### 1.5 设置页「不好看」的真实原因(截图逐条)

1. **图标样式不统一**:有纯色图标、有套粉底圆角方块的、有套红底圆形的,四行四种样;
2. **行高/内边距不一致**:「过滤翻唱」这一行明显比其它行胖;
3. **控件尺度失衡**:开关是超大号红胶囊;「浅色/深色」分段控件又大又厚;
4. **层次弱**:分区标题(音乐源/外观/通用)与卡片间距不均;卡片是"一块块裸白卡",
   缺浅灰底 + 白卡 + 小圆角 + 内缩分割线的层次;
5. **底部遮挡**:迷你播放条压住列表最后一行;
6. **计数口径错**:顶部「3 个音源」把已隐藏的内置源算进去了,与「只显示用户自己装的」不一致。

---

## 2. 目标与非目标

### 2.1 目标

- 全局图标换成 Tabler 线性风格,**每处都能表达选中/未选中**;
- 图标访问收敛到**一个语义层文件**,以后换图标集只改一处;并有测试防止页面回退到 `Icons.*`;
- 建立**设计 token**(间距/圆角/行高/字号/灰底色),设置页先吃这套;
- 设置页按 §1.5 六条逐条修到「像 NutUI」而不是「像 Material 默认」;
- 用**模拟器真机截图**验收,改动可见、可回退。

### 2.2 非目标(本版明确不做)

- 不改品牌色(仍是现有红);
- 不改信息架构与交互流程(只是视觉与图标);
- 不引入 NutUI 字体;
- 不做发现页/播放页/我的/下载页的细修 —— 第二版跟 token 走(见 §5)。

### 2.3 已确认决策

| 决策点 | 结论 |
|---|---|
| 图标集 | Tabler(`flutter_tabler_icons`),线性为主、选中用 filled |
| 图标访问方式 | 新增 `lib/ui/icons.dart` 语义层;页面禁止直接写 `Icons.*` |
| 视觉基准 | NutUI 观感:浅灰底 + 白卡 + 12~16 圆角 + 56 行高 + 20px 图标 + 13px 灰标题 |
| 发布节奏 | 分两版:第一版「图标层 + 全局 Tabler + token + 设置页」,第二版铺其余页面 |
| 验收方式 | 模拟器安装 → 截图给用户看 → 满意才发版 |

---

## 3. 设计

### 3.1 图标语义层 `lib/ui/icons.dart`

页面不再引用图标库,而是引用**语义**:

```dart
/// 全局图标语义层:页面只认这里的名字,换图标集只改这一个文件。
/// 命名:`xxx` = 常态(线性);`xxxActive` = 选中/激活(filled)。
abstract final class AppIcons {
  // 底部导航
  static const IconData explore = TablerIcons.compass;
  static const IconData exploreActive = TablerIcons.compass_filled;
  static const IconData mine = TablerIcons.user;
  static const IconData mineActive = TablerIcons.user_filled;
  static const IconData settings = TablerIcons.settings;
  static const IconData settingsActive = TablerIcons.settings_filled;
  // 播放控制
  static const IconData play = TablerIcons.player_play;
  static const IconData pause = TablerIcons.player_pause;
  static const IconData prev = TablerIcons.player_skip_back;
  static const IconData next = TablerIcons.player_skip_forward;
  static const IconData repeat = TablerIcons.repeat;
  static const IconData repeatOne = TablerIcons.repeat_once;
  static const IconData shuffle = TablerIcons.arrows_shuffle;
  static const IconData volume = TablerIcons.volume;
  // 队列 / 曲库 / 下载
  static const IconData playlist = TablerIcons.playlist;
  static const IconData queue = TablerIcons.playlist;
  static const IconData addToPlaylist = TablerIcons.playlist_add;
  static const IconData library = TablerIcons.library_music; // 若不存在用 music
  static const IconData album = TablerIcons.disc;
  static const IconData download = TablerIcons.download;
  static const IconData downloaded = TablerIcons.download_filled;
  static const IconData delete = TablerIcons.trash;
  // 发现页 / 搜索
  static const IconData search = TablerIcons.search;
  static const IconData searchOff = TablerIcons.search_off;
  static const IconData chart = TablerIcons.chart_bar; // 排行榜
  static const IconData fire = TablerIcons.flame; // 热歌
  static const IconData history = TablerIcons.history;
  static const IconData recent = TablerIcons.clock;
  static const IconData radar = TablerIcons.radar_2;
  // 其它
  static const IconData favorite = TablerIcons.heart;
  static const IconData favoriteActive = TablerIcons.heart_filled;
  static const IconData close = TablerIcons.x;
  static const IconData check = TablerIcons.check;
  static const IconData chevronRight = TablerIcons.chevron_right;
  static const IconData chevronDown = TablerIcons.chevron_down;
  static const IconData add = TablerIcons.plus;
  static const IconData remove = TablerIcons.minus;
  static const IconData refresh = TablerIcons.refresh;
  static const IconData restart = TablerIcons.restart;
  static const IconData update = TablerIcons.cloud_download;
  static const IconData info = TablerIcons.info_circle;
  static const IconData error = TablerIcons.alert_circle;
  static const IconData edit = TablerIcons.pencil;
  static const IconData link = TablerIcons.link;
  static const IconData openExternal = TablerIcons.external_link;
  static const IconData folder = TablerIcons.folder_open;
  static const IconData extension = TablerIcons.puzzle;
  static const IconData rss = TablerIcons.rss;
  static const IconData widgets = TablerIcons.layout_grid;
  static const IconData tune = TablerIcons.adjustments;
  static const IconData palette = TablerIcons.palette;
  static const IconData lightMode = TablerIcons.sun;
  static const IconData darkMode = TablerIcons.moon;
  static const IconData lyrics = TablerIcons.microphone_2;
  static const IconData subtitles = TablerIcons.subtitles;
  static const IconData music = TablerIcons.music;
  static const IconData cloudOff = TablerIcons.cloud_off;
  static const IconData verified = TablerIcons.rosette_discount_check;
  static const IconData autoAwesome = TablerIcons.sparkles;
  static const IconData textFields = TablerIcons.text_size;
  static const IconData viewAgenda = TablerIcons.layout_list;
  static const IconData viewDay = TablerIcons.layout_rows;
  static const IconData blur = TablerIcons.blur;
  static const IconData label = TablerIcons.tag;
  static const IconData insertFile = TablerIcons.file_music;
  static const IconData cancel = TablerIcons.circle_x;
  static const IconData removeCircle = TablerIcons.circle_minus;
  static const IconData checkCircle = TablerIcons.circle_check;
  static const IconData checkCircleFilled = TablerIcons.circle_check_filled;
  static const IconData settingsBackup = TablerIcons.settings_automation;
}
```

**说明与保障**:

- 常量名按 Tabler 官方命名(kebab → snake);表中少数不确定项(如 `library_music`、
  `radar_2`、`rosette_discount_check`)**以 `flutter analyze` 为准**:不存在的常量直接编译
  报错,实现时用同语义的 Tabler 图标替换,不猜、不留运行期兜底。
- `Icons.*` 完全消失由测试锁住:见 §4.1。
- 尺寸/颜色不写进语义层:统一由 token 与调用点决定。

### 3.2 设计 token `lib/ui/tokens.dart`

```dart
/// 视觉 token:设置页先吃这套,第二版其余页面复用。
abstract final class AppSpacing {
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24;
}

abstract final class AppRadius {
  static const double card = 14, chip = 10, control = 10, icon = 10;
}

abstract final class AppSize {
  static const double rowHeight = 56;   // 设置行统一高度
  static const double icon = 20;        // 行内图标
  static const double iconLarge = 24;   // 空态/大按钮
  static const double dividerInset = 16; // 分割线左内缩
}

abstract final class AppText {
  static const double sectionTitle = 13; // 分区标题
  static const double rowTitle = 15;
  static const double rowSubtitle = 12;
}

/// 颜色:跟随主题,浅色下即 NutUI 观感。
abstract final class AppPalette {
  static const Color lightBackground = Color(0xFFF5F6F8); // 页面灰底
  static const Color lightCard = Color(0xFFFFFFFF);       // 卡片
  static const Color lightDivider = Color(0xFFEDEEF1);
  static const Color lightTitle = Color(0xFF8A8F99);      // 分区标题灰
}
```

`app_theme.dart` 增加 `scaffoldBackgroundColor = AppPalette.lightBackground`(浅色)与
`dividerTheme`(颜色 + 内缩),让全局也吃到灰底白卡的层次。

### 3.3 设置页重做(对照 §1.5)

| 问题 | 改法 |
|---|---|
| 图标混搭 | 全部走 `AppIcons.*`、统一 20px、统一色(常态 `onSurfaceVariant`,强调项用主题红);**去掉粉底方块/红底圆**这类底衬 |
| 行高不一 | 所有设置行固定 `AppSize.rowHeight`(56),图标-文本-控件三段对齐 |
| 开关过大 | 开关统一 `MaterialTapTargetSize.shrinkWrap` + 缩放,不再满高 |
| 分段控件突兀 | 「浅色/深色」改为紧凑 segmented(高 32、圆角 10、内边距 12) |
| 层次弱 | 页面灰底 + 白卡(圆角 14)+ 分区标题 13px/600/灰 + 卡片间距 24 + 分割线内缩 16 |
| 底部遮挡 | 设置页列表底部加 `AppSpacing.xl + 迷你播放条高度` 的安全内边距 |
| 计数口径 | 顶部「N 个音源」改为只算**用户自己装的**(与「已安装音源」行同一口径);为 0 时不显示数字 |

### 3.4 测试与验收

- **安全网**(现有):`test/ui/layout_audit_test.dart`(8 种宽度)、`ui_redesign_test.dart`、
  `settings_layout_test.dart`、`source_visibility_test.dart`、`ui_simplify_test.dart`。
  仍断言具体 `IconData` 的用例同步改成 `AppIcons.*`。
- **新增**:§4.1 的图标层契约测试 + §3.1 的语义覆盖测试。
- **验收**:模拟器装包 → 截图「设置 / 发现 / 播放」→ 用户确认。

---

## 4. 风险与对策

| 风险 | 对策 |
|---|---|
| Tabler 缺某个语义(71 个里可能有 1~3 个) | 编译期就暴露;用同语义图标替代(如「歌词」用 `microphone_2`、「电台」用 `radio`),必要时保留一个 Material 兜底常量并在语义层注释原因 |
| Tabler 常量名与推测不符 | 同上,`flutter analyze` 是唯一裁判;任务里先写映射再 analyze |
| 图标字体增大包体 | Flutter 对 `IconData` 常量做 tree-shaking(`--tree-shake-icons`);CI 构建日志里核对包体变化 |
| 视觉改动咬到 UI 测试 | 换字形后先跑全套,逐个更新断言(文案/结构断言优先于图标断言) |
| 一次性 159 处替换回归难定位 | 分 5 个提交按文件群推进(主框架+设置页 / 发现+库+下载 / 播放+歌词+更新行),每步 analyze+测试 |
| 用户对最终观感不满意 | 模拟器截图迭代,满意才发版;第二版范围可再谈 |

---

## 5. 交付节奏

- **第一版(本次)**:依赖接入 → `AppIcons` 语义层 + 契约测试 → token → 全局 159 处替换 →
  设置页重做 → 模拟器截图验收 → 发版。
- **第二版(后续)**:发现页/播放页/我的/下载页按 token 细修(卡片、留白、控件尺度)。

---

## 6. 待用户确认后的下一步

1. 本设计文档提交;
2. 写实施计划 `docs/superpowers/plans/2026-10-09-ui-icon-system.md`;
3. 按计划分任务实施,每任务 analyze + 测试 + 提交;
4. 模拟器截图验收 → 发版。
