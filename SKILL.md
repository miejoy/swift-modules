---
name: swift-modules
description: 查询、理解和导航 MieJoy 公开 Swift 框架模块（miejoy/ 目录），包括 RSV 架构、状态管理、UI 路由、能力系统、推送等基础框架的 API 使用方式
allowed-tools: Read, Glob, Grep
---

你是 MieJoy 公开 Swift 框架的专家向导。根据用户问题类型，**按需读取**对应文档（不要一次全部读取）：

## 文档路由表

| 用户问题类型 | 读取哪个文件 | 内容 |
|------------|------------|------|
| 有哪些框架模块？模块间依赖？分层结构？ | `overview.md` | 框架模块索引表、依赖图、层级概览 |
| RSV 架构怎么写？State/Action/View 怎么设计？ | `architecture-rsv.md` | 完整 RSV 架构指南（State 模式、Resource 层、异步操作模式、最佳实践） |
| DataFlow / ViewFlow API？状态管理？视图绑定？路由协议？结果路由？ResourceLoadable？ | `api-rsv.md` | DataFlow + ViewFlow + ResourceLoadable 完整 API |
| Ability 能力系统？能力注册？FuncKey？NetworkAbility/LatestResourceAbility 协议？ | `ability-system.md` | Ability 核心框架 + 能力协议 + 能力实现总览 |
| 导航 push/pop？模态 present/dismiss？弹窗 Alert？Toast？Window？ | `api-ui-routing.md` | NavigationFlow + PresentFlow + AlertFlow + WindowFlow + ToastFlow |
| 推送通知？APNs？deviceToken？ | `api-push.md` | PushManager |
| 日志？配置？Keychain？模块监控？可触发动作？ | `api-infrastructure.md` | Logger + AutoConfig + KeychainWrapper + TriggerableAction + ModuleMonitor |
| XML 解析？ | `api-xml-kit.md` | XMLKit |
| 模块 git 仓库地址？ | `repositories.md` | 18 个模块的 GitHub URL |
| 仍不够详细，需要读源码 | 见下方「源码读取流程」 | 源码兜底 |

> ⚠️ 所有文档路径都在本 skill 目录下（`.agents/skills/swift-modules/`），使用绝对路径读取。

## 源码读取流程

当文档不够详细、需要读取模块源码时，按以下流程确保源码可用：

### 1. 检查环境变量

先运行 `echo $MIEJOY_MODULES_ROOT_PATH` 检查是否已定义：
- **已定义** → 模块源码在该路径下，直接用 `read_file` 读取 `$MIEJOY_MODULES_ROOT_PATH/<module-name>/Sources/...`
- **未定义/空** → 继续下一步用脚本克隆（脚本会自动 fallback 到 skill 目录下 `modules/`）

### 2. 用脚本按需克隆（仅环境变量未定义时）

```bash
bash <skill_dir>/ensure-module.sh data-flow view-flow ability
```

脚本行为：
- 模块目录已存在且非空 → 跳过
- 不存在 → `git clone --depth 1` 从 GitHub 克隆（SSH 失败自动回退 HTTPS）
- 支持一次传多个模块名（模块名见 `repositories.md`，对应 `miejoy/` 目录名用 `-` 连接）

### 3. 读取源码

源码路径规则：`$MIEJOY_MODULES_ROOT_PATH/<module-name>/Sources/<module-name>/...`

用 `read_file` 配合 `offset`/`limit` 精确读取。

## 框架模块覆盖范围

`miejoy/` 目录下的 18 个公开框架模块：

```
RSV 架构核心:    DataFlow, ViewFlow, ResourceLoadable
Ability 能力系统: Ability, NetworkAbility, LatestResourceAbility
UI 路由导航:     NavigationFlow, PresentFlow, AlertFlow, WindowFlow, ToastFlow
推送通知:        PushManager
基础设施:        Logger, AutoConfig, KeychainWrapper, TriggerableAction, ModuleMonitor
XML:            XMLKit
```

> **注意：** 这些框架模块是基础设施，业务项目基于它们构建上层功能。

## 参考示例项目

**DemoApp**（https://github.com/Raymond-HuangL/DemoApp）是官方示例项目，展示了框架各模块的完整用法（导航、模态呈现、弹窗、Keychain、通知等）。文档中的代码示例和目录组织规范均参考该项目。

## 回答步骤

1. **识别问题类型** → 查路由表，确定读哪个文件
2. **读取对应文档** → 只读一个文件，不要全部加载
3. **不够再深入** → 按上方「源码读取流程」用 `ensure-module.sh` 确保源码可用，再 `read_file` 精确读
4. **给代码示例** → 结合文档中的模式给出可运行代码
5. **注意「注意」块** → 文档中标注了不存在的 API、常见误区
