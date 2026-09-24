#!/usr/bin/env bash
#
# 一条命令发布当前版本(只发标准版)。
#
# 用法:
#   scripts/release.sh              # 发布当前 pubspec 版本(标准版)
#   scripts/release.sh --dry-run    # 只打印将要执行的命令
#   scripts/release.sh --verify     # 核对标准版产物是否已发布
#
# 历史说明:早期同时发布「吴玫静版」(v*)与「标准版」(std-v*)两条升级线,
# 需要维护两套 tag、顺序有讲究(旧客户端依赖 /releases/latest)。
# 现已合并为标准版单一发布线:只打 std-v* tag,CI 只构建一份包。
# 已安装旧吴玫静版的用户不会再收到自动更新(如需升级请手动下载)。
set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
VERIFY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1;;
    --verify) VERIFY=1;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
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

STANDARD_TAG="std-v${VERSION}"

echo "版本:  $VERSION (code $CODE)"
echo "标准版 tag: $STANDARD_TAG"
echo

# ---- --verify:核对标准版产物是否都真的发布了 --------------------------------
#
# 用途:CI 跑完后确认产物已就绪,避免发失败却没人发现。
# 检查标准版在当前平台上的关键产物(apk/dmg),HTTP 200 即视为就绪。
if [ "$VERIFY" = "1" ]; then
  ORIGIN="$(git remote get-url origin 2>/dev/null || echo '')"
  REPO="$(echo "$ORIGIN" \
    | sed -nE 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$#\1#p')"
  if [ -z "$REPO" ]; then
    # 本地 clone / 非 GitHub remote 时不能静默取错仓库去核对,
    # 否则会对着一个不存在的路径报 404,误导成"没发布"。
    echo "错误:origin 不是 GitHub 仓库地址(当前:$ORIGIN)" >&2
    echo "      --verify 需要能访问 github.com 的 remote。" >&2
    exit 2
  fi
  echo "核对仓库: $REPO"
  echo

  check() { # $1=tag $2=文件名
    # 注意:`curl -I -L` 每经过一次重定向都会输出一个 http_code
    # (GitHub 资产会 302 到 CDN),直接取用会得到 "302000" 这种拼接值。
    # 因此:
    #   - 用 -o /dev/null 丢弃正文,只保留最后一次的 code(取末尾 3 位);
    #   - 加 --retry 抵消偶发网络抖动(实测出现过瞬时 000)。
    local raw code
    raw="$(curl -sI -L --retry 3 --retry-delay 2 --retry-all-errors \
      -o /dev/null -w '%{http_code}' --max-time 40 \
      "https://github.com/$REPO/releases/download/$1/$2" 2>/dev/null || echo 000)"
    code="${raw: -3}"
    if [ "$code" = "200" ]; then
      printf '  ✅ %-46s (%s)\n' "$2" "$1"
      return 0
    fi
    printf '  ❌ %-46s (%s) HTTP=%s\n' "$2" "$1" "$code"
    return 1
  }

  FAILED=0
  check "$STANDARD_TAG" "MusicX-${VERSION}-standard.apk" || FAILED=1
  check "$STANDARD_TAG" "MusicX-${VERSION}-standard.dmg" || FAILED=1

  echo
  if [ "$FAILED" = "1" ]; then
    echo "有产物尚未就绪 —— 若刚推送,CI 可能仍在构建,稍等几分钟再跑一次"
    echo "scripts/release.sh --verify"
    exit 1
  fi
  echo "标准版产物均已就绪 ✅"
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
if git rev-parse -q --verify "refs/tags/$STANDARD_TAG" >/dev/null; then
  echo "错误:tag $STANDARD_TAG 已存在(本地)。" >&2
  exit 1
fi

# ---- 执行 ----------------------------------------------------------------
run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

echo "打 tag $STANDARD_TAG(标准版)…"
run git tag -a "$STANDARD_TAG" -m "MusicX ${VERSION}(标准版)"

echo
echo "推送 tag…"
echo "  → $STANDARD_TAG(标准版)"
run git push origin "$STANDARD_TAG"

echo
if [ "$DRY_RUN" = "1" ]; then
  echo "dry-run 结束,未实际打 tag / 推送。"
  exit 0
fi

echo "已推送。CI 将构建并上传产物,约 3-6 分钟。"
echo "查看进度: https://github.com/vpertj/musicx/actions"
echo
echo "构建完成后可核对:"
echo "  scripts/release.sh --verify"
echo "  页面: https://github.com/vpertj/musicx/releases/tag/$STANDARD_TAG"
