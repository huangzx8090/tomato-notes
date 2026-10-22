#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
configuration="${1:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_name="番茄小记"
bundle_id="com.zixuan.TomatoNotes"
if [[ "${2:-}" == "--qa" ]]; then
    app_name="番茄小记验证"
    bundle_id="com.zixuan.TomatoNotes.QA"
fi
if [[ "${2:-}" == "--guard-qa" ]]; then
    app_name="番茄小记守护验证"
    bundle_id="com.zixuan.TomatoNotes.GuardQA"
fi
app_path="$project_root/build/$app_name.app"
mkdir -p "$project_root/build"
staging="$(mktemp -d "$project_root/build/package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
staged_app="$staging/$app_name.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/TomatoNotes" "$staged_app/Contents/MacOS/TomatoNotes"
cp Packaging/Info.plist "$staged_app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$staged_app/Contents/Info.plist"
plutil -replace CFBundleName -string "$app_name" "$staged_app/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$app_name" "$staged_app/Contents/Info.plist"
swift Scripts/make-icon.swift "$project_root/build/AppIcon.iconset"
iconutil -c icns "$project_root/build/AppIcon.iconset" -o "$staged_app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
# 替换整个包，避免截断正在运行的可执行文件。
if [[ -d "$app_path" ]]; then mv "$app_path" "$staging/previous.app"; fi
mv "$staged_app" "$app_path"
printf '\n已构建：%s\n' "$app_path"
