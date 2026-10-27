#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
existing="$(git config --local --get core.hooksPath || true)"
if [[ -n "$existing" && "$existing" != .githooks ]]; then
    printf '已有自定义 hooksPath：%s；请先手动整合，未覆盖原设置。\n' "$existing" >&2
    exit 1
fi
git config --local core.hooksPath .githooks
printf '已启用本仓库提交与推送检查：禁止提交被忽略的本地文件；main / develop 通过 PR 更新。\n'
