#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tag="${1:?用法：Scripts/validate-release.sh vX.Y.Z}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || "$tag" != "v$version" ]]; then
    printf '标签与应用版本不符；期望 v%s。\n' "$version" >&2
    exit 1
fi
tag_commit="$(git rev-parse --verify "refs/tags/$tag^{commit}")"
if [[ "$tag_commit" != "$(git rev-parse HEAD)" ]]; then
    printf '当前提交不是指定标签对应的提交。\n' >&2
    exit 1
fi
git merge-base --is-ancestor "$tag_commit" origin/main
test -s "docs/releases/$tag.md"
printf '发布检查通过：%s，提交 %s\n' "$tag" "$tag_commit"
