# macOS 维护入口

- 开始工作前读取仓库根目录 `../../AGENTS.md` 和 `../../docs/双端协作维护.md`；本文件补充 macOS 范围。
- 本端负责 Swift / SwiftUI 应用、TomatoCore、TomatoSystem、测试与打包。分支示例：`feat/macos-history-search`、`fix/macos-timer-display`。
- 从仓库根目录运行 `apps/macos/Scripts/test.sh` 和 `apps/macos/Scripts/build-app.sh`；直接 SwiftPM 命令加 `--package-path apps/macos`。构建产物仍在根目录 `build/`。
- 交付前检查 Windows 是否需要跟进，按根规范优先使用 `gh` 查重并创建 / 补充 issue；纯 macOS 特有问题写明原因后跳过。
