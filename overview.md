# Swift Modules Overview

MieJoy 公开框架模块总览（`miejoy/` 目录），分层结构、依赖关系。

> 最后验证：2026-08-02

---

## 模块总览

```
总计: 18 个公开框架模块 (miejoy/ 目录)
├─ RSV 架构核心: DataFlow, ViewFlow, ResourceLoadable
├─ UI 路由: NavigationFlow, PresentFlow, AlertFlow, WindowFlow, ToastFlow
├─ 能力系统: Ability, NetworkAbility, LatestResourceAbility
├─ 推送: PushManager
├─ 基础设施: Logger, AutoConfig, KeychainWrapper, TriggerableAction, ModuleMonitor
└─ XML: XMLKit
```

## 模块索引

| 模块 | 功能 | 关键 API |
|------|------|----------|
| DataFlow | RSV State 层 | `Store<S>`, `Action`, `FullSharableState` |
| ViewFlow | 视图数据绑定 + 结果路由 | `@SharedState`, `@ViewState`, `ResultableRouteData` |
| Ability | 能力注册系统 | `Ability.getAbility(with:)`, `AbilityCenter.shared` |
| NetworkAbility | HTTP 网络请求 | `HTTPMethod`, `Requestable` |
| LatestResourceAbility | 远程资源 AsyncStream | `LatestResourceAbility` |
| PushManager | 推送通知管理 | `PushManager.shared` |
| NavigationFlow | 导航栈管理 | `navStack.push/pop` |
| PresentFlow | 模态呈现管理 | `presentManager.present/dismiss` |
| AlertFlow | 弹窗管理 | `alertManager.show` |
| WindowFlow | UIWindow 管理 | `WindowSceneState`, `WindowSceneAction`, `WindowHideAnimation` |
| ToastFlow | Toast 通知 | `toastManager` |
| AutoConfig | 自动配置加载 | `Config.value(for:)` |
| KeychainWrapper | Keychain 访问 | `KeychainWrapper.autoLoad()` |
| Logger | 日志框架 | `Logger.shared` |
| ResourceLoadable | 可加载资源协议 | `ResourceLoadable` protocol |
| TriggerableAction | 可触发动作协议 | `TriggerableAction` protocol |
| ModuleMonitor | 模块监控调试 | `ModuleMonitor.shared` |
| XMLKit | XML 处理 | XML parsing utilities |

---

## 分层架构

按依赖关系自底向上分层，每层只依赖下层模块：

```
Layer 4  应用入口
         ┌──────────────────────────────────┐
         │ ToastFlow                        │
         │ PushManager                      │
         └──────────────────────────────────┘
                    ↑
Layer 3  UI 路由 / 业务能力
         ┌──────────┬──────────┬──────────┬──────────┐
         │Navigation│ Present  │  Alert   │ Window   │
         │  Flow    │  Flow    │  Flow    │  Flow    │
         └──────────┴──────────┴──────────┴──────────┘
         ┌──────────┬───────────────────────────────┐
         │ Network  │ LatestResourceAbility         │
         │ Ability  │                               │
         └──────────┴───────────────────────────────┘
                    ↑
Layer 2  RSV 核心
         ┌──────────┬───────────────────────────────┐
         │ DataFlow │ Ability                        │
         │          │ ResourceLoadable               │
         └──────────┴───────────────────────────────┘
                    ↑
Layer 1  基础设施（零依赖）
   ┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
   │ Module   │   Auto   │  Logger  │Triggerable│ Keychain  │  XMLKit  │
   │ Monitor  │  Config  │          │  Action   │ Wrapper   │          │
   └──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
                    ↑
Layer 0  业务项目（基于以上 18 个框架模块构建）
```

### 依赖详情

| 层 | 模块 | 依赖 |
|------|------|------|
| L1 | ModuleMonitor | (无) |
| L1 | AutoConfig | (无) |
| L1 | Logger | (无) |
| L1 | TriggerableAction | (无) |
| L1 | KeychainWrapper | (无) |
| L1 | XMLKit | (无) |
| L2 | DataFlow | ModuleMonitor |
| L2 | Ability | AutoConfig, ModuleMonitor |
| L2 | ResourceLoadable | ModuleMonitor |
| L3 | ViewFlow | DataFlow, ModuleMonitor |
| L3 | NavigationFlow | ViewFlow, ModuleMonitor |
| L3 | PresentFlow | ViewFlow, ModuleMonitor |
| L3 | AlertFlow | ViewFlow, ModuleMonitor |
| L3 | WindowFlow | DataFlow, ViewFlow, Logger |
| L3 | NetworkAbility | Ability |
| L3 | LatestResourceAbility | Ability, Logger |
| L4 | ToastFlow | WindowFlow, AutoConfig |
| L4 | PushManager | TriggerableAction, Logger, AlertFlow, PresentFlow, AutoConfig, ViewFlow |

### 被依赖次数

| 模块 | 被依赖次数 |
|------|-----------|
| ModuleMonitor | 7 |
| ViewFlow | 6 |
| DataFlow | 3 |
| AutoConfig | 3 |
| Logger | 3 |
| Ability | 2 |
| AlertFlow | 1 |
| WindowFlow | 1 |
| TriggerableAction | 1 |

> **注意：** 业务项目基于以上 18 个框架模块构建上层功能模块，依赖方向始终自上而下。
