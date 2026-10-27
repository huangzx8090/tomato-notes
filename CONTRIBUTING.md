# 开发与分支约定

## 分支职责

```text
main ────────────── 稳定发布、版本标签
  │                       ↑ 发布 PR
  └── develop ────────────┘ 日常集成
        │          ↑ 功能 PR
        └── feat/macos-xxx
```

| 分支 | 用途 | 更新方式 |
| --- | --- | --- |
| `main` | 可发布的稳定代码，仓库默认分支 | 只接收 develop 的发布 PR |
| `develop` | 最新集成开发代码 | 接收功能分支 PR；必要时接收 main 的同步 PR |
| `<类型>/<平台>-<描述>` | 一项功能、修复或维护工作 | 从最新 origin/develop 创建，完成后 PR 到 develop |
| `vX.Y.Z` 标签 | 固定发布快照 | 在已合入 main 的版本提交创建注释标签，不移动、不覆盖 |

类型：`feat`、`fix`、`docs`、`chore`、`refactor`、`test`、`ci`、`release`、`hotfix`。类型后用 `/` 连接平台与描述，不加个人名前缀。平台为 `macos`、`windows` 或 `shared`，描述使用简短小写英文与连字符；发布分支的版本可含点，例如 `release/v1.3.3`。即使紧急修复也先进入 develop，再由 develop 发布到 main。

历史分支无需强制改名，现有检查保留命名兼容。已有历史分支保留，不作为新开发基线，也不为统一命名改写已合并记录。当前未执行历史分支删除。

## 开始工作

Codex 的项目级流程入口是 [`tomato-notes-workflow`](.agents/skills/tomato-notes-workflow/SKILL.md)，随仓库维护在 `.agents/skills/`。在本项目中可用 `$tomato-notes-workflow` 明确调用；它按任务读取现有规范，串联分支、双端跟进、验证与 PR 交付，基础约束仍以适用的 `AGENTS.md` 和当前维护文档为准。

首次克隆后：

```bash
Scripts/setup-dev.sh
```

这只修改本仓库的 `core.hooksPath`，启用 `.githooks/pre-commit` 和 `.githooks/pre-push`：提交时检查被忽略的本地文件，推送时拦截 main / develop；如果已经有其他 hook 设置，脚本会停止，不覆盖。每份新克隆都需单独执行。

开始一项功能：

```bash
Scripts/start-work.sh feat/macos-progress-timeline
```

脚本先检查命名与工作区，拉取最新 develop，再创建 `feat/macos-progress-timeline`。存在未提交内容或同名分支时停止，不丢弃任何内容。

也可手动执行：

```bash
git fetch origin develop
git switch -c fix/windows-timer-display origin/develop
```

## 完成开发

1. 只修改本次范围；不混入个人资料、Key、build、.build 或本地开发过程文档。明确暂存本次文件，并检查 `git diff --cached`。
2. 按[双端协作维护](docs/双端协作维护.md)检查另一端，优先使用 `gh` 查重并创建 / 补充适用的跨端 issue；平台特有问题记录跳过原因。执行与变更相称的检查，明确哪些是真实验证、哪些仅规则测试，哪些仍未验证。
3. 使用中文提交，推送同名工作分支，创建目标为 **develop** 的 PR。
4. CI 的 **分支约定**、**测试与编译** 均通过；修改打包输入时，额外通过 **双架构安装包验证**，再获得用户明确的合并授权。macOS 普通源码与公共文档变更会跳过安装包 job；`VERSION`、`apps/macos/Packaging/`、`apps/macos/Scripts/`、SwiftPM 配置、`apps/windows/`、根目录 `Scripts/` 或 `.github/workflows/` 变更会触发两端打包。
5. 合并后从最新 develop 开始下一项工作，不长期复用已经合并的功能分支。

```bash
git add <本次文件>
git commit -m '新增按时间线查看本轮进展'
git push -u origin feat/macos-progress-timeline
```

