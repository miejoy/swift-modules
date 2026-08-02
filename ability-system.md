# Ability 能力系统

模块间通信的依赖注入框架，解耦模块耦合。Ability 既是核心框架，又贯穿多个业务模块——框架层定义协议，业务层实现并注册，使用方通过 `Ability.getAbility(of:)` / `Ability.getAbility(with:)` 获取，不直接依赖具体实现。

> 配套文档：`overview.md`（模块索引）、`architecture-rsv.md`（RSV 架构指南）
> 最后验证：2026-08-02（已对齐源码）

---

## Ability 核心框架

**用途:** 模块间通信的依赖注入框架，解耦模块耦合

**依赖:** auto-config, module-monitor

**核心概念:**
- `AbilityProtocol` - 能力接口（`AnyObject`，class-only），要求 `static var abilityName: AbilityName` + `func load()`
- `AbilityName` - 能力名（`Hashable, Sendable`），通过 `AbilityName(SomeProtocol.self)` 构造，内部用 `ObjectIdentifier` 做唯一标识
- `AbilityCenter` - 全局能力注册中心（单例，通过 `AbilityQueue` 串行队列保护线程安全）
- `Ability` - 命名空间枚举（`public enum Ability {}`），提供静态方法入口
- `FuncKey<Input, Return>` / `DefaultFuncKey<Input, Return>` - 函数级能力注册（细粒度）
- `AbilityMonitor` - 注册/替换事件监控（来自 module-monitor 体系）

**能力注册方式:**

AbilityCenter 不提供公开的 `register(ability:for:)` 方法。能力注册通过 `AutoConfig` 配置体系完成：

```swift
// 1. 定义能力接口（必须 class-only 协议）
protocol LoggingAbility: AbilityProtocol {
    func log(_ message: String)
}

// 2. 实现能力（必须是 class）
final class ConsoleLogger: LoggingAbility {
    static var abilityName: AbilityName { AbilityName(LoggingAbility.self) }
    
    func log(_ message: String) {
        print("[LOG] \(message)")
    }
    
    func load() { /* 可选：能力加载时调用 */ }
}

// 3. 通过 AutoConfig 注册（项目配置中）
// Config.set(.abilityConfig, AbilityConfig(abilities: [
//     AbilityWrapper(ConsoleLogger())
// ]))
// 或在 AbilityConfig 的 abilities() 方法中返回
```

> **注册流程：** `AbilityCenter.shared` 首次访问时 → `init()` 读取 `AbilityConfig` → `registerAbilities(config.abilities())` → `load()` 调用每个能力的 `load()` 方法 → `registerFuncs(config.funcs())` 注册函数级能力。

**获取能力:**

```swift
// 方式 1：通过 AbilityName 获取（返回 nil 表示未注册）
let ability = Ability.getAbility(of: LoggingAbility.abilityName) as? LoggingAbility

// 方式 2：带默认值获取（未注册时返回默认实现，不会 nil）
let logger = Ability.getAbility(with: ConsoleLogger()) as! LoggingAbility
```

**FuncKey 函数级能力注册:**

函数级能力通过 `FuncKey<Input, Return>` 注册，支持独立于 Ability 协议的细粒度函数注入。

```swift
// 定义 FuncKey（Input/Return 泛型 + funcId 标识）
public let funcLocalized = FuncKey<(String, String?, String?, String, Int, String), String?>(funcId: "localized")

// 注册实现（通过 AbilityCenter.shared.register）
AbilityCenter.shared.register(funcLocalized) { (key, defaultValue, category, file, line, method) in
    return NSLocalizedString(key, comment: "")
}

// 调用（返回 nil 表示未注册）
let str = Ability.execute(funcLocalized, params: ("greeting", nil, "Home", #file, #line, #function)) ?? "greeting"
```

**DefaultFuncKey（带默认实现的函数能力）:**

```swift
// 定义带默认实现的 FuncKey
public let funcFormat = DefaultFuncKey<Date, String>(
    funcId: "formatDate",
    defaultRun: { date in
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }
)

// 调用（未注册时自动使用 defaultRun，不返回 nil）
let formatted = Ability.execute(funcFormat, params: Date())
```

