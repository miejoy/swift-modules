# 基础设施框架 API

日志、配置、Keychain、可触发动作、模块监控——不归属于特定业务领域的基础框架模块。

> 配套文档：`overview.md`（模块索引）
> 最后验证：2026-08-02（已对齐源码）

---

## Logger - 日志框架

**用途:** 结构化日志记录，支持多等级、多片段、自定义记录器

**核心类型:**
- `Logger` — 日志管理器（`final class, Sendable`），`Logger.shared` 单例
- `LogLevel` — 日志等级枚举（`Comparable`）：`.trace` / `.debug` / `.info` / `.notice` / `.warning` / `.error` / `.fault`
- `LogContent` — 日志内容（date/level/labels/messages/userInfo/file/line/method）
- `LogRecorder` — 日志记录协议（`write(log:of:)`），默认实现 `OSRecorder`（基于 `os.Logger`）
- `CombineRecorder` — 多记录器组合（`init(_ recorders: LogRecorder...)`）
- `LogSegment` — 日志片段（`.string(String)` / `.content(LogStringConverter)`），`.defaultSegments` 默认片段

**全局函数:**
```swift
LogTrace(_ message: @autoclosure () -> Any)   // .trace
LogDebug(_ message: @autoclosure () -> Any)   // .debug
LogInfo(_ message: @autoclosure () -> Any)    // .info
LogNotice(_ message: @autoclosure () -> Any)  // .notice
LogWarning(_ message: @autoclosure () -> Any) // .warning
LogError(_ message: @autoclosure () -> Any)   // .error
LogFault(_ message: @autoclosure () -> Any)   // .fault（DEBUG 构建 fatalError）
```

**Logger 实例方法（等效全局函数）:**
```swift
let logger = Logger(label: "MyModule", logLevel: .debug)
logger.trace("...")
logger.debug("...")
logger.info("...")
logger.notice("...")
logger.warning("...")
logger.error("...")
logger.fault("...")
```

**关键属性:**
- `logLevel: LogLevel` — 当前日志等级（低于此等级不记录，默认 `.debug`）
- `labels: [String]` — 标签列表（用于标识来源）
- `recorder: LogRecorder` — 记录器（默认 `OSRecorder`）
- `throwFault: Bool` — `fault` 级别是否 `fatalError`（默认 `true`，仅 DEBUG 构建）
- `deriveLoggerWith(label:)` — 派生子 Logger（继承父配置 + 新增 label）

**线程安全:** 所有读写通过 `DispatchQueue.syncOnLoggerQueue`（`"logger.logger_queue"`）串行保护。

> **Logger + OSRecorder 注意事项：** `os.Logger.debug()` 级别日志**不会持久化到磁盘**，`log show` 无法回查。只有 `notice` 及以上级别才会持久化。DEBUG 构建时建议自定义 Recorder 将 debug/trace/info 统一映射为 `logger.notice()` 输出，确保 `log show` 可查。`log stream` 命令可实时查看所有级别（包含 debug），但需先开启再操作。

> **fault 行为：** `LogFault()` / `logger.fault()` 在 DEBUG 构建且 `throwFault == true` 时会触发 `fatalError`。非 DEBUG 构建仅记录日志。`OSRecorder` 将 `fault` 映射为 `os.Logger.critical()`。

**依赖:** (无)

**平台:** iOS 14+, macOS 11+, tvOS 14+, watchOS 7+

---

## AutoConfig - 自动配置加载

**用途:** 自动配置加载框架，支持 JSON/Plist 文件 + 代码配置，提供 `ConfigKey` 类型安全和 `ConfigKeyPath` 层级路径

**核心类型:**
- `Config` — 配置管理命名空间（`public enum Config`），`set(value:for:)` / `value(for:)`
- `ConfigKey<Value>` — 类型安全配置键（`Hashable, Sendable`），如 `ConfigKey<String>("baseUrl")`
- `ConfigKeyPath<Value>` — 层级配置路径，通过 `key.append(nextKey)` 构造
- `ConfigPair` — 配置对（`Hashable, @unchecked Sendable`），支持 `.make(key, value)` / `.group(key, [pairs])`
- `ConfigProtocol` — 配置协议（`static var configs: [ConfigPair] { get }`），业务项目实现 `UserConfig` 类

