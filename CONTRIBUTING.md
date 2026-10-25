# 开发与分支约定

## 分支职责

```text
main ────────────── 稳定发布、版本标签
  │                       ↑ 发布 PR
  └── develop ────────────┘ 日常集成
        │          ↑ 功能 PR
        └── feat/xxx
```

| 分支 | 用途 | 更新方式 |
| --- | --- | --- |
| `main` | 可发布的稳定代码，仓库默认分支 | 只接收 develop 的发布 PR |
| `develop` | 最新集成开发代码 | 接收功能分支 PR；必要时接收 main 的同步 PR |
| `<类型>/<描述>` | 一项功能、修复或维护工作 | 从最新 origin/develop 创建，完成后 PR 到 develop |
| `vX.Y.Z` 标签 | 固定发布快照 | 在已合入 main 的版本提交创建注释标签，不移动、不覆盖 |

类型：`feat`、`fix`、`docs`、`chore`、`refactor`、`test`、`ci`、`release`、`hotfix`。类型后用 `/` 连接描述，不加个人名前缀。描述使用简短小写英文与连字符；发布分支的版本可含点，例如 `release/v1.3.3`。即使紧急修复也先进入 develop，再由 develop 发布到 main。

已有历史分支保留，不作为新开发基线，也不为统一命名改写已合并记录。当前未执行历史分支删除。

## 开始工作

首次克隆后：

```bash
Scripts/setup-dev.sh
```

这只修改本仓库的 `core.hooksPath`，启用 `.githooks/pre-push`；如果已经有其他 hook 设置，脚本会停止，不覆盖。每份新克隆都需单独执行。

开始一项功能：

```bash
Scripts/start-work.sh feat/progress-timeline
```

脚本先检查命名与工作区，拉取最新 develop，再创建 `feat/progress-timeline`。存在未提交内容或同名分支时停止，不丢弃任何内容。

也可手动执行：

```bash
git fetch origin develop
git switch -c fix/timer-display origin/develop
```

## 完成开发

1. 只修改本次范围；不混入个人资料、Key、build 或 .build 目录。
2. 执行与变更相称的检查，明确哪些是真实验证、哪些仅规则测试，哪些仍未验证。
3. 使用中文提交，推送同名工作分支，创建目标为 **develop** 的 PR。
4. CI 的 **分支约定**、**测试与编译** 均通过；修改打包输入时，额外通过 **双架构安装包验证**，再获得用户明确的合并授权。普通应用源码与文档变更会跳过安装包 job；`Packaging/`、`Scripts/`、`.github/workflows/`、`Package.swift` 或 `Package.resolved` 变更会触发打包。
5. 合并后从最新 develop 开始下一项工作，不长期复用已经合并的功能分支。

```bash
git add <本次文件>
git commit -m '新增按时间线查看本轮进展'
git push -u origin feat/progress-timeline
```

不直接推送 main / develop，不自动合并 PR；同一会话中用户已经给出的合并授权仍有效，不重复索要。合并 develop → main 时保留合并关系，不 squash 或 rebase 长期分支。

## 发布与回同步

- 在开发分支更新版本、build、CHANGELOG、README 示例、离线安装说明与 `docs/releases/<tag>.md`，先 PR 到 develop。
- 再创建 **develop → main** 的发布 PR，检查绿色且获准后合并。
- 从最新 main 创建并推送注释标签，触发发布工作流。具体见 [发布流程](docs/发布流程.md)。
- 如果 main 出现 develop 不包含的提交，创建 **main → develop** 同步 PR；不直接从本地推送 develop。
- 已发布标签不改写；安装包内容或发布逻辑需要修复时发新版本。Release 文字可以补充已知问题。

## 双端协作

仓库同时维护 macOS（`Sources/`）与 Windows（`Windows/`）两个客户端。目录职责、代码所有者配置与跨端评审规则见 [双端协作维护](docs/双端协作维护.md)：macOS 由 @huangzx8090 主要维护，Windows 由同伴主要维护；`Compatibility/`、发布脚本和 GitHub Actions 属于双端共享，修改需要双方知情。两端共用同一版本号与资料契约，Release 必须两端构建全部成功才会公开。

## 三层约束与实际限制

| 层面 | 已落实的约束 | 边界 |
| --- | --- | --- |
| 项目约定 | AGENTS.md、此文、PR 模板 | 需要开发者和代理遵守 |
| GitHub Actions | PR 来源 / 目标校验、规则测试和安装包验证 | 没有服务端保护时，仍不能阻止有写权限者直接推送或忽略失败手动合并 |
| 本地 pre-push hook | 拦截直接推送 main / develop，功能分支和标签可推送 | 只对安装了 hook 的克隆有效，可被绕过，不是服务端安全边界 |

**2026-10-22 实际 API 核验：** 当前私有仓库的分支保护和 ruleset 接口返回 HTTP 403，要求升级 GitHub Pro 或公开仓库。因此没有声称已启用服务器强制保护，也没有更改可见性或付费计划。

未来具备能力后，建议为 main 与 develop 开启：必须 PR、必须上述两项 CI、禁止强推与删除、管理员同样遵守；以实际设置成功并跑通合并为准。

## 历史分支清理

- 仅在确认对应 PR 已合并、没有新提交或未提交工作且不再需要时清理短分支。
- 不删除 main / develop 或已发布标签，不使用 `git branch -D` 强行丢弃工作。
- 保持仓库自动删分支关闭：当前没有服务端保护，自动删除有可能在发布 PR 后误删长期 develop。
- 历史 `feat/tomato-notes-v1` 的剩余提交经 `git cherry` 核对为 main 中已有的等价补丁；仍保留原分支供追溯，不直接拿旧分支合回去。
