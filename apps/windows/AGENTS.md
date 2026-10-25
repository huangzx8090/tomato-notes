# Windows 维护入口

- 开始工作前读取仓库根目录 `../../AGENTS.md` 和 `../../docs/双端协作维护.md`；本文件补充 Windows 范围。
- 本端负责 C# / WPF 应用、TomatoNotes.Core、测试与安装器。分支示例：`feat/windows-history-search`、`fix/windows-tray-menu`。
- 从仓库根目录运行 `dotnet run --project apps/windows/TomatoNotes.Tests/TomatoNotes.Tests.csproj` 和 `powershell -ExecutionPolicy Bypass -File apps/windows/Scripts/package-windows.ps1`。构建产物仍在根目录 `build/`。
- 交付前检查 macOS 是否需要跟进，按根规范优先使用 `gh` 查重并创建 / 补充 issue；纯 Windows 特有问题写明原因后跳过。
