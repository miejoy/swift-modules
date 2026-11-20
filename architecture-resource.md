# Resource 层设计指南（RSV 的 R）

RSV 架构中 **Resource** 层的完整设计哲学、识别方法、拆分粒度与实践模式。

> 配套文档：`architecture-rsv.md`（RSV 整体架构）、`api-rsv.md`（ResourceLoadable API 细节）
> 源码：`miejoy/resource-loadable`

---

## 一、Resource 是什么

### 核心定义

> **任何可以从非内存位置加载的东西，都可以定义为资源。**

「加载」这个动作 = 把非内存的东西搬进内存并返回。

非内存位置包括但远不止文件和网络：

| 来源 | 示例资源 |
|------|---------|
| 文件系统 | 配置文件、缓存、日志、沙盒文档 |
| 网络 | REST 接口、WebSocket 推送、下载 |
| 系统服务 | 定位、通知权限、蓝牙、健康数据 |
| 设备信息 | 设备型号、系统版本、电量、网络状态 |
| 用户数据 | 相册、通讯录、剪贴板 |
| 持久化 | UserDefaults、Keychain、数据库 |
| 传感器 | 陀螺仪、加速度计、麦克风电平 |
| 三方 SDK | 内购商品列表、广告物料、推送 token |

### 识别判定

```
这个数据/能力是异步获取的吗？
├─ 是 → 优先定义成 Resource（几乎无例外）
└─ 否 → 它来自内存之外吗（文件/系统/设备）？
    ├─ 是 → 也可以定义成 Resource（同步资源）
    └─ 否 → 纯内存计算，不是 Resource
```

**口诀：凡是异步的，先想能不能定义成 Resource。**

一个 App 定义**几十到上百个 `ResourceCategory` 是正常的**，不要吝啬。

### 不是 Resource 的东西

- 纯内存计算（排序、过滤、格式化）
- State 内部的派生值（computed property）
- UI 状态（选中项、展开折叠）

---

## 二、分层职责：State 向下只对接 Resource

**这是 Resource 层最重要的约定。**

```
View ──→ State ──→ Resource ──→ ResourceCenter ──→ ResourceLoader ──→ 外部世界
                     ↑
              State 向下的唯一出口
```

State 需要外部数据时，**不直接调 Service / SDK / URLSession**，而是 `open` 一个 Resource：

```swift
// ❌ State 直接调 Service，依赖硬编码，无法替换、难以测试
case .loadUser:
    state.isLoading = true
    Task {
        let user = try await AuthService.fetchUser()      // 直接依赖具体实现
        Store<UserState>.shared.dispatch(action: .userLoaded(user))
    }

// ✅ State 通过 Resource 取数据，依赖收敛到一个可替换的点
case .loadUser:
    state.isLoading = true
    Task {
        do {
            let user = try await UserResource().openOnce(with: userId)
            Store<UserState>.shared.dispatch(action: .userLoaded(user))
        } catch {
            Store<UserState>.shared.dispatch(action: .loadFailed(.fetch))
        }
    }
```

**收益**：State 的所有外部依赖都变成「声明一个 Resource」，实现细节完全隔离在 Loader 里。

> 尽量让 State 里所有 `LoadableResource` 都通过统一入口取数据，不要一半走 Resource 一半直连 Service。

---

## 三、Category 与 Loader：多对一

这是最容易搞混的一点。

| 概念 | 是什么 | 粒度 | 数量级 |
|------|-------|------|-------|
| `ResourceCategory` | **数据切面** — 一次具体的加载语义 | 细 | 几十到上百 |
| `ResourceLoader` | **实现载体** — 处理一组 Category 的实际逻辑 | 粗 | 几个到几十个 |

**一个 Loader 可以处理多个 Category。**

### 同一功能拆多个 Category

同一个功能下的不同数据获取，应该拆成不同 Category：

**例：定位功能**

