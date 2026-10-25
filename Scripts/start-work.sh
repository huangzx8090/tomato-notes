#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
branch="${1:?用法：Scripts/start-work.sh feat/macos-history-search}"
Scripts/check-branch-policy.sh develop "$branch"
if [[ -n "$(git status --porcelain)" ]]; then
    printf '工作区有未提交内容，请先妥善保存，再创建新工作分支。\n' >&2
    exit 1
fi
git fetch origin develop
git switch -c "$branch" origin/develop
