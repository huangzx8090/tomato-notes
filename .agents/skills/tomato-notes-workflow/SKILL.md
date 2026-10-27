---
name: tomato-notes-workflow
description: 在番茄小记（tomato-notes）仓库开发功能、修复问题、维护代码或文档、验证改动、进行跨端跟进及准备发布时使用，按项目约定完成分支到 PR 的交付。仅适用于本项目；纯阅读或答疑不启动开发交付、issue 或发布操作。
---

# 番茄小记项目协作

将当前任务落实为范围明确、验证可核对的改动，按仓库约定交付 PR。默认用中文沟通和提交；解释已有代码时先说明用途、调用或数据流及组件关系，再结合实现说明。

## 先确定任务与规范

- 以当前用户指令和适用的 `AGENTS.md` 为准；本 skill 串联现有规则，不授予额外操作权限。用户限定只读、暂不提交或暂停实机测试时遵守该边界，继续可独立完成的工作。
- 确认仓库根目录、当前分支、工作区、`origin` 和实际 PR 状态；不要从历史记录推断当前版本、部署、权限或 CI 结果。涉及分支保护、可见性和成员可指派状态的结论先核验，旧文档中的日期记录不能当作当前事实。
- 确认已阅读根 [AGENTS.md](../../../AGENTS.md) 和 [CONTRIBUTING.md](../../../CONTRIBUTING.md)，再按下面的任务类型补充资料。下列命令均从仓库根目录执行。

| 任务范围 | 按需读取的维护入口 | 关键关系与边界 |
| --- | --- | --- |
| macOS | [macOS AGENTS.md](../../../apps/macos/AGENTS.md)、[macOS README](../../../apps/macos/README.md) | Swift / SwiftUI 工程、测试、系统接口与打包位于 `apps/macos/` |
| Windows | [Windows AGENTS.md](../../../apps/windows/AGENTS.md)、[Windows README](../../../apps/windows/README.md) | C# / WPF 应用、核心规则、测试与安装器位于 `apps/windows/` |
| 平台维护与跨端判断 | [双端协作维护](../../../docs/双端协作维护.md)、[CODEOWNERS](../../../.github/CODEOWNERS) | 单端维护限定在本端；跨端跟进规则双向适用 |
| 数据保存或迁移 | [Compatibility README](../../../Compatibility/README.md)、[本地资料保存与统一](../../../docs/本地资料保存与统一.md) | 两端共享资料契约，各自实现存储；密钥不跨端迁移 |
| 界面、权限或 AI 行为 | [使用指南与权限](../../../docs/使用指南与权限.md) | 核对现有用法、隐私边界和实机验收条件 |
| CI、版本或发布 | [发布流程](../../../docs/发布流程.md)、[CI 工作流](../../../.github/workflows/ci.yml)、[发布工作流](../../../.github/workflows/release.yml) | 版本、打包与发布属于共享流程，需要双方评审 |

只读取与当前任务有关的资料；理解组件时再查 [项目结构与实现详解](../../../docs/项目结构与实现详解.md)。规范或脚本变化后同步本入口，避免复制一套完整手册长期维护。

## 开始与实现

1. 先检查 `git status --short --branch`。保留无关改动、个人资料和已有历史分支；工作区不干净时优先在独立 worktree 中开始，不为切分支重置、清理或覆盖内容。
2. 新克隆按 `Scripts/setup-dev.sh` 启用本地 hooks；已有其他 `core.hooksPath` 时保留它，按脚本提示整合。hooks 和 CI 的存在不代表服务端已强制保护分支。
3. 普通开发从最新 `origin/develop` 建立 `<类型>/<平台>-<简短英文描述>`，不加个人名前缀。平台为 `macos`、`windows`、`shared`；类型与发布分支例外见 CONTRIBUTING。已有本任务分支先核对归属与 PR 状态，不重复开分支或复用已合并分支。

   ```bash
   Scripts/start-work.sh feat/macos-history-search
   ```

   该脚本检查工作区、拉取 `origin/develop` 并创建分支；遇到他人未提交内容时，改在隔离的工作区继续。Windows 可在 Git Bash 使用，或按 CONTRIBUTING 手动创建。

4. 只改任务授权的平台和文件，默认保留现有功能与兼容性。需要扩大范围或改变兼容行为时，先说明具体影响并取得确认。数据契约、版本、CI 和发布流程的变更需要双方评审；跟进 issue 不能代替本次必需的数据兼容修复。
5. 修改资料格式时检查 `Compatibility/` 的当前契约和回归样例，保留未知字段，明确迁移与备份策略；不假定两端自动同步。Keychain / DPAPI 中的密钥不随资料跨端迁移，不将 Key、个人资料或敏感日志写入提交、PR 或 issue。
6. 用户可见变化优先更新已有 README、使用指南或 CHANGELOG。临时计划、过程和一次性验收记录只放在被忽略的 `.local-dev/` 或 `PROJECT_PROGRESS.md`，保留已有进度内容，不新增受跟踪的过程归档。

## 按风险验证

