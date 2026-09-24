# 标准版发布与升级说明

本文说明 MusicX 单一发布线(标准版)如何构建、发布,以及客户端如何判断
更新。改动发布流程或排查「更新提示不对」时请先读本文。

> **历史说明**:仓库早期同时发布「吴玫静版」(tag `v*`)与「标准版」
> (tag `std-v*`)两条升级线,靠 tag 前缀隔离防止串版。现已合并为
> **标准版单一发布线**:只打 `std-v*` tag,CI 只构建一套产物。
> 已安装历史吴玫静版的客户端不会再收到自动更新(如需升级请手动到
> GitHub Releases 下载)。

---

## 1. 版本

当前只有一个发行版本:**标准版**。

| 项 | 值 |
|---|---|
| 安装包 | 无寄语卡片(该卡片随吴玫静版停发) |
| tag 形式 | `std-v1.7.47` |
| tag 前缀 | `std-v` |
| 升级线 | 只认 `std-v*` |

---

## 2. 核心机制:tag 前缀即升级线

客户端**不使用** `/releases/latest`(它返回全仓库最新 release,不区分
tag 前缀,会把历史 `v*` tag 当成更新),而是拉取 release 列表后按前缀
筛选,再取版本号最大的一条。相关实现与测试:

- `lib/core/updater/app_flavor.dart` —— 变体定义与 tag 前缀解析
- `lib/core/updater/update_service.dart` —— `pickLatestForFlavor()`
- `test/core/updater/flavor_isolation_test.dart` —— 隔离契约

仓库里仍存在历史 `v*` tag(吴玫静版时期发布的)。**标准版客户端对这些
tag 一律不认**:`std-v` 前缀匹配互斥于 `v`,不会串版。

### 平台后缀

| 平台 | 匹配的资产后缀 |
|---|---|
| Android | `.apk` |
| macOS | `.dmg` |
| Windows | `.exe` |

---

## 3. 客户端如何判断该升哪个包

变体是**编译期常量**,已烘进安装包,不需要运行时判断或用户选择。

构建时(CI)统一注入:

```
flutter build apk --release --dart-define=FLAVOR=standard
  → 自己是 standard,前缀 "std-v"
```

检查更新的流程:

```
① 读编译期常量 → 确定自己的前缀 "std-v"
② GET /repos/vpertj/musicx/releases?per_page=100   (列表,不是 latest)
③ 逐条筛选:tag 是否以 std-v 开头、且前缀后为数字?
   draft / prerelease 一律跳过
④ 取版本号最大者 → 其 assets 中匹配当前平台后缀的包 → 下载
⑤ 下载后校验:包名 + 签名 + versionCode 严格大于已装 + SHA256
```

前缀匹配互斥:`std-v1.7.47` 以 `s` 开头,历史 `v` 前缀不会命中它;
反过来 `v1.7.47` 也不以 `std-v` 开头,标准版不会误收。

### 历史构建(无 FLAVOR 定义)的处理

早期 CI 构建未注入 `--dart-define`,默认值为空。`parseFlavor` 对空值
与 `blessing` 一律归入**标准版**升级线,保证这些已装客户端仍能收到
`std-v*` 更新,而不是停在旧线上。

---

## 4. 发布流程

### 推荐:用发布脚本

```
scripts/release.sh              # 发布当前版本(只打 std-v* tag)
scripts/release.sh --dry-run    # 只打印将执行的命令,不实际打 tag
scripts/release.sh --verify     # 核对标准版产物是否都已发布
```

脚本会读取 `pubspec.yaml` 的版本,自动打 `std-v*` tag,并在发布前检查:

- 工作区是否干净(有未提交改动则拒绝)
- 本地 `main` 与 `origin/main` 是否一致(避免基于旧代码打 tag)
- tag 是否已存在(避免重复发布)
- `versionCode` 是否存在且为数字

### 手工发布

```
git tag -a std-v1.7.48 -m "MusicX 1.7.48(标准版)" \
  && git push origin std-v1.7.48
```

