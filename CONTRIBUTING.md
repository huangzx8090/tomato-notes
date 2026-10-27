# 开发与分支约定

本文件维护开分支和 PR 交付的操作流程；平台命令、跨端跟进和发布细节分别在对应专题维护。AI 可用 [$tomato-notes-workflow](.agents/skills/tomato-notes-workflow/SKILL.md) 按任务定位。

## 分支职责

| 分支 | 用途与更新方式 |
| --- | --- |
| `main` | 默认分支，保存稳定发布；只接收 `develop` 的发布 PR |
| `develop` | 日常集成；接收工作分支 PR，必要时接收 `main` 的回同步 PR |
| `<类型>/<平台>-<描述>` | 从最新 `origin/develop` 开始一项工作，完成后 PR 到 `develop` |
| `release/vX.Y.Z` | 发布准备分支，先 PR 到 `develop` |
| `vX.Y.Z` 标签 | `main` 中发布提交的注释标签，不移动或覆盖 |

类型为 `feat`、`fix`、`docs`、`chore`、`refactor`、`test`、`ci`、`release`、`hotfix`；平台为 `macos`、`windows`、`shared`，描述使用简短小写英文与连字符，不加个人名前缀。同一工作涉及两端或公共配置时使用 `shared`。历史命名保持兼容，不为改名重写记录；紧急修复也先进入 `develop`。

## 开始工作

先检查当前分支、工作区和已有 PR。已有本任务的未合并分支时沿用；不要复用已合并分支开始新任务。有无关未提交内容时保留原状，优先在独立 worktree 中开始。

新克隆执行：

```bash
Scripts/setup-dev.sh
```

脚本仅为当前克隆启用 `.githooks`；已存在其他 `core.hooksPath` 时停止，先整合而不覆盖。本地 hooks 拦截被忽略文件进入提交及直接推送 `main` / `develop`，不能代替服务端保护。

创建新工作分支，例如：

```bash
Scripts/start-work.sh feat/macos-history-search
```

脚本检查命名和工作区，拉取 `origin/develop` 后创建分支；遇到未提交内容或同名分支会停止。Windows 可在 Git Bash 使用，或手动执行 `git fetch origin develop` 后从 `origin/develop` 创建同名分支。

## 验证选择

- 代码变更使用 [macOS 入口](apps/macos/AGENTS.md#构建与测试)或 [Windows 入口](apps/windows/README.md#构建与测试)中的相关检查；资料格式变更还需覆盖[共同契约](Compatibility/README.md)和迁移兼容。
- 文档变更核对文件链接、章节锚点、命令及 `git diff --check`。skill 变更还需校验元数据；路由或发现方式变化时验证实际发现结果及代表性任务的读取与授权边界。
- 规则与模拟接口测试、编译、安装包和实机操作分别记录。自动化 / 破坏性验证使用隔离资料；普通交付预览使用日常资料并复用已有实例。
- CI 和打包要求按[当前策略](docs/发布流程.md#ci-与打包)核对，不因文档改动自行修改触发规则。无法在当前环境完成的检查如实列出，不以编译成功代替实机结果。

## 完成开发

1. 检查另一端是否存在对应能力或同类问题，按[跨端跟进](docs/双端协作维护.md#跨端跟进)作出判断。需要提 issue 时在来源 PR 创建后执行并回填链接；纯文档等无需跟进的情况写明原因。
2. 用户可见变化更新已有 README、指南或 CHANGELOG。过程记录只放已忽略的 `.local-dev/` 或 `PROJECT_PROGRESS.md`，不新增受跟踪的过程归档。
3. 明确列出本次文件暂存，查看 `git diff --cached --name-status` 和实际 diff。不得提交 Key、个人资料、构建产物或本地过程文件，不用 `git add -f` 或绕过 hooks 强行提交。
4. 中文提交，推送同名工作分支，创建目标为 `develop` 的 PR。按 [PR 模板](.github/pull_request_template.md)填写实际验证、未验证范围、跨端判断和兼容风险；多行正文先写临时文件，再用 `--body-file` 提交。
5. 跟踪对应提交的 CI，在任务范围内修复失败，分别报告成功、失败或仍运行的状态。检查通过后仍需用户明确授权合并，同一会话已给出的有效授权不重复询问。

例如，暂存并检查本次文件、准备好 `.local-dev/pr.md` 后：

```bash
git commit -m '新增历史记录搜索'
git push -u origin feat/macos-history-search
gh pr create --base develop --head feat/macos-history-search --body-file .local-dev/pr.md
```

发布准备、`develop` → `main`、标签和必要的 `main` → `develop` 回同步统一见[发布流程](docs/发布流程.md#发布一个新版本)。

## 分支与权限维护

分支保护、ruleset、仓库可见性和成员权限以实时查询为准。项目约定、GitHub Actions、本地 hooks 和 CODEOWNERS 各有边界，不能仅凭文件或 CI 绿色声称服务端已强制保护；不为执行流程擅自修改这些设置或升级计划。

历史分支不强制改名、不作为新基线，不在其他任务中顺手删除。只有确认对应 PR 已合并、没有剩余工作且获准清理时才删除短分支，不用 `git branch -D` 强行丢弃内容；保留 `main`、`develop` 和发布标签，不擅自开启自动删分支。
