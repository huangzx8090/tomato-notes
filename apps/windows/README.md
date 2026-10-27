# 番茄小记 Windows 客户端

这是同一仓库内的原生 **WPF / .NET 8** 客户端，不是把 SwiftUI 直接条件编译到 Windows。
macOS 工程位于 `apps/macos/`，由 macOS 维护者负责；`apps/windows/` 由 Windows 维护者负责。目录职责与协作规则见 [双端协作维护](../../docs/双端协作维护.md)。Windows 代码按核心与系统界面拆分：

- `TomatoNotes.Core/`：跨平台资料模型、macOS 日期编码兼容、计时、统计、备份与 AI 协议。
- `TomatoNotes/`：WPF 界面、Win32 前台进程/全局快捷键、系统托盘、DPAPI 密钥、图片导入。
- `TomatoNotes.Tests/`：无外部依赖的规则和模拟 HTTP 测试。
- `Packaging/TomatoNotes.iss`：Inno Setup 安装/卸载配置。

## 功能与边界

保留番茄钟、暂停恢复、待办与撤销、历史统计、独立浮动便签、TXT 导出、前台应用投入、
本地备份、AI 模型查询和文字/图片回顾、自动回顾。托盘气泡代替 macOS 通知，
Ctrl+Alt 快捷键代替 Control+Option，DPAPI 当前用户加密代替 Keychain。
另支持本地历史搜索、专注热力图、未完成待办手动结转与撤销安排，
以及待办删除后的本次运行内撤销。所有历史数据仍只写入既有 v4 JSON 字段。

Liquid Glass、macOS 合盖检测、AppleScript Chrome 页面读取/截图/自动关闭不移植。
Windows 版不展示不可用的守护设置。不会假装支持这些系统接口。

## 资料兼容

默认位置为 `%APPDATA%\TomatoNotes`，支持 macOS v1–v4 资料格式（Apple 2001 基准秒数日期），
写入采用相同的 v4 JSON 字段。未知字段和 macOS 专属字段通过扩展数据原样保留。
这表示可通过备份迁移资料，**不表示两台电脑会自动同步**。不要通过网络共享目录让两端同时写入。

Keychain 密钥不会也不应迁移到 Windows，需在 Windows 设置中重新填写。
`--ui-test` 和 `--data-dir <目录>` 用于隔离测试资料，不用日常资料做破坏性验证。

## 构建与测试

在 Windows 10/11 x64 + .NET 8 SDK 上，从仓库根目录执行：

```powershell
dotnet run --project apps/windows/TomatoNotes.Tests/TomatoNotes.Tests.csproj
dotnet run --project apps/windows/TomatoNotes/TomatoNotes.csproj -- --ui-test
powershell -ExecutionPolicy Bypass -File apps/windows/Scripts/package-windows.ps1
```

打包需要 Inno Setup 6。输出为
`build/releases/v<版本>/TomatoNotes-v<版本>-Windows-x64-setup.exe`。
应用自包含 .NET 8 运行时，安装机器无需另装运行时。未配置 Authenticode 签名，
首次运行可能有 SmartScreen 提示，应核对 Release 的 SHA-256。

macOS / Linux 可用 .NET 8 SDK 验证核心，并用以下参数交叉编译 WPF：

```bash
dotnet build apps/windows/TomatoNotes/TomatoNotes.csproj -p:EnableWindowsTargeting=true
dotnet publish apps/windows/TomatoNotes/TomatoNotes.csproj -c Release -r win-x64 \
  --self-contained true -p:EnableWindowsTargeting=true -o build/windows/publish
```

跨平台编译和安装器内容校验不等于 Windows 实机验收。托盘、通知、快捷键、
安装/卸载、权限与真实 AI 请求需在 Windows 上单独验证。

## 协作与版本

Windows 共同维护者为 @blakceyes（khalil）和 @yhy854；后续 Windows 跟进 issue 默认在同一事项上同时委派两人，实际指派需成员已接受邀请并可被指派。

产品版本来自根目录 `VERSION`，Windows 打包仅核对自身 csproj 与该版本，不读取 macOS 配置；公共 CI 校验两端一致。根目录 `Scripts/package-windows.ps1` 保留为兼容入口。

分支示例：`feat/windows-history-search`、`fix/windows-tray-menu`。AI 交付前需检查 macOS 是否应跟进，优先使用 `gh` 查重并创建 / 补充适用的 issue；纯 Windows 特有问题记录跳过原因，完整规则见[双端协作维护](../../docs/双端协作维护.md)。
