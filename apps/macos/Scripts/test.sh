#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc_dir="$(dirname "$(xcrun --find swiftc)")"
testing_plugin="$swiftc_dir/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$testing_plugin" ]]; then
    # 部分 Command Line Tools 的 Swift Build 未自动发现测试宏。
    swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$testing_plugin"
else
    swift test --disable-xctest
fi
