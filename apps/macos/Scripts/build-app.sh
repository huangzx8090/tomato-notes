#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
repository_root="$(cd "$project_root/../.." && pwd)"
cd "$project_root"
configuration="${1:-release}"
app_name="番茄小记"
bundle_id="com.zixuan.TomatoNotes"
universal=false
for option in "${@:2}"; do
    case "$option" in
        --qa) app_name="番茄小记验证"; bundle_id="com.zixuan.TomatoNotes.QA" ;;
        --guard-qa) app_name="番茄小记守护验证"; bundle_id="com.zixuan.TomatoNotes.GuardQA" ;;
        --universal) universal=true ;;
        *) printf '未知打包选项：%s\n' "$option" >&2; exit 1 ;;
    esac
done
if [[ "$configuration" != release && "$configuration" != debug ]]; then
    printf '构建配置必须为 release 或 debug。\n' >&2
    exit 1
fi
app_path="$repository_root/build/$app_name.app"
mkdir -p "$repository_root/build"
staging="$(mktemp -d "$repository_root/build/package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
staged_app="$staging/$app_name.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
if [[ "$universal" == true ]]; then
    # 两种架构都固定最低 macOS 版本，再合并；不依赖构建机的 CPU 类型。
    binaries=()
    for architecture in arm64 x86_64; do
        triple="$architecture-apple-macosx14.0"
        swift build -c "$configuration" --product TomatoNotes --triple "$triple"
        binary_dir="$(swift build -c "$configuration" --triple "$triple" --show-bin-path)"
        # 部分 SwiftPM 工具链复用 Products/Release 路径，下一次构建前先留存当前架构。
        cp "$binary_dir/TomatoNotes" "$staging/TomatoNotes-$architecture"
        lipo "$staging/TomatoNotes-$architecture" -verify_arch "$architecture"
        binaries+=("$staging/TomatoNotes-$architecture")
    done
    lipo -create "${binaries[@]}" -output "$staged_app/Contents/MacOS/TomatoNotes"
    for architecture in arm64 x86_64; do
        lipo "$staged_app/Contents/MacOS/TomatoNotes" -verify_arch "$architecture"
    done
else
    swift build -c "$configuration" --product TomatoNotes
    binary_dir="$(swift build -c "$configuration" --show-bin-path)"
    cp "$binary_dir/TomatoNotes" "$staged_app/Contents/MacOS/TomatoNotes"
fi
cp Packaging/Info.plist "$staged_app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$staged_app/Contents/Info.plist"
plutil -replace CFBundleName -string "$app_name" "$staged_app/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$app_name" "$staged_app/Contents/Info.plist"
swift Scripts/make-icon.swift "$repository_root/build/AppIcon.iconset"
iconutil -c icns "$repository_root/build/AppIcon.iconset" -o "$staged_app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
# 替换整个包，避免截断正在运行的可执行文件。
if [[ -d "$app_path" ]]; then mv "$app_path" "$staging/previous.app"; fi
mv "$staged_app" "$app_path"
printf '\n已构建：%s\n' "$app_path"