> **execute 重载：** `Ability.execute` 对 `FuncKey` 和 `DefaultFuncKey` 各有 4 种重载（有/无 Input × 有/无 Return），共 8 种。对 `DefaultFuncKey` 始终返回非 Optional（有默认值兜底）。

> **线程安全：** 所有注册/读取操作通过 `DispatchQueue.syncOnAbilityQueue` 串行保护。`getAbility` 是 `@inlinable`，内部直接读 `AbilityCenter.shared[name.identifier]`。

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

---

## NetworkAbility - 网络请求能力

**用途:** 统一的网络请求接口，支持 GET/POST/上传，提供 async/await 和 Combine Future 两套 API

**依赖:** ability

**协议继承关系:**
```
AbilityProtocol
└── NetworkAbility          ← 通用网络能力（request 方法 + responseDecoder）
    └── HTTPAbility          ← HTTP 扩展能力（httpRequest/httpUpload + HTTPMethod）
```

**NetworkAbility 协议:**
```swift
public protocol NetworkAbility: AbilityProtocol, Sendable {
    var responseDecoder: NetworkResponseDecoder { get }
    
    func request<E: Encodable>(
        url: URL,
        method: RequestMethod,
        body: E?,
        header: NetworkHeaders?
    ) async throws -> (data: Data, headers: NetworkHeaders)
}
```

**HTTPAbility 协议（继承 NetworkAbility）:**
```swift
public protocol HTTPAbility: NetworkAbility {
    func httpRequest<E: Encodable>(
        url: URL, method: HTTPMethod, formData: URLEncodeWrapper?,
        body: E?, header: NetworkHeaders?
    ) async throws -> (data: Data, headers: NetworkHeaders)
    
    func httpUpload(
        url: URL, files: [URL], filesKey: String,
        method: HTTPMethod, formData: URLEncodeWrapper?, header: NetworkHeaders?
    ) async throws -> (data: Data, header: NetworkHeaders)
}
```

**Ability 入口:**
```swift
// 通用网络能力（返回 NetworkAbility，未注册时用 DefaultHTTPDriver）
Ability.network    // NetworkAbility

// HTTP 能力（返回 HTTPAbility，未注册时用 DefaultHTTPDriver）
Ability.http       // HTTPAbility
```

**使用示例（async/await）:**
```swift
struct UserResponse: Decodable {
    let id: Int
    let name: String
}

// GET 请求（Decodable 自动解码）
let users: [UserResponse] = try await Ability.http.httpRequest(
    URL(string: "https://api.example.com/users")!
)

// POST 请求（Encodable body + Decodable response）
let newUser = try await Ability.http.httpRequest(
    URL(string: "https://api.example.com/users")!,
    .post,
    body: ["name": "John"]
) as UserResponse

// 文件上传
let result: UserResponse = try await Ability.http.httpUpload(
    URL(string: "https://api.example.com/upload")!,
    files: [fileURL],
    filesKey: "files"
)
```

**使用示例（Combine Future）:**
```swift
// HTTPAbility 也提供 Future 版本（用于 Combine 链式调用）
let cancellable = Ability.http.httpRequest(
    URL(string: "https://api.example.com/users")!,
    .get
) as Future<[UserResponse], Error>
.sink { completion in
    // ...
} receiveValue: { users in
    // ...
}
```

> **默认实现：** `DefaultHTTPDriver` 实现了 `HTTPAbility`，使用 `URLSession`。业务项目可通过注册自定义 `HTTPAbility` 替换（如添加拦截器、重试等）。

> **NetworkAbility vs HTTPAbility：** `NetworkAbility` 是基础网络协议（`RequestMethod` 枚举），`HTTPAbility` 继承它并扩展了 `HTTPMethod`、`formData`、文件上传等 HTTP 特有能力。日常使用推荐 `Ability.http`（HTTPAbility）。

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

---

## LatestResourceAbility - 最新资源能力

**用途:** 监听最新服务器资源变化，持续推送更新（用于配置、主题、文案等远程资源）

