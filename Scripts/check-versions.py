#!/usr/bin/env python3
"""核对产品版本与两端构建配置；成功时输出统一版本号。"""

from pathlib import Path
import plistlib
import re
import sys
import xml.etree.ElementTree as ET


def main():
    root = Path(__file__).resolve().parent.parent
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("VERSION 必须为 X.Y.Z")
    with (root / "apps/macos/Packaging/Info.plist").open("rb") as source:
        macos = plistlib.load(source)
    windows = ET.parse(root / "apps/windows/TomatoNotes/TomatoNotes.csproj").getroot()
    expected = {
        "macOS CFBundleShortVersionString": (macos.get("CFBundleShortVersionString"), version),
        "Windows VersionPrefix": (windows.findtext("PropertyGroup/VersionPrefix"), version),
        "Windows AssemblyVersion": (windows.findtext("PropertyGroup/AssemblyVersion"), version + ".0"),
        "Windows FileVersion": (windows.findtext("PropertyGroup/FileVersion"), version + ".0"),
    }
    for name, (actual, wanted) in expected.items():
        if actual != wanted:
            raise ValueError(f"{name} 为 {actual!r}，应与 VERSION 对应：{wanted}")
    print(version)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, ET.ParseError, plistlib.InvalidFileException) as error:
        print(f"版本检查失败：{error}", file=sys.stderr)
        sys.exit(1)