不直接推送 main / develop，不自动合并 PR；同一会话中用户已经给出的合并授权仍有效，不重复索要。合并 develop → main 时保留合并关系，不 squash 或 rebase 长期分支。

## 文档提交范围

- README、使用指南、开发维护约定、数据契约和版本记录随仓库维护。功能变化优先更新这些已有文档，不为每轮开发新增一份说明。
- 临时计划、开发记录、实现过程、一次性验收清单、评估及后续建议放在 `.local-dev/`；进度文件可用 `PROJECT_PROGRESS.md`。这些路径已被忽略，不提交，也不通过受跟踪的归档目录变相保留。
- 检查结果与交付记录写入 PR 描述；仍有效的操作、权限、隐私与限制归入正式指南。
- 提交 hook 检查 Git 暂存区内被忽略的文件，包括通过 `git add -f` 强行加入的内容。已有跟踪文件不会因 `.gitignore` 自动移除，应从跟踪中删除；不要绕过 hook 提交本地过程资料。

## 发布与回同步

- 在开发分支更新根目录 `VERSION`、两端版本与 macOS build、CHANGELOG、README 示例、离线安装说明与 `docs/releases/<tag>.md`，先 PR 到 develop。
- 再创建 **develop → main** 的发布 PR，检查绿色且获准后合并。
- 从最新 main 创建并推送注释标签，触发发布工作流。具体见 [发布流程](docs/发布流程.md)。
- 如果 main 出现 develop 不包含的提交，创建 **main → develop** 同步 PR；不直接从本地推送 develop。
- 已发布标签不改写；安装包内容或发布逻辑需要修复时发新版本。Release 文字可以补充已知问题。

## 双端协作

仓库同时维护 macOS（`apps/macos/`）与 Windows（`apps/windows/`）两个客户端。目录职责、代码所有者配置与跨端评审规则见 [双端协作维护](docs/双端协作维护.md)：macOS 由 @huangzx8090 主要维护，Windows 由 @blakceyes（khalil）和 @yhy854 共同维护；Windows 跟进 issue 默认同时委派这两人，邀请或权限尚未就绪时按协作规范记录缺少的指派。`Compatibility/`、`VERSION`、发布脚本和 GitHub Actions 属于双端共享，修改需要双方知情。两端共用同一版本号与资料契约，Release 必须两端构建全部成功才会公开。

## 三层约束与实际限制

| 层面 | 已落实的约束 | 边界 |
| --- | --- | --- |
| 项目约定 | AGENTS.md、此文、PR 模板 | 需要开发者和代理遵守 |
| GitHub Actions | PR 来源 / 目标校验、规则测试和安装包验证 | 没有服务端保护时，仍不能阻止有写权限者直接推送或忽略失败手动合并 |
| 本地 Git hooks | pre-commit 拦截被忽略的本地文件；pre-push 拦截直接推送 main / develop | 只对安装了 hook 的克隆有效，可被绕过，不是服务端安全边界 |

**2026-10-22 实际 API 核验：** 当前私有仓库的分支保护和 ruleset 接口返回 HTTP 403，要求升级 GitHub Pro 或公开仓库。因此没有声称已启用服务器强制保护，也没有更改可见性或付费计划。

未来具备能力后，建议为 main 与 develop 开启：必须 PR、必须上述两项 CI、禁止强推与删除、管理员同样遵守；以实际设置成功并跑通合并为准。

## 历史分支清理

- 仅在确认对应 PR 已合并、没有新提交或未提交工作且不再需要时清理短分支。
- 不删除 main / develop 或已发布标签，不使用 `git branch -D` 强行丢弃工作。
- 保持仓库自动删分支关闭：当前没有服务端保护，自动删除有可能在发布 PR 后误删长期 develop。
- 历史 `feat/tomato-notes-v1` 的剩余提交经 `git cherry` 核对为 main 中已有的等价补丁；仍保留原分支供追溯，不直接拿旧分支合回去。
