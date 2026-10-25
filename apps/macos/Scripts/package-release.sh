#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
repository_root="$(cd "$project_root/../.." && pwd)"
cd "$project_root"
version="$(cat "$repository_root/VERSION")"
macos_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
if [[ "$version" != "$macos_version" ]]; then
    printf 'macOS 版本 %s 与 VERSION %s 不一致。\n' "$macos_version" "$version" >&2
    exit 1
fi
tag="${1:-v$version}"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || "$tag" != "v$version" ]]; then
    printf '发布标签必须与 VERSION 一致：v%s\n' "$version" >&2
    exit 1
fi

Scripts/build-app.sh release --universal
app_path="$repository_root/build/番茄小记.app"
output="$repository_root/build/releases/$tag"
staging="$(mktemp -d "$repository_root/build/release.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$output" "$staging/dmg" "$staging/unpacked"
asset="TomatoNotes-$tag-macOS-universal"

plutil -lint "$app_path/Contents/Info.plist"
codesign --verify --deep --strict "$app_path"
for architecture in arm64 x86_64; do
    lipo "$app_path/Contents/MacOS/TomatoNotes" -verify_arch "$architecture"
done
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output/$asset.zip"
# 从实际 ZIP 解包校验签名与执行位，防止下载后失去运行权限。
ditto -x -k "$output/$asset.zip" "$staging/unpacked"
test -x "$staging/unpacked/番茄小记.app/Contents/MacOS/TomatoNotes"
codesign --verify --deep --strict "$staging/unpacked/番茄小记.app"
for architecture in arm64 x86_64; do
    lipo "$staging/unpacked/番茄小记.app/Contents/MacOS/TomatoNotes" -verify_arch "$architecture"
done

ditto "$app_path" "$staging/dmg/番茄小记.app"
ln -s /Applications "$staging/dmg/Applications"
cp Packaging/安装说明.txt "$staging/dmg/安装说明.txt"
hdiutil create -volname "番茄小记 $version" -srcfolder "$staging/dmg" \
    -format UDZO -ov "$output/$asset.dmg"
hdiutil verify "$output/$asset.dmg"
cp Packaging/安装说明.txt "$output/INSTALL.txt"
(
    cd "$output"
    shasum -a 256 "$asset.dmg" "$asset.zip" INSTALL.txt > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
printf '\n发布文件：%s\n' "$output"