| Category | 语义 | 返回 |
|----------|------|------|
| `.custom("location.permission")` | 请求定位权限 | 权限状态（一次性） |
| `.custom("location.updates")` | 持续监听位置变化 | 位置流（持续推送） |
| `.custom("location.once")` | 获取当前位置一次 | 单次位置 |

三个 Category，但**同一个 `LocationLoader`** 负责它们的读取和返回。

**例：内购功能**

| Category | 语义 |
|----------|------|
| `.custom("iap.products")` | 拉取商品列表 |
| `.custom("iap.purchase")` | 发起购买 |
| `.custom("iap.restore")` | 恢复购买 |
| `.custom("iap.transactions")` | 监听交易更新（持续） |

四个 Category，一个 `IAPLoader`。

### 拆分原则

**按「返回什么数据」拆 Category，按「谁来实现」拆 Loader。**

- 返回的数据类型或语义不同 → 不同 Category
- 底层依赖同一个 SDK / 同一套连接 / 同一份内部状态 → 同一个 Loader

### Category 命名

`ResourceCategory` 是 enum，业务侧统一用 `.custom(String)` 扩展：

```swift
// 框架内置
public enum ResourceCategory: Hashable, Sendable {
    case unknown
    case file
    case web
    case custom(String)
}
```

业务侧集中定义静态常量，**避免裸写字符串**。Category 常量按性质分两处定义：

### 业务 ResourceCategory → `Constants.swift`

与 ViewRoute 路由定义并列，放主工程 `Constants.swift`。这类 Category 对应的 Loader 可替换升级，属于项目级业务资源：

```swift
// Constants.swift
extension ResourceCategory {
    // MARK: - 用户
    static let userProfile = ResourceCategory.custom("user.profile")
    static let userLogin   = ResourceCategory.custom("user.login")

    // MARK: - 内购
    static let iapProducts = ResourceCategory.custom("iap.products")
    static let iapPurchase = ResourceCategory.custom("iap.purchase")
}
```

### 功能性 ResourceCategory → 对应 Ability 文件

与底层能力强绑定、不可替代的模块（如定位、设备信息），Category 常量和 Loader 都定义在对应 Ability 文件里，内聚在一起：

```swift
// LocationAbility.swift（Ability 模块内）
extension ResourceCategory {
    static let locationPermission = ResourceCategory.custom("location.permission")
    static let locationUpdates    = ResourceCategory.custom("location.updates")
}

// Loader 也在同一文件，通过 Ability 的 load 方法自动注册（见下文「注册」）
```

命名建议：`<功能域>.<具体语义>`，点分隔，全小写。

---

## 四、定义 Resource

`LoadableResource` 只有一个方法 `open`，且框架已提供默认实现（路由到 `ResourceCenter`），**业务侧通常不需要实现它**：

```swift
public protocol LoadableResource {
    static var category: ResourceCategory { get }   // 匹配 Loader
    associatedtype ExtraData                        // 传入参数，无参用 Void
    associatedtype Response: Sendable               // 返回类型

    func open(with extraData: ExtraData) async throws -> AsyncStream<Response>
}
```

### 无参资源

```swift
struct DeviceInfoResource: LoadableResource {
    static var category: ResourceCategory { .deviceInfo }
    typealias ExtraData = Void
    typealias Response = DeviceInfo
    // open 用框架默认实现，无需自己写
}

// 使用
let info = try await DeviceInfoResource().openOnce()
```

### 带参资源

```swift
struct UserResource: LoadableResource {
    static var category: ResourceCategory { .web }
    typealias ExtraData = String            // userId
    typealias Response = User
}

let user = try await UserResource().openOnce(with: "u_123")
```

### 持续监听资源

```swift
struct LocationUpdatesResource: LoadableResource {
    static var category: ResourceCategory { .locationUpdates }
    typealias ExtraData = LocationAccuracy
    typealias Response = Coordinate
}

// open 返回 AsyncStream，持续接收
for await coord in try await LocationUpdatesResource().open(with: .best) {
    Store<LocationState>.shared.dispatch(action: .locationUpdated(coord))
}
```

### open vs openOnce

