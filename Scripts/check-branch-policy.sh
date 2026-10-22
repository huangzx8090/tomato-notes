#!/bin/bash
set -euo pipefail
base="${1:?请传入 PR 目标分支}"
head="${2:?请传入 PR 来源分支}"
case "$base" in
    main)
        if [[ "$head" != develop ]]; then
            printf 'main 只接收 develop 的发布 PR；功能与修复请先合入 develop。\n' >&2
            exit 1
        fi
        ;;
    develop)
        if [[ "$head" != main && ! "$head" =~ ^huangzx/(feat|fix|docs|chore|refactor|test|ci|release|hotfix)-[a-z0-9][a-z0-9.-]*$ ]]; then
            printf '开发分支应命名为 huangzx/<类型>-<简短英文描述>；仅允许 main 作为回同步来源。\n' >&2
            exit 1
        fi
        ;;
    *) printf 'PR 目标只能是 develop 或 main。\n' >&2; exit 1 ;;
esac
printf '分支约定通过：%s → %s\n' "$head" "$base"
