# 双版本发布与升级说明

本文说明 MusicX 的两个发行版本如何构建、发布,以及客户端如何判断自己
该升级哪一个包。改动发布流程或排查「更新提示不对」时请先读本文。

---

## 1. 两个版本是什么

| 版本 | 界面差异 | 说明 |
|---|---|---|
| **吴玫静版** | 设置页底部有红色寄语卡片(含署名) | 主版本 |
| **标准版** | 无该卡片 | 面向不需要该卡片的用户 |

两者来自**同一套代码**,由构建参数区分,不使用 Android productFlavor
(不产生额外的 `applicationIdSuffix`)。

---

## 2. 核心机制:tag 前缀即升级线

| 版本 | tag 形式 | tag 前缀 | 升级线 |
|---|---|---|---|
| 吴玫静版 | `v1.7.47` | `v` | 只认 `v*` |
| 标准版 | `std-v1.7.47` | `std-v` | 只认 `std-v*` |

**为什么必须靠前缀隔离**:GitHub 的 `/releases/latest` 返回**全仓库最新**
的 release,不区分变体。若两个版本都用它,标准版用户会收到吴玫静版的更新
提示(反之亦然)——即「串版」,表现为用户莫名多出/丢失卡片,甚至被系统以
版本冲突拒绝安装。

因此客户端**不使用** `/releases/latest`,而是拉取 release 列表后按自己的
前缀筛选,再取版本号最大的一条。相关实现与测试:

- `lib/core/updater/app_flavor.dart` —— 变体定义与 tag 前缀解析
- `lib/core/updater/update_service.dart` —— `pickLatestForFlavor()`
- `test/core/updater/flavor_isolation_test.dart` —— 隔离契约(17 例)

### 为什么吴玫静版的前缀是 `v` 而不是 `wmj-v`

v1.7.46 及以前的所有版本都发布在 `v` 线上。若改成 `wmj-v`,这些老用户将
**永远查不到新版本**(它们只会匹配 `v*`)。保持 `v` 才能让它们平滑升级到
v1.7.47,从而获得正确的变体判断能力。

代价是 `v` 前缀较宽,因此解析时要求**前缀后必须是数字**,避免误收
`v-next` 之类的无关 tag。

---

## 3. 客户端如何判断自己该升哪个包

变体是**编译期常量**,已烘进 APK,不需要运行时判断或用户选择。

```
构建时                                  运行时
──────────────────────────────────────────────────────────
flutter build apk                    →  自己是 blessing,前缀 "v"
  --dart-define=FLAVOR=standard      →  自己是 standard,前缀 "std-v"
```

检查更新的流程:

```
① 读编译期常量 → 确定自己的前缀
② GET /repos/vpertj/musicx/releases?per_page=100   (列表,不是 latest)
③ 逐条筛选:tag 是否以本变体前缀开头、且前缀后为数字?
   draft / prerelease 一律跳过
④ 取版本号最大者 → 其 assets 中匹配当前平台后缀的包 → 下载
⑤ 下载后校验:包名 + 签名 + versionCode 严格大于已装 + SHA256
```

前缀匹配是互斥的:`std-v1.7.47` 以 `s` 开头,吴玫静版的 `v` 前缀
(`startsWith('v')`)不会命中它,所以不会串版。

### 平台后缀

| 平台 | 匹配的资产后缀 |
|---|---|
| Android | `.apk` |
| macOS | `.dmg` |
| Windows | `.exe` |

---

## 4. 发布流程

### 推荐:用发布脚本

```bash
scripts/release.sh              # 一次发两个变体(默认;自动保证顺序)
scripts/release.sh --blessing   # 只发吴玫静版
scripts/release.sh --standard   # 只发标准版
scripts/release.sh --dry-run    # 只打印将执行的命令,不实际打 tag
scripts/release.sh --verify     # 核对两个变体的产物是否都已发布
```

**不带参数时默认两个都发。** CI 跑完后用 `--verify` 确认两个变体的
apk/dmg 都能下载(HTTP 200),避免「只成功发布了一个变体却没发现」。

脚本会读取 `pubspec.yaml` 的版本,自动生成两种 tag,并在发布前检查:

- 工作区是否干净(有未提交改动则拒绝)
- 本地 `main` 与 `origin/main` 是否一致(避免基于旧代码打 tag)
- tag 是否已存在(避免重复发布)
- `versionCode` 是否存在且为数字

两个都发时,**脚本会先推标准版、再推吴玫静版** —— 顺序原因见下。

### 手工发布

#### 只发吴玫静版

```bash
git tag -a v1.7.48 -m "..." && git push origin v1.7.48
```

### 只发标准版

```bash
git tag -a std-v1.7.48 -m "..." && git push origin std-v1.7.48
```

### 两个都发

```bash
git tag -a v1.7.48 -m "..." && git tag -a std-v1.7.48 -m "..."
git push origin v1.7.48 std-v1.7.48
```

**只发一条线时,另一条线的用户完全不受影响** —— 这正是「独立升级」的含义。

### ⚠️ 发版顺序:吴玫静版必须最后发

两个都发时,**先推 `std-v*`,再推 `v*`**。原因是 v1.7.46 及以前的旧客户端
只读 `/releases/latest`,且用 `tag.startsWith('v')` 取版本号:

| `/releases/latest` 指向 | 旧版解析结果 | 旧版行为 |
|---|---|---|
| `v1.7.47` | `1.7.47` | ✅ 正常提示更新 |
| `std-v1.7.47` | `std-v1.7.47` | ❌ 比较时非数字段当 0 → 误判「已是最新」 |

即:标准版若占了最新位,旧用户就再也收不到更新提示(表现为「检测不到新版本」)。
**让 `v*` 保持在最新位,旧版即可恢复在线升级能力。**