| 方法 | 语义 | 适用 |
|------|------|------|
| `open(with:)` | 返回 `AsyncStream<Response>`，**持续推送** | 位置监听、交易监听、WebSocket、文件监听 |
| `openOnce(with:)` | 只取流的第一个值即返回 | 接口请求、读文件、取设备信息、权限请求 |

`ExtraData == Void` 时有无参便利方法 `open()` / `openOnce()`。

> `openOnce` 在流未推任何值就结束时抛 `LoadResourceError.noValueReceiveWhenCompletion`。

---

## 五、实现 ResourceLoader

### 形态：单例 + 优先 actor

`ResourceLoader` 协议要求 `AnyObject, Sendable`，方法是 `async`，**actor 天然满足**。

- **一般都是单例** — 一个 Loader 对应一套外部依赖（一个 SDK、一个连接池）
- **优先用 actor** — Loader 内部通常有可变状态（CLLocationManager、连接、缓存），actor 自动保证并发安全
- 无内部状态时可用 `final class ... : Sendable`

### 单 Category Loader

```swift
actor UserLoader: ResourceLoader {
    static let categories: Set<ResourceCategory> = [.web]
    static let shared = UserLoader()
    private init() {}

    func load<Resource: LoadableResource>(
        _ resource: Resource,
        with extraData: Resource.ExtraData
    ) async throws -> AsyncStream<Resource.Response> {
        guard let userId = extraData as? String else {
            throw LoadResourceError.resourceTypeError
        }
        let user = try await APIClient.fetchUser(userId)
        guard let response = user as? Resource.Response else {
            throw LoadResourceError.resourceTypeError
        }
        return AsyncStream { continuation in
            continuation.yield(response)
            continuation.finish()
        }
    }
}
```

### 多 Category 共用一个 Loader

**在 `load` 内部按 `Resource.category` 分支**：

```swift
actor LocationLoader: ResourceLoader {
    static let categories: Set<ResourceCategory> = [
        .locationPermission,
        .locationUpdates,
        .locationOnce,
    ]
    static let shared = LocationLoader()

    private let manager = CLLocationManager()   // 三个 Category 共用同一个 manager
    private init() {}

    func load<Resource: LoadableResource>(
        _ resource: Resource,
        with extraData: Resource.ExtraData
    ) async throws -> AsyncStream<Resource.Response> {
        switch Resource.category {
        case .locationPermission:
            return try await requestPermission()
        case .locationUpdates:
            return try await startUpdates(with: extraData)
        case .locationOnce:
            return try await fetchOnce()
        default:
            throw LoadResourceError.resourceTypeError
        }
    }

    // 各 Category 的具体实现拆成私有方法
    private func requestPermission<R: Sendable>() async throws -> AsyncStream<R> { /* ... */ }
    private func startUpdates<R: Sendable>(with extraData: Any) async throws -> AsyncStream<R> { /* ... */ }
    private func fetchOnce<R: Sendable>() async throws -> AsyncStream<R> { /* ... */ }
}
```

**这样拆的好处**：三个资源共享 `CLLocationManager` 实例和权限状态，不用在多个 Loader 间同步状态。

### 注册

Loader 注册分两种模式：

#### 模式一：LaunchManager 手动注册（业务 Loader）

可替换升级的业务 Loader，在 `LaunchManager.appInit()` 中手动注册：

```swift
// LaunchManager.swift
func appInit() {
    // ...
    ResourceCenter.shared.registerLoader(UserLoader.shared)
    ResourceCenter.shared.registerLoader(IAPLoader.shared)
    ResourceCenter.shared.registerLoader(NetworkLoader.shared)
}
```

#### 模式二：Ability 自动注册（功能性 Loader）

不可替代的功能性模块（如定位），通过 `AbilityProtocol.load` 方法自动注册。Ability 经主工程 `UserConfig` 注册后，`load` 方法会被自动调用，在 `load` 内注册对应 ResourceLoader：