**依赖:** ability, logger

**核心协议:**
```swift
public protocol LatestResourceAbility: AbilityProtocol & Sendable {
    func load<T: Decodable & Sendable>(_ name: String, as type: T.Type) -> AsyncStream<T?>
}
```

**Ability 入口:**
```swift
// 未注册时使用 DefaultLatestResourceLoader
Ability.latestResource    // LatestResourceAbility
```

**LoadableLatestResource（声明式资源定义）:**
```swift
public protocol LoadableLatestResource {
    associatedtype Response: Decodable & Sendable
    var name: String { get }
}

// 扩展：通过 Ability.latestResource.load 加载
extension LoadableLatestResource {
    public func open() -> AsyncStream<Response?> {
        Ability.latestResource.load(name, as: Response.self)
    }
}

// 便利类型
public struct AnyLatestResource<Response: Decodable & Sendable>: LoadableLatestResource {
    public var name: String
    public init(name: String)
}
```

**使用示例:**
```swift
// 方式 1：直接通过 Ability.latestResource
let themeStream = Ability.latestResource.load("themes", as: [Theme].self)

for await themes in themeStream {
    if let themes = themes {
        updateUI(with: themes)  // 每次新主题到达时调用
    }
}

// 方式 2：声明式资源定义（推荐）
struct ThemeResource: LoadableLatestResource {
    typealias Response = [Theme]
    let name = "themes"
}

for await themes in ThemeResource().open() {
    // themes 是 [Theme]? 类型
}

// 只获取第一个值（单次加载）
let firstValue = await themeStream.first()
```

**特性:**
- 异步流（`AsyncStream<T?>`），支持多个订阅者
- `DefaultLatestResourceLoader` 默认从 Bundle 加载（`latest-resource/` 目录，优先 `.json`，其次 `.plist`）
- 内部通过 `AsyncCurrentValue<Data?>` 管理多订阅者共享
- 支持 `update(name, with:)` 手动推送新数据（业务层可调用）
- `DefaultLatestResourceLoader` 可自定义 `bundle`、`resourceDir`、`jsonDecoder`

> **业务实现示例:** 可通过实现 `LatestResourceAbility` 协议提供多层加载策略（服务器 → 加密缓存 → Bundle），注册到 `AbilityCenter` 替换默认实现。

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

---

## Ability 生态总览

| 层级 | 模块/类型 | 角色 | 说明 |
|------|----------|------|------|
| **核心框架** | `Ability` | 命名空间 | `Ability.getAbility(of:)`、`Ability.getAbility(with:)`、`Ability.execute()` |
| | `AbilityProtocol` | 协议 | 所有能力接口（class-only，要求 `abilityName` + `load()`） |
| | `AbilityCenter` | 注册中心 | 单例，通过 `AbilityQueue` 串行保护，注册靠 `AutoConfig` 配置 |
| | `AbilityConfig` | 配置 | 定义 `abilities()`/`funcs()`/`removeFuncs()`，由 `AutoConfig` 驱动 |
| | `FuncKey`/`DefaultFuncKey` | 函数级能力 | 细粒度注册（SafeStorage/Message 等用它） |
| | `AbilityMonitor` | 监控 | 注册/替换事件的观察 |
| **能力协议** | `NetworkAbility` | 网络能力协议 | `request()` + `responseDecoder`，由业务项目实现 |
| | `HTTPAbility` | HTTP 扩展协议 | 继承 `NetworkAbility`，`httpRequest()`/`httpUpload()` + `HTTPMethod` |
| | `LatestResourceAbility` | 远程资源能力协议 | `load(name, as:)` → `AsyncStream<T?>`，由业务项目实现 |
| | `LoadableLatestResource` | 声明式资源 | `name` + `Response`，`open()` 便利方法 |

Ability 的本质是**依赖注入 + 插件注册**——框架层定义协议，业务层通过 `AutoConfig` 配置实现并注册，使用方通过 `Ability.getAbility(with:)` 获取（带默认值兜底），不直接依赖具体实现。