**配置来源（自动加载顺序）:**
1. `configs.json` 或 `configs.plist`（Bundle.main 根目录，json 优先）
2. `UserConfig` 类（遵循 `ConfigProtocol`，通过 `Bundle.main.classNamed` 动态查找）
3. 代码中 `Config.set(value:for:)`（建议仅启动阶段）

**API:**
```swift
// 定义 Key
let baseUrlKey = ConfigKey<String>("baseUrl")
let timeoutKey = ConfigKey<Int>("timeout")

// 设置/读取
Config.set("https://api.example.com", for: baseUrlKey)
let url = Config.value(for: baseUrlKey)
let urlWithDefault = Config.value(for: baseUrlKey, "https://default.com")

// 层级路径
let groupKey = ConfigKey<String>("network")
let subKey = ConfigKey<String>("baseUrl")
let path = groupKey.append(subKey)  // ConfigKeyPath<String>
Config.set("https://...", with: path)
let value = Config.value(with: path)

// 内置 Key
Config.appId  // ConfigKey<String>("appId")

// 业务项目实现
class UserConfig: ConfigProtocol {
    static var configs: [ConfigPair] {
        [
            .make(.appId, "com.example.app"),
            .group("network", [
                .make(.init("baseUrl"), "https://api.example.com"),
                .make(.init("timeout"), 30)
            ])
        ]
    }
}
```

**线程安全:** 所有读写通过 `DispatchQueue.syncOnConfigQueue`（`"auto-config.config_queue"`）串行保护。

**依赖:** (无)

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

---

## KeychainWrapper - Keychain 访问

**用途:** Keychain 数据存储，通过 `SafeStorage` 接口访问（KeychainWrapper 是 SafeStorage 的默认实现）

**核心类型:**
- `KeychainWrapper` — Keychain 访问封装（`final class, Sendable`），实现 `SafeStorage` 协议
- `SafeStorage` — 安全存储协议（定义在 Ability 框架中，通过 `Ability.getAbility(with:)` 获取）

**主要 API:**
- `KeychainWrapper.autoLoad()` — 自动加载，注册到 Ability 系统
- `KeychainWrapper.configDefault(with:accessGroup:)` — 初始化配置（必须先调用）
- `wipeAll()` / `wipeDatas()` / `wipeAccounts()` — 清除数据

> **KeychainWrapper 注意事项：** 使用前**必须**调用 `KeychainWrapper.configDefault(with: serviceName, accessGroup: nil)` 初始化。KeychainWrapper 内部使用 `kSecAttrGeneric` 作为数据标识键，在 macOS App Sandbox（`ENABLE_APP_SANDBOX = YES`）下写入会失败。解决方案：关闭 App Sandbox 或配置 Keychain Sharing entitlement。iOS 不受此问题影响。`wipeAll()` = `wipeDatas()` + `wipeAccounts()`，`wipeDatas()` 只清普通数据，`wipeAccounts()` 只清账号数据。`KeychainWrapper` 符合 `Sendable` 协议，可安全跨 Actor 传递。

**依赖:** (无)（`SafeStorage` 协议定义在 Ability 框架，但 KeychainWrapper 本身无依赖）

**平台:** iOS 14+, macOS 11+, tvOS 14+, watchOS 7+

---

## TriggerableAction - 可触发动作

**用途:** 定义可触发动作的协议体系，用于模块间事件传递，支持同步/异步、带/不带结果、组合、类型擦除、数据转换

**协议继承体系:**
```
TriggerableAsyncResultAction          ← 异步 + 带结果（最基础协议）
├── TriggerableAsyncAction            ← 异步 + 无结果（ResultData == Void）
└── TriggerableResultAction           ← 同步 + 带结果（追加同步 trigger 方法）
    └── TriggerableAction             ← 同步 + 无结果（最严格协议）
```

**核心协议:**
```swift
public protocol TriggerableAsyncResultAction: Sendable {
    associatedtype TriggerData
    associatedtype ResultData
    func trigger(with data: TriggerData) async throws -> ResultData
}

public protocol TriggerableResultAction: TriggerableAsyncResultAction {
    func trigger(with data: TriggerData) throws -> ResultData  // 同步版本
}

public protocol TriggerableAsyncAction: TriggerableAsyncResultAction where ResultData == Void {}
public protocol TriggerableAction: TriggerableAsyncAction, TriggerableResultAction {}
```

