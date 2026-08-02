# swift-modules

AI agent skill for MieJoy Swift modular framework — API documentation & source navigation for 18 modules.

## What is this?

A [BoxAI skill](https://github.com/Raymond-HuangL) that helps AI coding assistants **query, understand, and navigate** the MieJoy Swift framework. Instead of reading all source code, the AI reads structured docs on demand — one file per topic — then falls back to source when needed.

## Modules covered (18)

```
RSV 架构核心:    DataFlow, ViewFlow, ResourceLoadable
Ability 能力系统: Ability, NetworkAbility, LatestResourceAbility
UI 路由导航:     NavigationFlow, PresentFlow, AlertFlow, WindowFlow, ToastFlow
推送通知:        PushManager
基础设施:        Logger, AutoConfig, KeychainWrapper, TriggerableAction, ModuleMonitor
XML:            XMLKit
```

## How it works

1. **SKILL.md** — Entry point with a routing table that maps user questions → doc files
2. **Topic docs** — Each file covers one area (RSV architecture, UI routing, ability system, etc.)
3. **ensure-module.sh** — Clones source code on demand when docs aren't enough
4. **Source fallback** — Reads actual `.swift` files for implementation details

## Usage

Load this skill in any BoxAI-compatible agent:

```
use_skill("swift-modules")
```

Then ask questions like:
- "RSV 架构怎么写？State/Action/View 怎么设计？"
- "导航 push/pop 怎么用？"
- "Ability 能力系统怎么注册？"

## Files

| File | Purpose |
|------|---------|
| `SKILL.md` | Entry point & routing table |
| `overview.md` | Module index, dependency graph, layer overview |
| `architecture-rsv.md` | RSV architecture guide (State patterns, Resource layer, async patterns) |
| `api-rsv.md` | DataFlow + ViewFlow + ResourceLoadable API |
| `api-ui-routing.md` | Navigation / Present / Alert / Window / Toast |
| `ability-system.md` | Ability registration & protocols |
| `api-push.md` | PushManager (APNs) |
| `api-infrastructure.md` | Logger / AutoConfig / KeychainWrapper / TriggerableAction / ModuleMonitor |
| `api-xml-kit.md` | XMLKit |
| `repositories.md` | Git URLs for all 18 modules |
| `ensure-module.sh` | Clone-on-demand helper script |

## Example project

[DemoApp](https://github.com/Raymond-HuangL/DemoApp) — official demo showing all framework modules in action.

## License

MIT
