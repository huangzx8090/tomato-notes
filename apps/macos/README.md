# 番茄小记 macOS 客户端

本目录是独立 SwiftPM 工程：`TomatoNotes` 负责界面与应用协调，`TomatoCore` 负责业务规则与资料，`TomatoSystem` 负责系统及外部接口。Windows 工程位于平级的 `../windows/`。

从仓库根目录执行：

```bash
apps/macos/Scripts/test.sh
apps/macos/Scripts/build-app.sh
swift build --package-path apps/macos --product TomatoNotes
```

构建输出在仓库根目录 `build/`，SwiftPM 缓存在本目录 `.build/`。根目录同名脚本继续转发到本目录。正式发布版本由根目录 `VERSION` 定义，发版时同步更新 `Packaging/Info.plist` 的版本与 build。

分支示例：`feat/macos-history-search`、`fix/macos-timer-display`。AI 交付前需检查 Windows 是否应跟进，优先使用 `gh` 查重并创建 / 补充适用的 issue；完整规范见[双端协作维护](../../docs/双端协作维护.md)。

日常启动共用本机资料库，自动化或破坏性验证显式使用 `--ui-test` / 独立资料。用户指南与源码构建说明见[项目 README](../../README.md)。
