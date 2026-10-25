# CLAUDE.md

## 强制加载

必须在每次会话开始时加载 `@AGENTS.md`，不得跳过。`AGENTS.md` 包含本项目的全部硬规则（质量验证、提交与分支规则、CI/CD 禁止事项、可用性验收和安全边界等）；凭记忆行事会导致返工或产生不安全变更。

双端工程位于 `apps/macos/` 与 `apps/windows/`。维护分工、分支命名和跨端 issue 规则见 `docs/双端协作维护.md`；交付前必须作跨端判断，优先使用 `gh` 创建或补充适用的跟进 issue。资料契约样例在 `Compatibility/`，改到它需要双方知情。

@AGENTS.md