```swift
// LocationAbility.swift（Ability 模块内）
actor LocationLoader: ResourceLoader {
    static let categories: Set<ResourceCategory> = [.locationPermission, .locationUpdates]
    // ...
}

// Ability 注册时 load 自动调用
func load() {
    ResourceCenter.shared.registerLoader(LocationLoader.shared)
}
```

**测试时用另一个 mock Loader 覆盖注册即可**，测试是独立流程，不会触发 Ability 的 `load`，互不影响。

`registerLoader` 会把 `Loader.categories` 里的所有 Category 都指向该 Loader。

---

## 六、设计目的一：可测试

**换掉 Loader 就能 mock 整个数据来源。**

这是 Resource 层设计的核心收益之一。

### 为什么方便

State 只认 Resource，Resource 只认 Category，Category 由谁实现是运行时注册的。所以：

> 单元测试只需注册一个 mock Loader，就能模拟该功能的所有场景，**被测的 State 和 View 代码一行不改**。

### 示例：模拟定位

```swift
// 测试专用 Loader，覆盖定位相关的所有 Category
actor MockLocationLoader: ResourceLoader {
    static let categories: Set<ResourceCategory> = [
        .locationPermission,
        .locationUpdates,
        .locationOnce,
    ]

    // 测试场景可配置
    var permissionGranted: Bool = true
    var mockCoordinates: [Coordinate] = []
    var shouldFail: Bool = false

    func load<Resource: LoadableResource>(
        _ resource: Resource,
        with extraData: Resource.ExtraData
    ) async throws -> AsyncStream<Resource.Response> {
        if shouldFail { throw LoadResourceError.resourceTypeError }
        switch Resource.category {
        case .locationPermission:
            // 返回预设的权限状态
        case .locationUpdates:
            // 按 mockCoordinates 逐个 yield，模拟位置移动
        default:
            throw LoadResourceError.resourceTypeError
        }
    }
}

@Suite
struct LocationStateTests {

    @Test
    @MainActor
    func permissionDeniedShowsGuide() async throws {
        let mock = MockLocationLoader()
        await mock.setPermissionGranted(false)
        ResourceCenter.shared.registerLoader(mock)   // 覆盖注册

        Store<LocationState>.shared.send(action: .requestPermission)
        // 验证 State 走到了引导用户开权限的分支
    }
}
```

### 重复注册的语义

`ResourceCenter.registerLoader` 对已注册的 Category **直接覆盖**，同时向 `ResourceMonitor` 记一条 `duplicateRegistration` 事件。

| 场景 | 期望 |
|------|------|
| **正常运行** | 一个 Category 只应有一个 Loader。`duplicateRegistration` 事件是**告警信号** — 说明注册重复了，可能有两个 Loader 抢同一个资源，需要排查 |
| **单元测试** | 走的是独立流程，覆盖注册 mock 是**正常操作**，忽略该事件即可 |

> 换句话说：防重入检查是为了**保护正常运行时**不出现两个 Loader 争抢同一资源，不是为了阻止测试替换。测试和运行是两条独立流程，各自注册各自的 Loader。

---

## 七、设计目的二：可替换、可升级

**同一个 Category，实现可以随时换掉，上层零改动。**

典型演进路径（以网络为例）：

| 阶段 | Loader 实现 | 上层改动 |
|------|-----------|---------|
| 初期 | 框架默认的 `NetworkAbility` 实现 | — |
| 中期 | 换成第三方库（Alamofire 等）的 Loader | **零** |
| 后期 | 自己完全重写一套（自定义连接池、重试、缓存策略） | **零** |

其他场景：
- 定位从 CoreLocation 换成第三方 SDK
- 内购从 StoreKit 1 升级到 StoreKit 2
- 文件存储从沙盒改成 iCloud
- 本地缓存从 UserDefaults 换成 SQLite

只要 Category 和 `Response` 类型不变，换 Loader 即完成升级。

**这也是不要吝啬 Category 的理由**：Category 划得细，替换的粒度就细，可以只换一部分实现。

---

## 八、与 Ability 体系的关系

框架里有两套「可替换实现」的机制，容易混淆：

