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

### 只发吴玫静版

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

旧版本不包含 `app_flavor.dart`,仍使用 `/releases/latest`,会拿到全仓库
最新的 release。若下载到另一条线的包,安装会被系统拒绝(同包名、同
versionCode 但内容不同)。v1.7.47 起已加入签名与版本校验,失败时会给出
可读原因。

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
