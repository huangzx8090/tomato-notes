# 番茄小记项目约定

## 分支与交付

- `main` 是稳定发布分支，`develop` 是日常集成分支；仓库默认分支保持 `main`。
- 功能与修复从最新 `origin/develop` 建立短分支，使用 `<类型>/<简短英文描述>`，例如 `feat/progress-timeline`、`fix/timer-display`，不加个人名前缀。
- 类型为 `feat`、`fix`、`docs`、`chore`、`refactor`、`test`、`ci`、`release` 或 `hotfix`。
- 普通 PR 进入 `develop`；发布 PR 为 `develop` → `main`；发布后的同步 PR 可为 `main` → `develop`。
- 不直接推送 main / develop，不改写已发布标签，不绕过检查；提交信息使用中文。
- 合并需要用户明确授权；同一会话已经给出的授权不重复询问，未经授权不自动合并。
- 先检查工作区，不丢弃或覆盖他人未提交内容。旧分支保留，不在其他任务中顺手删除。
- 详细操作见 CONTRIBUTING.md；新克隆执行 Scripts/setup-dev.sh，快速开分支用 Scripts/start-work.sh。

## 验证与资料

- 执行与变更风险相称的验证。Scripts/test.sh 为规则与模拟接口测试；构建和发布使用现有脚本。
- 界面、系统通知、Chrome 授权 / 截图 / 关闭的真实验证与规则测试分开报告。
- 不用个人待办、便签或重要浏览标签做破坏性测试。用户要求暂停实机测试时继续遵守。
- 日常使用和交付用户操作的预览共用固定本机资料库，普通启动并复用已有实例；不要把带独立 `--data-dir` 的测试实例当成日常入口。自动化或破坏性验证显式使用 `--ui-test` / 独立资料，交付时说明隔离状态。
- 不提交 Key、.build、build 或个人数据；日志不得输出密钥。
- 发版同时更新 Info.plist 的版本与 build、CHANGELOG、docs/releases/<tag>.md。版本标签只能指向 main 中的提交。

## 当前平台限制

截至 2026-10-22，GitHub 对此私有仓库的分支保护 / ruleset 请求返回 403，要求 Pro 或公开仓库。当前依靠约定、CI 和本地 hook，不能声称有服务端强制保护。未经用户授权，不更改可见性、不升级付费计划。