**内置实现:**

| 类型 | 协议 | 说明 |
|------|------|------|
| `TriggerBlockAction<T>` | `TriggerableAction` | 同步闭包，无结果 |
| `TriggerAsyncBlockAction<T>` | `TriggerableAsyncAction` | 异步闭包，无结果 |
| `TriggerBlockResultAction<T, R>` | `TriggerableResultAction` | 同步闭包，带结果 |
| `TriggerAsyncBlockResultAction<T, R>` | `TriggerableAsyncResultAction` | 异步闭包，带结果 |
| `TriggerGroupAction<T>` | `TriggerableAction` | 同步事件组（`.add(trigger)`，顺序执行） |
| `TriggerAsyncGroupAction<T>` | `TriggerableAsyncAction` | 异步事件组 |
| `TriggerGroupResultAction<T, R>` | `TriggerableResultAction` | 同步带结果事件组（返回 `[ResultData]`） |
| `TriggerAsyncGroupResultAction<T, R>` | `TriggerableAsyncResultAction` | 异步带结果事件组 |

**类型擦除:**
- `AnyTriggerAction<T>` / `AnyAsyncTriggerAction<T>` — 无结果类型擦除
- `AnyTriggerResultAction<T, R>` / `AnyAsyncTriggerResultAction<T, R>` — 带结果类型擦除
- `eraseToAny()` — 擦除为对应 Any 类型
- `eraseResult()` — 擦除结果（`ResultData == Void` 时）
- `eraseToAsyncAny()` — 同步升级为异步

**链式组合:**
```swift
// prepend: 前置转换器/触发器（改变 TriggerData 类型）
action.prepend(converter)    // DataConverter: Input → TriggerData
action.prepend { input in ... }  // 闭包转换
action.prepend(otherTrigger) // 前置 ResultAction，其 ResultData == 本 TriggerData

// append: 后置触发器（仅 ResultAction，改变 ResultData 类型）
resultAction.append(otherTrigger)  // otherTrigger.TriggerData == 本 ResultData

// group: 组合
let group = action1.group()  // TriggerGroupAction
group.add(action2)
```

**DataConverter 协议:**
```swift
public protocol AsyncDataConverter: Sendable {
    associatedtype Input
    associatedtype Output
    func process(data: Input) async throws -> Output
}
public protocol DataConverter: AsyncDataConverter {
    func process(data: Input) throws -> Output  // 同步版本
}
```

**依赖:** (无)

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

---

## ModuleMonitor - 模块监控调试

**用途:** 模块运行状态监控与调试，提供通用的事件观察者模式，是各模块 Monitor 的基础

**核心类型:**
- `ModuleMonitor<Event>` — 模块监视器（`open class`，泛型 `<Event: MonitorEvent>`）
- `MonitorEvent` — 监控事件协议（`Sendable`，要求 `static func fatalError(_ message: String) -> Self`）
- `MonitorObserver` — 观察者协议（`AnyObject, Sendable`）

**API:**
```swift
// 创建监视器（需提供通知回调）
let monitor = ModuleMonitor<MyEvent> { event, observer in
    // 事件通知回调（在 monitorQueue 中执行）
}

// 添加观察者（返回 AnyCancellable，取消时自动移除）
let cancellable = monitor.addObserver(observer)

// 记录事件（通知所有观察者）
monitor.record(event: .someEvent)

// 致命错误（无观察者时 DEBUG 构建 fatalError，有观察者时转为事件）
monitor.fatalError("Something went wrong")
```

> **fatalError 行为：** `fatalError()` 在 DEBUG 构建下：如果无观察者则直接 `Swift.fatalError`，有观察者则转为 `.fatalError` 事件通知。非 DEBUG 构建仅记录事件。

**线程安全:** 所有操作通过 `DispatchQueue.syncOnMonitorQueue`（`"module-monitor.monitor_queue"`）串行保护。

> **使用模式：** 各业务模块定义自己的 `Event` 枚举（遵循 `MonitorEvent`），创建对应的 `ModuleMonitor<Event>` 单例。例如 `NavigationMonitor`、`AlertMonitor`、`PresentMonitor` 等都基于此框架。

**依赖:** (无)

**平台:** iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+
