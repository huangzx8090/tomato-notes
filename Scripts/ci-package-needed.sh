#!/bin/bash
set -euo pipefail

event_name="${CI_EVENT_NAME:?缺少 CI_EVENT_NAME}"
base_sha="${CI_BASE_SHA:-}"
head_sha="${CI_HEAD_SHA:-HEAD}"

case "$event_name" in
    workflow_dispatch)
        case "${CI_PACKAGE:-false}" in
            true|false) printf '%s\n' "${CI_PACKAGE:-false}" ;;
            *) printf 'CI_PACKAGE 必须为 true 或 false。\n' >&2; exit 1 ;;
        esac
        exit 0
        ;;
    pull_request|push) ;;
    *) printf '不支持的 CI 事件：%s\n' "$event_name" >&2; exit 1 ;;
esac

# 新分支或缺失历史时，保守执行打包，不把无法比较当作没有变化。
if [[ -z "$base_sha" || "$base_sha" =~ ^0+$ ]] \
    || ! git cat-file -e "$base_sha^{commit}" 2>/dev/null \
    || ! git cat-file -e "$head_sha^{commit}" 2>/dev/null; then
    printf '无法可靠比较提交，执行完整安装包验证。\n' >&2
    printf 'true\n'
    exit 0
fi

comparison="$base_sha..$head_sha"
if [[ "$event_name" == pull_request ]]; then
    # PR 仅检查相对共同祖先的改动，避免把目标分支的新提交算入 PR。
    comparison="$base_sha...$head_sha"
fi

# 禁用重命名检测，移出这些目录的文件也会按删除触发验证。
if git diff --quiet --no-renames "$comparison" -- \
    .github/workflows/ Packaging/ Scripts/ Package.swift Package.resolved; then
    printf 'false\n'
else
    diff_status=$?
    if [[ "$diff_status" -ne 1 ]]; then
        printf '提交差异检查失败，执行完整安装包验证。\n' >&2
    fi
    printf 'true\n'
fi