| 机制 | 替换的是什么 | 调用方 | 典型代表 |
|------|------------|-------|---------|
| **Ability** | **通用能力的实现** | 任何代码 | `NetworkAbility`（怎么发 HTTP）、`LatestResourceAbility`、`SafeStorage`、`Message` |
| **Resource** | **一次具体的数据加载** | 主要是 State | `UserResource`（拉哪个用户的信息） |

**层次关系**：Resource 在上，Ability 在下。

```
State ──→ UserResource ──→ UserLoader ──→ Ability.http.request(...) ──→ 网络
          （加载什么数据）    （怎么加载）     （用什么发请求）
```

- **Loader 内部可以用 Ability** — `NetworkLoader` 用 `Ability.http` 发请求，这样网络驱动本身也可替换
- **不要混用** — State 不应该直接调 `Ability.http`，而应该 open 一个 Resource；Ability 是 Loader 的实现细节

MJ 业务模块（`MJWebInterface` / `MJLatestResource` / `MJDevice` / `MJStoreKit` 等）都属于 **R 层范畴的能力提供方**。
在 State 里用它们时，建议包一层 Resource：

```swift
// ❌ State 直连 MJWebInterface
Task {
    let users = try await GetUserListRequest(page: 1, pageSize: 20).openOnce()
}

// ✅ 包一层 Resource，Loader 内部用 MJWebInterface
struct UserListResource: LoadableResource {
    static var category: ResourceCategory { .userList }
    typealias ExtraData = PageParam
    typealias Response = [UserInfo]
}

actor UserLoader: ResourceLoader {
    static let categories: Set<ResourceCategory> = [.userList, .userProfile]
    // load 内部调 GetUserListRequest(...).openOnce()
}
```

---

## 九、实践清单

设计一个功能时，按顺序过：

1. **列出所有外部数据/能力获取点** — 凡是异步的都列出来
2. **每个点定义一个 Category** — 按「返回什么数据」拆，别怕多
3. **集中定义 Category 常量** — 业务类放 `Constants.swift`（与 ViewRoute 并列），功能性类放对应 Ability 文件
4. **定义 Resource struct** — 声明 `category` / `ExtraData` / `Response`，`open` 用默认实现
5. **归组 Loader** — 底层依赖相同的 Category 归到一个 Loader，`actor` + 单例
6. **Loader 内按 `Resource.category` 分支** — 各 Category 实现拆私有方法
7. **注册 Loader** — 业务 Loader 在 `LaunchManager.appInit()` 手动注册；功能性 Loader 在 Ability `load` 中自动注册
8. **State 只调 Resource** — 不直连 Service/SDK
9. **测试写 mock Loader** — 覆盖注册，模拟各种场景

---

## 十、常见坑

| 坑 | 后果 |
|----|------|
| State 直连 Service / URLSession / SDK | 依赖硬编码，无法 mock，无法替换实现 |
| 一个 Category 塞多种返回语义 | `Response` 类型要用枚举包一层，调用方还得解包，替换粒度也变粗 |
| 每个 Category 都建一个 Loader | 同功能的内部状态（manager、连接）无法共享，需要跨 Loader 同步 |
| 裸写 `.custom("xxx")` 字符串 | 拼错无编译期检查，没有自动补全，全局找不到有哪些资源 |
| Loader 用 class 且内部有可变状态没加锁 | 并发访问数据竞争（用 actor 就没这问题） |
| 该用 `open` 的用了 `openOnce` | 只拿到第一个值，后续更新收不到（位置、交易监听等） |
| 只把网络当 Resource | 定位、权限、设备信息、相册这些也应该是 Resource，漏了就退化成到处直连 SDK |

---

## 参考

- MieJoy ResourceLoadable: https://github.com/miejoy/resource-loadable
- `api-rsv.md` — ResourceLoadable API 速查
- `architecture-rsv.md` — RSV 整体架构
- `ability-system.md` — `NetworkAbility` / `LatestResourceAbility` 等能力协议