### 前置条件

发布前请确保 `pubspec.yaml` 的版本与 tag 一致:

```
version: 1.7.48+67    # tag 用 std-v1.7.48
```

`versionCode`(即 `+67`)必须**严格递增**,否则安卓会拒绝安装。
CI 会校验 tag 与 pubspec 是否一致,不一致直接拒绝发布。

---

## 5. 产物命名

| 平台 | 产物 |
|---|---|
| Android | `MusicX-<v>-standard.apk` |
| macOS | `MusicX-<v>-standard.dmg` |
| Windows 安装器 | `MusicX-<v>-setup-standard.exe` |
| Windows 便携版 | `MusicX-<v>-windows-standard.zip` |

每个 release(`std-v*` tag)包含当前版本的全平台产物。

---

## 6. CI 实现要点

工作流:`.github/workflows/release.yml`,三个平台各一个 job。

### 触发条件只接受 std-v* tag

```yaml
on:
  push:
    tags:
      - 'std-v*'
```

### 变体判定(三个平台统一)

只接受 `std-v*` tag,其他一律拒绝:

```
case "$TAG" in
  std-v*) VERSION="${TAG#std-v}";;
  *) echo "::error::tag 必须以 std-v 开头"; exit 1;;
esac
```

### 注入变体

```
# 安卓(APK 内烘入升级线)
flutter build apk --release --dart-define=FLAVOR=standard
```

桌面端(macOS/Windows)构建不带 FLAVOR 定义,`parseFlavor` 默认值为
standard,行为一致。

### 发布前的自检

CI 会核对构建产物的 `versionName` 是否等于 tag 版本,不等则拒绝发布。
这可以拦住「文件名是新版本、包内却是旧版本」这类最难排查的问题。

---

## 7. 已知限制

### 历史吴玫静版客户端不再收自动更新

已安装的吴玫静版(v* tag 时期)客户端的更新检查逻辑烘焙在旧包里,
仍只认 `v*` 升级线。该线已停发,因此**它们不会再收到自动更新**。
如需升级,请到 GitHub Releases 手动下载最新 `std-v*` 产物(需先卸载
旧版,包内寄语卡片为吴玫静版专属,卸载重装后消失)。

### v1.7.46 及以前的客户端不受前缀约束

旧版本不包含 `app_flavor.dart`,仍使用 `/releases/latest`,因此**它们
能否收到更新,取决于最新 release 是哪条线**:

- 最新是 `std-v*`(标准版)→ 解析出 `std-vX.Y.Z`,版本比较被判为 0,
  误报「已是最新版本」,用户收不到更新提示。

这是历史遗留问题,无解(旧包无法更新其自身逻辑),建议此类用户
手动重装。

### 两个历史变体不能共存于同一台设备

吴玫静版与标准版使用同一个包名 `com.musicx.musicx`,互相覆盖。
现吴玫静版已停发,此限制不再实际发生。

### 公共加速代理可用性不可控

国内下载依赖 `lib/core/updater/download_source.dart` 中的免费代理回退链。
代理可能限速或关停。无论走哪个源,下载后都会校验 SHA256,被篡改的包
会被拒绝。

---

## 8. 排查清单

用户反馈「更新提示不对 / 升不了级」时,按序检查:

1. **用户装的是哪个版本?** 设置页「检查更新」会显示版本号与 versionCode。
   若版本号停在旧线且包内有寄语卡片 → 历史吴玫静版,已停止自动更新。
2. **应用看到的 latestVersion 是多少?** 点提示条上的「诊断」可查看
   `latestVersion` / `currentVersion` / `hasUpdate` / 资产直链 / 是否
   走了降级路径。
3. **tag 打对了吗?** `git tag | grep <版本>` 应只出现 `std-v*` tag。
4. **CI 产物名对吗?** 标准版的包名必须带 `-standard`。
5. **versionCode 是否递增?** 未递增时安卓必然拒绝安装。

诊断面板实现在 `lib/ui/plugins/update_diagnostics.dart`。