| 变更 | 验证入口与报告要求 |
| --- | --- |
| 文档或 skill | 核对结构、相对链接、引用命令及 `git diff --check`；skill 还应验证元数据、发现路径和实际适用边界 |
| macOS 业务或界面代码 | `apps/macos/Scripts/test.sh`；涉及应用编译时运行 `apps/macos/Scripts/build-app.sh`，直接 SwiftPM 命令带 `--package-path apps/macos` |
| Windows 核心规则 | `dotnet run --project apps/windows/TomatoNotes.Tests/TomatoNotes.Tests.csproj`；WPF、安装器与系统行为按 Windows 维护入口在对应环境或 CI 验证 |
| 共享资料或版本 | 运行受影响两端的兼容回归及 `python3 Scripts/check-versions.py`，核对 schema、未知字段、迁移与版本一致性 |
| 打包或工作流 | 按当前脚本与 CI 判断所需检查；打包输入变更需要相应安装包验证，不为普通改动擅自发版 |

规则、模拟接口测试、编译与 CI 分开记录。界面、通知、Chrome 授权 / 截图 / 关闭、系统权限和快捷键等，只有实际操作后才能报告实机通过；未验证或当前环境无法验证时明确说明。

日常启动和交付用户操作的预览共用固定本机资料库，并复用已有实例。自动化或破坏性验证显式使用 `--ui-test` / 独立资料，交付时说明隔离情况；不要把带独立 `--data-dir` 的测试实例当作日常入口，不用个人待办、便签或重要浏览标签做破坏性测试。

## 跨端判断与跟进

交付功能、修复或改进前，按双端协作维护文档检查目标端当前实现和相关事项，记录适用依据。纯文档、目录整理、内部等价重构或仅平台特有且无同类问题的改动，可写明具体原因后跳过 issue；另一端已实现时不重复提出需求。

需要跟进时：

1. 优先用 `gh issue list --repo huangzx8090/tomato-notes --state all --search ...` 搜索 open / closed issue，再用 `gh issue view` 阅读候选内容。有对应事项则补充新依据，不重复创建或重复评论；未证实的问题标记“待确认”。
2. 先让来源实现可评审并创建来源 PR，再创建 / 补充跟进事项。正文用临时文件和 `--body-file`，列出目标端、来源 PR / commit 与合入状态、适用依据、预期行为、兼容要求和可操作的验收条件。来源未合并时标明“来源 PR 待合入”。
3. 按当前维护规范核验可指派状态：macOS 指派 `huangzx8090`；Windows 在同一事项同时指派 `blakceyes` 和 `yhy854`，用 `gh api repos/huangzx8090/tomato-notes/assignees/<用户名>` 分别检查，补齐缺少人员并保留已有 assignee。不可指派时先完成可用部分，报告缺少人员和原因，不以正文 @ 提及代替指派。用 `gh issue view --json assignees` 核对实际结果。
4. 满足本仓库跨端规则时直接执行已授权的 issue 操作；这不授权修改另一端或合并。`gh` 失败时可用已连接的 GitHub 工具，仍失败则保留标题和正文，说明未创建 / 未补充及原因，不声称已通知。
5. 将 issue 链接补到来源 PR 和最终交付。源端 PR 不用 `Closes` / `Fixes` 提前关闭目标端事项。

## 提交与 PR 交付

- 按 [PR 模板](../../../.github/pull_request_template.md) 整理变更目的、影响平台、跨端判断、实际验证、未验证范围及兼容风险。
- 显式 `git add` 本次文件；提交前查看 `git diff --cached --name-status` 和实际 diff，排除 Key、构建产物、个人数据和本地过程资料，不用 `git add -f` 或绕过 hooks 提交被忽略内容。
- 使用中文提交信息，推送同名工作分支，创建目标为 `develop` 的 PR。多行正文先写临时文件再传 `--body-file`，保留真实换行；以实际返回结果核对分支、提交和 PR。
- 跟踪本次 CI，区分成功、失败与仍运行；在任务范围内修复失败。不得把本地检查当成 CI 结果，或把 CI 成功当作合并许可。
- 不直接推送 `main` / `develop`。合并需要用户明确授权；同一会话已有的有效授权不重复询问。推送分支、创建 PR 和完成检查本身均不授权合并。
- 最终说明实际改动及原因、验证结果与实机未验证范围、分支和 PR 链接、跨端 issue 链接或无需跟进的具体原因；遇到阻塞如实说明已完成部分。

## 仅在发布任务中执行

先阅读当前发布流程。发布准备使用 `release/vX.Y.Z`；同步根 `VERSION`、macOS Info.plist 的版本与递增 build、Windows csproj 的版本字段、CHANGELOG 和 `docs/releases/<tag>.md`，并核对文档示例与安装说明。

先 PR 到 `develop`，再走 `develop` → `main` 发布 PR；长期分支合并保留合并关系，不 squash / rebase。合并、推送标签和公开 Release 依当前任务的明确授权执行，不能因“准备发布”自行扩展；已有授权不重复索要。

标签必须是指向 `main` 中提交的注释标签，版本与两端配置一致，通过当前发布检查。附件逐项对照当前发布工作流校验的清单和服务器实际附件名，不沿用文档中的历史数量。两端构建和全部附件上传、校验成功后才能公开同一 Release；已发布标签和安装包不覆盖，需要内容修复时使用新版本。必要时通过 `main` → `develop` PR 回同步。
