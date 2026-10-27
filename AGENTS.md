# 番茄小记项目约定

## 项目级 skill

- 执行本仓库的开发、修复、维护和发布准备时，使用项目级 [`tomato-notes-workflow`](.agents/skills/tomato-notes-workflow/SKILL.md)（`$tomato-notes-workflow`）串联现有规范、验证与 PR 交付流程。
- 本文件和平台目录的 `AGENTS.md` 仍是基础约束；skill 按任务读取现有维护文档。纯阅读或答疑不因此启动分支、提交、issue 或发布操作。

## 分支与交付

- `main` 是稳定发布分支，`develop` 是日常集成分支；仓库默认分支保持 `main`。
- 功能与修复从最新 `origin/develop` 建立短分支，使用 `<类型>/<平台>-<简短英文描述>`；平台为 `macos`、`windows` 或 `shared`，例如 `feat/macos-history-search`、`fix/windows-tray-menu`、`refactor/shared-directory-layout`，不加个人名前缀。历史分支不强制改名，发布分支仍为 `release/vX.Y.Z`。
- 类型为 `feat`、`fix`、`docs`、`chore`、`refactor`、`test`、`ci`、`release` 或 `hotfix`。
- 普通 PR 进入 `develop`；发布 PR 为 `develop` → `main`；发布后的同步 PR 可为 `main` → `develop`。
- 不直接推送 main / develop，不改写已发布标签，不绕过检查；提交信息使用中文。
- 合并需要用户明确授权；同一会话已经给出的授权不重复询问，未经授权不自动合并。
- 先检查工作区，不丢弃或覆盖他人未提交内容。旧分支保留，不在其他任务中顺手删除。
- 详细操作见 CONTRIBUTING.md；新克隆执行 Scripts/setup-dev.sh，快速开分支用 Scripts/start-work.sh。

## 双端目录与 AI 协作

- `apps/macos/` 是 macOS 工程，`apps/windows/` 是 Windows 工程；平台源码、测试、打包资源和实现脚本留在各自目录。根目录维护 `Compatibility/`、`VERSION`、仓库协作脚本、CI 和公共文档。
- macOS 维护者为 @huangzx8090，Windows 共同维护者为 @blakceyes（khalil）和 @yhy854，路径责任见 `.github/CODEOWNERS`；Windows 跟进 issue 默认在同一个事项上同时指派这两人，不轮流分配或只选一人，保留其他已有 assignee。
- 指派前用 `gh api repos/huangzx8090/tomato-notes/assignees/<用户名>` 核验目标成员可被指派。邀请未接受或暂不可指派时，先创建 / 补充 issue 并指派可用成员，交付时明确报告未成功指派的成员与原因；恢复可用后，对该事项补齐缺少的 assignee，并用 `gh issue view --json assignees` 核对结果。不能把正文 @ 提及当作成功委派。
- 一端的正常维护只修改该端；数据契约、版本、CI 和发布流程需要双方评审。目录职责与完整流程见 `docs/双端协作维护.md`。
- AI 每次交付功能、修复或改进前，必须检查另一端是否存在对应能力或同类问题：新增另一端缺少且适用的功能、修复共同逻辑缺陷、提供可复用的体验或维护改进时，自动为另一端创建跟进 issue；规则双向适用。
- 仅影响某一平台 API、系统权限、托盘、签名或安装器等特有实现，且另一端无同类问题时，不创建跨端 issue。纯目录整理、内部等价重构、文档修改或另一端已实现的行为也不重复提 issue。
- issue 操作优先使用 `gh`：先搜索已有 open / closed issue 并阅读相关内容；有对应事项则补充，避免重复创建。正文通过临时文件和 `--body-file` 提交，附目标端、来源 PR / commit、适用依据、预期行为与验收条件；来源未合并时明确标记。
- 创建本仓库跨端跟进 issue 属于上述协作流程，满足条件时直接执行；跟进 issue 不授权自动修改另一端或自动合并。`gh` 不可用时可使用已连接的 GitHub 工具；仍失败时保留标题和正文并报告原因，不声称已通知。
- PR 和最终交付必须记录跨端判断：已创建 / 已补充的 issue 链接，或无需提 issue 的具体原因。禁止用源端 PR 的 `Closes` / `Fixes` 提前关闭目标端跟进事项。

## 文档与本地开发记录

- 仓库文档只保留需要长期维护的使用说明、开发约定、数据契约和发布记录。功能变化优先更新现有 README、使用指南和 CHANGELOG，不为每轮功能单独新增过程说明。
- 临时计划、实现过程、开发日志、一次性验收清单、评估和后续建议只放在已忽略的 `.local-dev/`；进度文件可用已忽略的 `PROJECT_PROGRESS.md`。这些文件不提交，不用 `git add -f` 绕过规则，也不另建受跟踪的归档目录保留。
- 实际执行的检查、结果、未验证范围和交付说明写入 PR 描述；需要长期保留的用法、隐私边界与限制归入正式指南。
- 暂存时明确列出本次文件；提交前查看 `git diff --cached --name-status` 与实际 diff，排除本地过程资料。`Scripts/setup-dev.sh` 启用提交检查，拦截暂存区中已被忽略的文件。

## 验证与资料

- 执行与变更风险相称的验证。Scripts/test.sh 为规则与模拟接口测试；构建和发布使用现有脚本。
- 界面、系统通知、Chrome 授权 / 截图 / 关闭的真实验证与规则测试分开报告。
- 不用个人待办、便签或重要浏览标签做破坏性测试。用户要求暂停实机测试时继续遵守。
- 日常使用和交付用户操作的预览共用固定本机资料库，普通启动并复用已有实例；不要把带独立 `--data-dir` 的测试实例当成日常入口。自动化或破坏性验证显式使用 `--ui-test` / 独立资料，交付时说明隔离状态。
- 不提交 Key、.build、build 或个人数据；日志不得输出密钥。
- 发版同时更新根目录 `VERSION`、`apps/macos/Packaging/Info.plist` 的版本与 build、Windows csproj 版本、CHANGELOG、docs/releases/<tag>.md。`Scripts/check-versions.py` 检查三者一致；版本标签只能指向 main 中的提交。

## 当前平台限制

截至 2026-10-22，GitHub 对此私有仓库的分支保护 / ruleset 请求返回 403，要求 Pro 或公开仓库。当前依靠约定、CI 和本地 hook，不能声称有服务端强制保护。未经用户授权，不更改可见性、不升级付费计划。
