# macOS 维护入口

本目录是独立 SwiftPM 工程：`TomatoNotes` 负责界面与应用协调，`TomatoCore` 负责业务规则与资料，`TomatoSystem` 负责系统和外部接口。适用根 [AGENTS.md](../../AGENTS.md)，协作流程由[项目 skill](../../.agents/skills/tomato-notes-workflow/SKILL.md)按任务定位。

## 构建与测试

从仓库根目录按改动选择：

```bash
apps/macos/Scripts/test.sh
swift build --package-path apps/macos --product TomatoNotes
apps/macos/Scripts/build-app.sh
```

规则测试不涉及真实系统权限；需要应用包时使用构建脚本。直接 SwiftPM 命令带 `--package-path apps/macos`。构建产物在根 `build/`，SwiftPM 缓存在本目录 `.build/`；根目录同名脚本保留兼容转发。安装包与版本操作见[发布流程](../../docs/发布流程.md)。