发布工作流会在发布吴玫静版时打印当前 `/releases/latest`,便于确认。

### 前置条件

发布前请确保 `pubspec.yaml` 的版本与 tag 一致:

```yaml
version: 1.7.48+67    # tag 用 v1.7.48 或 std-v1.7.48
```

`versionCode`(即 `+67`)必须**严格递增**,否则安卓会拒绝安装。
CI 会校验 tag 与 pubspec 是否一致,不一致直接拒绝发布。

---

## 5. 产物命名

| 平台 | 吴玫静版 | 标准版 |
|---|---|---|
| Android | `MusicX-<v>.apk` | `MusicX-<v>-standard.apk` |
| macOS | `MusicX-<v>.dmg` | `MusicX-<v>-standard.dmg` |
| Windows 安装器 | `MusicX-<v>-setup.exe` | `MusicX-<v>-setup-standard.exe` |
| Windows 便携版 | `MusicX-<v>-windows.zip` | `MusicX-<v>-windows-standard.zip` |

**每个 release 只包含一个变体的包** —— 吴玫静版在 `v*` 那个 release,
标准版在 `std-v*` 那个 release。因此在 GitHub 的 Releases 页面(默认只展开
最新一个 release)通常只看到一个 APK,这是预期行为。

### 为什么不把两个包放进同一个 release

看似方便(用户一次下载两个),但会破坏两处机制:

1. **tag 前缀分流会失效**。客户端只接受属于自己前缀的 release
   (`std-v*` 的客户端不会解析 `v1.7.49`),把一个 release 同时当作两个
   变体的来源,需要重做整套前缀机制。
2. **选包逻辑会串版**。当前实现取「第一个以 `.apk` 结尾的资产」,而
   `MusicX-1.7.49-standard.apk` 同样以 `.apk` 结尾,两者互相冲突;
   GitHub 不保证资产顺序,谁在前就选谁。

若将来确实要合并到同一 release,必须先改为**按变体精确匹配文件名**
(吴玫静版只认 `MusicX-<v>.apk`,标准版只认 `MusicX-<v>-standard.apk`),
并相应调整 tag 策略。

---

## 6. CI 实现要点

工作流:`.github/workflows/release.yml`,三个平台各一个 job。

### 触发条件必须显式列出两种 tag

```yaml
on:
  push:
    tags:
      - 'v*'
      - 'std-v*'   # 漏掉它标准版就不会触发发布(曾踩过)
```

### 变体判定(GitHub Actions, bash)

```bash
case "$TAG" in
  std-v*) FLAVOR=standard; VERSION="${TAG#std-v}";;
  v*)     FLAVOR=blessing; VERSION="${TAG#v}";;
  *) echo "::error::tag 必须以 v 或 std-v 开头"; exit 1;;
esac
```

### ⚠️ 一个容易踩的陷阱

`${TAG#v}` 与 PowerShell 的 `TrimStart('v')` **对 `std-v1.7.48` 都不生效**
(它不以 `v` 开头),会得到 `std-v1.7.48` 而不是 `1.7.48`,导致文件名错误。
必须先判断变体、再用对应的前缀剥离。三个平台都已按此处理。

### 注入变体

```bash
# 标准版
flutter build apk --release --dart-define=FLAVOR=standard
# 吴玫静版(默认,无需注入)
flutter build apk --release
```

**漏掉 `--dart-define` 会让标准版包带上吴玫静版的升级逻辑**,它会去追
`v*` 线,从而串版。

### 发布前的自检

CI 会核对构建产物的 `versionName` 是否等于 tag 版本,不等则拒绝发布。
这可以拦住「文件名是新版本、包内却是旧版本」这类最难排查的问题。

---

## 7. 已知限制

### 两个版本不能共存于同一台设备

两者使用同一个包名 `com.musicx.musicx`,互相覆盖。若需共存,标准版需要
改用独立包名(如 `com.musicx.standard`)并单独配置签名。

### v1.7.46 及以前的客户端不受前缀约束

旧版本不包含 `app_flavor.dart`,仍使用 `/releases/latest`,因此**它们能否
收到更新,取决于最新 release 是哪一条线**:

- 最新是 `v*`(吴玫静版)→ 正常提示更新,可在线升级;
- 最新是 `std-v*`(标准版)→ 解析出 `std-vX.Y.Z`,版本比较被判为 0,
  误报「已是最新版本」,用户收不到更新提示。

这也是「吴玫静版必须最后发」的原因(见第 4 节)。已实测确认:发一个更新的
`v*` 版本即可让这些旧客户端恢复在线升级,无需用户重装。

v1.7.47 起已按 tag 前缀正确分流,不再受发布顺序影响。

### 公共加速代理可用性不可控

国内下载依赖 `lib/core/updater/download_source.dart` 中的免费代理回退链。
代理可能限速或关停。无论走哪个源,下载后都会校验 SHA256,被篡改的包
会被拒绝。

---

## 8. 排查清单

用户反馈「更新提示不对 / 升不了级」时,按序检查:

1. **用户装的是哪个版本?** 设置页「检查更新」会显示版本号与 versionCode。
   两个版本号相同时,以卡片是否存在区分:有卡片=吴玫静版。
2. **应用看到的 latestVersion 是多少?** 点提示条上的「诊断」可查看
   `latestVersion` / `currentVersion` / `hasUpdate` / 资产直链 / 是否
   走了降级路径。
3. **tag 打对了吗?** `git tag | grep <版本>` 应只出现对应线的 tag。
4. **CI 产物名对吗?** 标准版的包名必须带 `-standard`。
5. **versionCode 是否递增?** 未递增时安卓必然拒绝安装。

诊断面板实现在 `lib/ui/plugins/update_diagnostics.dart`。
