#!/usr/bin/env bash
#
# 一条命令发布两个变体(或只发其中一个)。
#
# 用法:
#   scripts/release.sh              # 发布当前 pubspec 版本的两个变体(默认)
#   scripts/release.sh --blessing   # 只发吴玫静版
#   scripts/release.sh --standard   # 只发标准版
#   scripts/release.sh --dry-run    # 只打印将要执行的命令
#   scripts/release.sh --verify     # 核对两个变体的产物是否都已发布
#
# 为什么需要这个脚本:发布涉及两个 tag、且**顺序有讲究**(见下),
# 手工敲容易漏掉一条或搞反顺序。**不带参数时默认两个都发。**
set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
ONLY=""
VERIFY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1;;
    --blessing) ONLY=blessing;;
    --standard) ONLY=standard;;
    --verify) VERIFY=1;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "未知参数: $arg(用 --help 查看用法)" >&2; exit 2;;
  esac
done

# ---- 读取版本号 ----------------------------------------------------------
VERSION_LINE="$(grep '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//')"
VERSION="${VERSION_LINE%%+*}"
CODE="${VERSION_LINE##*+}"

if [ -z "$VERSION" ] || [ "$VERSION" = "$VERSION_LINE" ]; then
  echo "错误:pubspec.yaml 的 version 应形如 1.7.48+67,当前:$VERSION_LINE" >&2
  exit 1
fi
if ! echo "$CODE" | grep -qE '^[0-9]+$'; then
  echo "错误:versionCode 必须是数字,当前:$CODE" >&2
  exit 1
fi

BLESSING_TAG="v${VERSION}"
STANDARD_TAG="std-v${VERSION}"

echo "版本:  $VERSION (code $CODE)"
echo "吴玫静版 tag: $BLESSING_TAG"
echo "标准版 tag:   $STANDARD_TAG"
echo

# ---- --verify:核对两个变体的产物是否都真的发布了 --------------------------
#
# 用途:CI 跑完后确认「两个版本都发出去了」,避免只发成功一个却没人发现。
# 检查每个变体在当前平台上的关键产物(apk/dmg),HTTP 200 即视为就绪。
if [ "$VERIFY" = "1" ]; then
  REPO="$(git remote get-url origin \
    | sed -E 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?#\1#')"
  echo "核对仓库: $REPO"
  echo

  check() { # $1=tag $2=文件名
    local code
    code="$(curl -sI -L -o /dev/null -w '%{http_code}' --max-time 30 \
      "https://github.com/$REPO/releases/download/$1/$2" || echo 000)"
    if [ "$code" = "200" ]; then
      printf '  ✅ %-46s (%s)\n' "$2" "$1"
      return 0
    fi
    printf '  ❌ %-46s (%s) HTTP=%s\n' "$2" "$1" "$code"
    return 1
  }

  FAILED=0
  check "$BLESSING_TAG" "MusicX-${VERSION}.apk"      || FAILED=1
  check "$BLESSING_TAG" "MusicX-${VERSION}.dmg"      || FAILED=1
  check "$STANDARD_TAG" "MusicX-${VERSION}-standard.apk" || FAILED=1
  check "$STANDARD_TAG" "MusicX-${VERSION}-standard.dmg" || FAILED=1

  echo
  if [ "$FAILED" = "1" ]; then
    echo "有产物尚未就绪 —— 若刚推送,CI 可能仍在构建,稍等几分钟再跑一次"
    echo "scripts/release.sh --verify"
    exit 1
  fi
  echo "两个变体的产物均已就绪 ✅"
  exit 0
fi

# ---- 发布前检查 ----------------------------------------------------------
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "main" ]; then
  echo "警告:当前分支是 $BRANCH,通常应在 main 上发布。" >&2
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "错误:工作区有未提交的改动,请先提交再发布。" >&2
  git status --short >&2
  exit 1
fi

# 本地与远端是否同步(避免基于旧代码打 tag)
git fetch origin main --quiet 2>/dev/null || true
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse origin/main 2>/dev/null || echo '')"
if [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
  echo "错误:本地 main 与 origin/main 不一致,请先 push 或 pull。" >&2
  exit 1
fi

# tag 是否已存在
for t in "$BLESSING_TAG" "$STANDARD_TAG"; do
  if git rev-parse -q --verify "refs/tags/$t" >/dev/null; then
    echo "错误:tag $t 已存在(本地)。" >&2
    exit 1
  fi
done

# ---- 组装 tag 列表 --------------------------------------------------------
# 顺序很重要:先推标准版、再推吴玫静版。
#
# 原因:v1.7.46 及以前的旧客户端只读 /releases/latest,且用
# `tag.startsWith('v')` 取版本号。若标准版(std-v*)最后发布并占据最新位,
# 旧版会解析出 "std-vX.Y.Z",版本比较被判为 0 → 误报「已是最新」,
# 永远收不到更新。让吴玫静版占住最新位,旧版才有出路。
TAGS=()
case "$ONLY" in
  blessing) TAGS=("$BLESSING_TAG");;
  standard) TAGS=("$STANDARD_TAG");;
  *)        TAGS=("$STANDARD_TAG" "$BLESSING_TAG");;
esac

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

# ---- 执行 ----------------------------------------------------------------
for t in "${TAGS[@]}"; do
  case "$t" in
    std-*) NAME="标准版";;
    *)     NAME="吴玫静版";;
  esac
  echo "打 tag $t($NAME)…"
  run git tag -a "$t" -m "MusicX ${VERSION}(${NAME})"
done

echo
echo "推送 tag(顺序:${TAGS[*]})…"
for t in "${TAGS[@]}"; do
  case "$t" in
    std-*) NAME="标准版";;
    *)     NAME="吴玫静版";;
  esac
  echo "  → $t($NAME)"
  run git push origin "$t"
done

echo
if [ "$DRY_RUN" = "1" ]; then
  echo "dry-run 结束,未实际打 tag / 推送。"
  exit 0
fi

echo "已推送。CI 将并行构建对应变体,约 3-6 分钟。"
echo "查看进度: https://github.com/vpertj/musicx/actions"
echo
echo "构建完成后可核对:"
echo "  吴玫静版: https://github.com/vpertj/musicx/releases/tag/$BLESSING_TAG"
if [ "$ONLY" != "blessing" ]; then
  echo "  标准版:   https://github.com/vpertj/musicx/releases/tag/$STANDARD_TAG"
fi
