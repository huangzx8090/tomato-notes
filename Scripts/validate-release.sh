#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tag="${1:?用法：Scripts/validate-release.sh vX.Y.Z}"
version="$(python3 -c 'import xml.etree.ElementTree as E; d=E.parse("Packaging/Info.plist").getroot().find("dict"); children=list(d); print(next(children[i+1].text for i,x in enumerate(children) if x.tag == "key" and x.text == "CFBundleShortVersionString"))')"
windows_version="$(python3 -c 'import xml.etree.ElementTree as E; print(E.parse("Windows/TomatoNotes/TomatoNotes.csproj").getroot().find("PropertyGroup/VersionPrefix").text)')"
if [[ "$windows_version" != "$version" ]]; then
    printf 'Windows 项目版本 %s 与 Info.plist 版本 %s 不一致。\n' "$windows_version" "$version" >&2
    exit 1
fi
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || "$tag" != "v$version" ]]; then
    printf '标签与应用版本不符；期望 v%s。\n' "$version" >&2
    exit 1
fi
if [[ "$(git cat-file -t "refs/tags/$tag")" != tag ]]; then
    printf '发布必须使用 git tag -a 创建的注释标签。\n' >&2
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
