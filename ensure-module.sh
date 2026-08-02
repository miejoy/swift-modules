#!/bin/bash
# ensure-module.sh — 确保指定模块源码可用，不存在则从 GitHub 克隆
#
# 用法:
#   ./ensure-module.sh <module-name> [module-name ...]
#   ./ensure-module.sh data-flow view-flow ability
#
# 环境变量:
#   MIEJOY_MODULES_ROOT_PATH  模块根目录（未定义则用 skill 目录下 modules/）
#
# 行为:
#   1. 确定 MODULES_ROOT：$MIEJOY_MODULES_ROOT_PATH 或 <skill_dir>/modules
#   2. 对每个传入的模块名：
#      - 若 $MODULES_ROOT/<module-name> 已存在且非空 → 跳过
#      - 否则 → git clone git@github.com:miejoy/<module-name>.git

set -euo pipefail

# --- 确定 skill 目录（脚本所在目录） ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 确定模块根目录 ---
if [[ -n "${MIEJOY_MODULES_ROOT_PATH:-}" ]]; then
    MODULES_ROOT="$MIEJOY_MODULES_ROOT_PATH"
else
    MODULES_ROOT="$SCRIPT_DIR/modules"
fi

# --- 确保根目录存在 ---
mkdir -p "$MODULES_ROOT"

# --- 校验参数 ---
if [[ $# -eq 0 ]]; then
    echo "用法: $0 <module-name> [module-name ...]"
    echo "示例: $0 data-flow view-flow ability"
    echo ""
    echo "环境变量 MIEJOY_MODULES_ROOT_PATH 当前值: ${MODULES_ROOT}"
    exit 1
fi

# --- GitHub 组织 ---
ORG="miejoy"

# --- 逐个处理模块 ---
cloned=0
skipped=0
failed=0

for module in "$@"; do
    target="$MODULES_ROOT/$module"

    if [[ -d "$target" ]] && [[ -n "$(ls -A "$target" 2>/dev/null)" ]]; then
        echo "[跳过] $module — 已存在于 $target"
        skipped=$((skipped + 1))
        continue
    fi

    url="git@github.com:$ORG/$module.git"
    echo "[克隆] $module ← $url"

    if git clone --depth 1 "$url" "$target" 2>&1; then
        echo "[完成] $module → $target"
        cloned=$((cloned + 1))
    else
        echo "[失败] $module — 克隆失败，请检查网络或仓库地址: $url"
        # HTTPS 兜底
        https_url="https://github.com/$ORG/$module.git"
        echo "[重试] 尝试 HTTPS: $https_url"
        if git clone --depth 1 "$https_url" "$target" 2>&1; then
            echo "[完成] $module → $target (HTTPS)"
            cloned=$((cloned + 1))
        else
            echo "[失败] $module — HTTPS 克隆也失败"
            failed=$((failed + 1))
        fi
    fi
done

echo ""
echo "汇总: 克隆 $cloned, 跳过 $skipped, 失败 $failed"
echo "模块根目录: $MODULES_ROOT"

[[ $failed -eq 0 ]] || exit 1
