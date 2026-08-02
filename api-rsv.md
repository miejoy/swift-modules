# RSV 架构 API (DataFlow + ViewFlow + ResourceLoadable)

RSV 架构的核心框架 API：状态管理（DataFlow）、视图绑定（ViewFlow）、资源加载协议（ResourceLoadable）。

> 配套文档：`overview.md`（模块索引）、`architecture-rsv.md`（RSV 架构指南）
> 最后验证：2026-08-02（已对齐源码）

---

## DataFlow - 数据状态管理

**用途:** RSV 架构的 State 层，定义应用状态如何存储、变更、传递

**核心概念:**
- `Action` - 状态变更指令（枚举，遵循 `Action: Sendable` 协议）
- `Store<T>` - 全局状态管理器 (`@MainActor ObservableObject`，`@dynamicMemberLookup`)
- `Reducer` - 状态变更逻辑 (`@MainActor (inout State, Action) -> Void`)

**协议继承体系:**
```
StorableState              ← 基础状态协议（Sendable，有 stateId）
├── InitializableState     ← 可无参初始化（init()）
├── StateContainable       ← 可容纳子状态（subStates 字典）
├── AttachableState        ← 可挂载到父状态（associatedtype UpState: StateContainable）
│   └── SharableState      ← 可跨视图共享（UpState: SharableState，默认 AppState）
│       └── FullSharableState ← 完整共享状态（+ ReducerLoadableState + ActionBindable）
ReducerLoadableState       ← 可自动加载 Reducer（loadReducers 由框架在 didBoxed 时自动调用）
ActionBindable             ← 可绑定默认 Action（associatedtype BindAction: Action）
```

**关键说明:**
- `FullSharableState = SharableState + ReducerLoadableState + ActionBindable`，定义 `typealias BindAction` 和 `static func loadReducers(on:)` 后，框架自动注册 reducer
- `Store<T>.shared` — 全局单例 Store，按 `ObjectIdentifier(State.self)` 缓存在 `s_mapSharedStore`，首次创建时自动 `attachToUpStore` 挂载到父状态

**基础使用:**
```swift
// 定义状态和 Action
enum AuthAction: Action {
    case login(String, String)
    case loginSuccess(User)
    case loginFailed(Error)
}

struct AuthState: FullSharableState {
    typealias UpState = AppState  // 挂载到根状态
    typealias BindAction = AuthAction
    
    var isLoggedIn: Bool = false
    var user: User?
    var error: Error?
    
    static func loadReducers(on store: Store<AuthState>) {
        store.register { state, action in
            switch action {
            case .login(let email, let password):
                // 发起登录请求
                AuthService.login(email: email, password: password) { result in
                    switch result {
                    case .success(let user):
                        store.dispatch(action: .loginSuccess(user))
                    case .failure(let error):
                        store.dispatch(action: .loginFailed(error))
                    }
                }
            case .loginSuccess(let user):
                state.isLoggedIn = true
                state.user = user
            case .loginFailed(let error):
                state.error = error
            }
        }
    }
}
```

**Action 三种调用方式:**

| 方法 | 场景 | 线程要求 | 示例 |
|------|------|---------|------|
| `send` | 用户直接操作（按钮点击等） | 必须主线程 | `$state.send(action: .login(email, pwd))` |
| `apply` | Reducer 中调用其他 Store | 必须主线程 | `Store<OtherState>.shared.apply(action: .xxx)` |
| `dispatch` | 异步回调/后台任务完成后通知 | **不限线程**（内部自动切主线程） | `Store<AuthState>.shared.dispatch(action: .loginSuccess(user))` |

```swift
// View 层：用户点击按钮
$authState.send(action: .login(email, password))

// Reducer 中：通知其他 State
Store<NotificationState>.shared.apply(action: .showBanner("登录成功"))

// 异步回调/后台线程：网络请求完成后
Task {
    let user = try await AuthService.login(email, password)
    Store<AuthState>.shared.dispatch(action: .loginSuccess(user))
}
```

> **注意：** 异步操作（网络请求、Keychain、文件IO等）不要直接在 Reducer 闭包中执行结果赋值。应该在 Service/View 层执行完后，通过 `dispatch` 回调通知 State。

> **`observe` 注意事项：**
> - 纯回调版 `observe(store:callback:)` 中，若 `callback` 捕获了 `self`，必须使用 `[weak self]` 避免循环引用（持有链：`store → observers → callback → self`）。
> - 带 Action 版 `observe(store:callback:) -> A?` 内部已用 `[weak self]`，无需额外处理。
> - B 释放后会自动清理 A 的观察记录（`mapCancellable`），无需手动 `unobserve`。
> - 仍支持手动调用 `unobserve(store:)` / `unobserveAll(store:)` 提前取消观察。

> **`addDestroyCallback` 注意：** 可多次调用，所有回调在 Store deinit 时依次执行（替代旧的 `setDestroyCallback`，支持多回调）。

> **Store 防重入设计：** Reducer 执行途中若触发新 action（如 `dispatch`），不会递归执行，而是排队到 `pendingActions`。当前 reduce 完成后 `popLast` 取出继续处理，保证状态变更串行。

> **Store 直接赋值：** `store.state = newValue` 和 `store[keyPath] = newValue` 也可直接修改状态（走 `updateStateWithNotify`），但 strictMode 下会 fatalError，推荐统一用 action。

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

**依赖:** module-monitor

---

## ViewFlow - 视图数据绑定

**用途:** SwiftUI 视图与 DataFlow 的连接层，提供响应式绑定

**核心 PropertyWrapper:**
- `@SharedState` - 跨视图共享状态订阅（`State: SharableState`，内部用 `@ObservedObject` + `SharedStoreStorage`）
- `@ViewState` - 视图私有状态（`State: StorableViewState`，内部用 `@StateObject` + `ViewStateWrapperStorage`）

**视图状态协议体系:**
```
StorableState
└── AttachableState (UpState: StateContainable)
    └── StorableViewState (UpState == SceneState)   ← @ViewState 要求的协议
        └── FullStorableViewState                   ← + ReducerLoadableState + ActionBindable

StorableState
└── AttachableState
    └── SharableState (UpState: SharableState)      ← @SharedState 要求的协议
        └── FullSharableState                        ← + ReducerLoadableState + ActionBindable
```

**刷新机制:**
两个包装器内部都有一个 `@Published var refreshTrigger: Bool = false`。Store 状态变化时通过 `addObserver` 回调 toggle `refreshTrigger`，触发 `ObservableObject.objectWillChange` → SwiftUI 视图刷新。

**`@SharedState` 细节:**
- 普通 `SharableState` → `Store.shared`（全局单例）
- `SceneSharableState` → `Store.shared(on: sceneId)`（场景级，通过 `SceneSharedStoreContainer` 缓存）
- `projectedValue` 返回 `Store<State>`，所以 `$authState.send(action:)` 拿到的是 Store

**`@ViewState` 细节:**
- `Store.box(state)` 创建临时 Store（非共享，生命周期由 SwiftUI `@StateObject` 管理）
- `configIfNeed` 绑定 sceneId/viewPath，触发 `State.didAddStoreToView(store)` → 自动 `loadReducers`
- 若 `recordViewState` 开启，注册到 `SceneState` 的 `ViewStateContainer`，支持生命周期追踪

**使用示例:**
```swift
struct LoginView: View {
    @SharedState private var authState: AuthState
    @ViewState private var form: LoginForm  // 视图私有状态
    
    var body: some View {
        VStack {
            TextField("Email", text: $form.email)
            SecureField("Password", text: $form.password)
            
            Button("Login") {
                // 发送 Action 到共享状态
                $authState.send(action: .login(form.email, form.password))
            }
            
            if let error = authState.error {
                Text(error.localizedDescription).foregroundColor(.red)
            }
        }
        .disabled(authState.isLoggedIn)
    }
}
```

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

**依赖:** data-flow, module-monitor

---

### RoutableView 协议体系（路由导航核心）

ViewFlow 提供了一套完整的 View 协议体系，用于支持路由导航、参数传递和视图追踪：

#### 协议继承关系
```swift
// 基础协议
protocol TrackableView: View {
    associatedtype Content: View
    @ViewBuilder @MainActor var content: Self.Content { get }
    var trackId: String { get }  // 默认 = 类名
}

// 初始化参数协议
protocol InitializableView: View {
    associatedtype InitData: Sendable
    @MainActor init(_ data: InitData)
    static func makeInitializeData(from: Any) -> InitData?  // 默认返回 nil
}

protocol VoidInitializableView: InitializableView where InitData == Void {
    @MainActor init()  // 无参初始化
}

// 核心 RoutableView（通用路由基础，提供 defaultRoute 和 RouteWrapperView）
protocol RoutableView: TrackableView, InitializableView { }
protocol VoidRoutableView: RoutableView, VoidInitializableView { }

// PushableView（导航栈压入，定义在 navigation-flow，非 view-flow）
protocol PushableView: RoutableView, Sendable { }
protocol VoidPushableView: PushableView, VoidInitializableView { }

// PresentableView（模态展示，定义在 present-flow，非 view-flow）
protocol PresentableView: RoutableView { }
protocol VoidPresentableView: PresentableView, VoidInitializableView { }
```

#### 协议选择原则

**核心判断：该视图是否需要被 push（导航栈压入）或 present（模态弹出）打开？**

| 调用方式 | 使用协议 |
|---------|--------|
| 通过 `NavigationLink` / `navStack.push()` 打开，**无参数** | `VoidPushableView` |
| 通过 `NavigationLink` / `navStack.push()` 打开，**有参数** | `PushableView` |
| 通过 `.fullScreenCover` / `.sheet` / `presentManager.present()` 打开，**无参数** | `VoidPresentableView` |
| 通过 `.fullScreenCover` / `.sheet` / `presentManager.present()` 打开，**有参数** | `PresentableView` |
| 状态驱动直接内嵌（`Group`/`if`/`switch`），**不被 push/present** | `VoidRoutableView` 或普通 `View` |
| 子组件（Cell、Overlay 等） | 普通 `View`，**不需要路由协议** |

> **常见误区：** 首页、根视图等通过条件分支直接显示的视图**不需要** `PushableView` 或 `PresentableView`，只需 `VoidRoutableView` 或普通 `View`。只有真正被 push/present 打开的视图才继承对应协议。

#### 使用示例

**1. 无参数、状态驱动显示（VoidRoutableView）**
```swift
// 首页等直接显示的根视图，不需要 push/present
struct HomeView: VoidRoutableView {
    var content: some View {
        VStack {
            Text("Home")
        }
    }
}
// internal 类型无需显式实现 init()，协议 extension 提供默认实现
// public 类型需显式声明 public init() {}
```

**2. 无参数、通过 present 弹出（VoidPresentableView）**
```swift
struct SettingsView: VoidPresentableView {
    var content: some View { /* ... */ }
}
// 注册后使用 .fullScreenCover 或 presentManager.present() 打开
```

**3. 带参数、通过 push 打开（PushableView）**
```swift
// 参数结构体必须遵循 Sendable
struct DetailParam: Sendable {
    let itemId: String
    let title: String
}

struct DetailView: PushableView {
    let itemId: String
    let title: String
    
    init(_ param: DetailParam) {
        self.itemId = param.itemId
        self.title = param.title
    }
    
    var content: some View {
        VStack {
            Text(title)
            Text("ID: \(itemId)")
        }
    }
}
```

**4. 绑定参数 View（支持 @Binding）**
```swift
struct EditParam: Sendable {
    @Binding var value: String
}

struct EditView: PushableView {
    @Binding var value: String
    
    init(_ param: EditParam) {
        self._value = param.$value
    }
    
    var content: some View {
        TextField("Edit", text: $value)
    }
}
```

#### 视图注册方式

**方式 1：Modifier 注册（推荐，在 onAppear 自动触发）**
```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                // 注册 PushableView（使用默认路由）
                .registerPushOn { navManager in
                    navManager.registerDefaultPushableView(HomeView.self)
                    navManager.registerDefaultPushableView(DetailView.self)
                }
                // 注册 PresentableView
                .registerPresentOn { presentCenter in
                    presentCenter.registerDefaultPresentableView(LoginView.self)
                    presentCenter.registerDefaultPresentableView(SettingsView.self)
                }
        }
    }
}
```

**方式 2：直接调用 NavigationManager/PresentCenter**
```swift
// NavigationManager 中注册
let navManager = NavigationManager.shared(on: sceneId)
navManager.registerDefaultPushableView(HomeView.self)
navManager.registerDefaultPushableView(DetailView.self, for: .init("custom_route"))

// PresentCenter 中注册
let presentCenter = Store<PresentState>.shared(on: sceneId).presentCenter
presentCenter.registerDefaultPresentableView(LoginView.self)
```

#### 视图存储位置规范

参考 DemoApp 的目录组织（项目地址见 `SKILL.md`）：

```
DemoApp/Views/
├── MainView.swift              # 主界面（根视图）
├── ViewCenter.swift            # 路由注册中心
│
├── Navigation/                 # 导航功能模块
│   ├── NavigationRootView.swift    # 模块主视图（VoidRoutableView）
│   ├── PushFirstView.swift         # 可推入视图（PushableView）
│   ├── PushSecondView.swift        # 可推入视图（带参数）
│   └── ...
│
├── Present/                    # 模态呈现模块
│   ├── PresentRootView.swift       # 模块主视图
│   ├── PresentFirstView.swift      # 可呈现视图（PresentableView）
│   └── ...
│
├── Alert/                      # 弹窗模块
│   ├── AlertRootView.swift         # 模块主视图
│   └── SecondAlertView.swift       # 子弹窗视图
│
├── Keychain/                   # Keychain 功能模块
│   └── KeychainRootView.swift      # 模块主视图
│
└── Notification/               # 通知功能模块（含 State）
    ├── NotificationRootView.swift  # 模块主视图
    ├── NotificationDetailView.swift # 子视图
    ├── NotificationState.swift     # 状态定义
    └── NotificationManager.swift   # 业务逻辑
```

**规则：**
- **按功能模块分目录**：每个功能模块一个目录（如 `Navigation/`、`Present/`、`Alert/`），模块内主视图命名为 `XxxRootView`
- **可路由视图**：直接放在模块目录内，根据调用方式选择协议（push → `PushableView`，present → `PresentableView`，直接显示 → `VoidRoutableView` 或 `View`）
- **子视图**：直接放在模块目录内，**不遵循路由协议**，就是普通 `View`
- **State 与 Manager**：可与视图同目录放（如 `Notification/`），也可单独放 `States/` 目录

#### 注册检重机制

框架自动防止重复注册：
```swift
// 同一路由只能注册一次，重复注册会 fatalError
let route = ViewRoute<DetailParam>("DetailView")
navManager.registerPushableView(DetailView.self, for: route)
navManager.registerPushableView(DetailView.self, for: route)  // ❌ Fatal error!
```

#### 可返回结果的路由（ResultableRouteData）

界面在关闭时把结果返回给调用方，调用方用 `async throws` 等待。适用于选择器、确认弹窗、编辑页等「打开界面 → 拿到用户输入 → 继续流程」的场景。

**核心类型（`ViewFlow/Base/ResultableRouteData.swift`、`ViewFlow/View/ResultableView.swift`）：**

| 类型 | 说明 |
|------|------|
| `ResultableRouteData<InitData, ResultData>` | 路由数据，携带 `initData` 与结果回调句柄；提供 `finishRoute(_:)` / `cancelRoute()` / `failRoute(reason:)` |
| `ResultViewRoute<InitData, ResultData>` | `ViewRoute<ResultableRouteData<InitData, ResultData>>` 的 typealias |
| `ResultableView` | 界面协议，`InitData == ResultableRouteData<InitParam, ResultData>` |
| `VoidResultableView` | `ResultableView where InitParam == Void` |
| `ViewResult<ResultData>` | `.finished(data)` / `.cancelled` / `.failed(reason:)`；`get()` 抛错、`resultToResultData()` 转 `Result` |
| `ViewRouteError` | `.cancelled` / `.failed(reason:)` |
| `CancellableRouteData` | 路由管理方用来 cancel/fail 的协议，`ResultableRouteData` 已实现 |

**1. 定义可返回结果的界面**

```swift
// InitParam = 传入参数类型，ResultData = 返回结果类型
struct ItemPickerView: PushableView, ResultableView {
    typealias InitParam = [Item]
    typealias ResultData = [Item]

    @Environment(\.dismiss) var dismiss
    @State private var selected: [Item] = []

    let routeData: ResultableRouteData<[Item], [Item]>

    init(_ routeData: ResultableRouteData<[Item], [Item]>) {
        self.routeData = routeData
    }

    var content: some View {
        List(routeData.initData, id: \.id) { item in
            // ... 选择逻辑
        }
        .toolbar {
            Button("完成") {
                routeData.finishRoute(selected)   // 1. 先返回结果
                dismiss()                         // 2. 再关闭界面
            }
        }
    }
}

// 无参数版本用 VoidResultableView
struct ConfirmView: PresentableView, VoidResultableView {
    typealias ResultData = Bool
    // InitParam == Void，routeData 类型为 ResultableRouteData<Void, Bool>
    let routeData: ResultableRouteData<Void, Bool>
    init(_ routeData: ResultableRouteData<Void, Bool>) { self.routeData = routeData }
    // ...
}
```

**2. 注册（和普通路由完全一致）**

```swift
// PushableView
navManager.registerDefaultPushableView(ItemPickerView.self)
// PresentableView
presentCenter.registerDefaultPresentableView(ConfirmView.self)
```

**3. 调用方等待结果（async throws）**

```swift
// NavigationFlow — Store<NavigationState> 扩展
@Environment(\.navStack) var navStack

Button("选择") {
    Task {
        do {
            let picked = try await navStack.push(ItemPickerView.defaultRoute, items)
            // 用户点了「完成」，picked 是返回的结果
        } catch ViewRouteError.cancelled {
            // 用户侧滑返回 / pop
        } catch ViewRouteError.failed(let reason) {
            // 路由未注册 / baseOn 不存在 / initData 类型不匹配
        }
    }
}

// baseOn 可选，指定基于哪个界面 push
let picked = try await navStack.push(ItemPickerView.defaultRoute, items, baseOn: HomeView.defaultRoute.eraseToAnyRoute())

// PresentFlow — Store<PresentState> 扩展
@Environment(\.presentManager) var presentManager

let picked = try await presentManager.present(ItemPickerView.defaultRoute, items)
let ok     = try await presentManager.present(ConfirmView.defaultRoute)   // InitParam == Void

// iOS/tvOS/watchOS 还有 fullCover 版本
let picked = try await presentManager.presentFullCover(ItemPickerView.defaultRoute, items)
```

**关键约定：**

- **回调有且仅有一次**：`ResultHandle` 用 `DispatchQueue.syncOnStoreQueue` 取出即置空，`finishRoute` 之后再 `cancelRoute` 是 no-op，连续两次 `finishRoute` 也只回调一次
- **deinit 兜底**：路由管理方漏调 cancel/fail 时，`ResultHandle.deinit` 会回调 `.cancelled`，防止调用方永久挂起
- **界面关闭统一用 `@Environment(\.dismiss)`**：对 sheet 和 NavigationStack push 都有效，界面无需知道自己是被 present 还是 push
- **`ResultData == Void`** 时有便利方法 `finishRoute()`（无参）
- 普通 `ViewRouteData` 可调 `cancelRouteIfNeeded()` / `failRouteIfNeeded(reason:)`，对非 `CancellableRouteData` 是 no-op

**路由管理方自动触发 cancel/fail 的场景：**

| 场景 | 结果 |
|------|------|
| `navStack.pop()` / `popToRoot()` / `remove(with:)` | `.cancelled` |
| `navStack.push(_, baseOn:)` 清除上方 page | 被清除的 page → `.cancelled` |
| `presentManager.dismissTopView()` / `dismissViewOnLevel()` / `dismissToRootView()` | `.cancelled` |
| 用户侧滑返回 / 下拉关闭 sheet | `.cancelled` |
| 路由未注册 | `.failed(reason:)` |
| `baseOn` 指定的路由不在栈中 | `.failed(reason:)` |
| initData 类型与注册的界面不匹配 | `.failed(reason:)` |

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

---

## ResourceLoadable - 可加载资源协议

**用途:** 定义可加载资源的统一协议，RSV 架构中 Resource 层的基础协议

**核心协议:** `LoadableResource`（注意：协议名是 `LoadableResource`，模块名为 `ResourceLoadable`）

```swift
public protocol LoadableResource {
    static var category: ResourceCategory { get }     // 资源类别，匹配 ResourceLoader
    associatedtype ExtraData                            // 传入额外数据（Void 时有无参便利方法）
    associatedtype Response: Sendable                   // 返回数据类型

    func open(with extraData: ExtraData) async throws -> AsyncStream<Response>
}
```

**核心 API:**

| API | 说明 |
|-----|------|
| `ResourceCategory` | 资源类别（用于匹配 `ResourceLoader`） |
| `ResourceCenter.shared` | 资源调度中心，单例 |
| `ResourceLoader` | 资源加载器协议，按 `ResourceCategory` 注册到 `ResourceCenter` |
| `ResourceMonitor` | 资源加载监控 |
| `resource.open(with:)` | 打开资源，返回 `AsyncStream<Response>` 持续推送 |
| `resource.openOnce(with:)` | 打开资源只取第一个值 |
| `resource.open()` / `resource.openOnce()` | `ExtraData == Void` 时的无参便利方法 |
| `LoadResourceError` | 加载错误（含 `.noValueReceiveWhenCompletion`） |

**使用示例:**
```swift
// 1. 定义资源
struct UserProfileResource: LoadableResource {
    static let category = ResourceCategory("user_profile")
    typealias ExtraData = String  // userId
    typealias Response = UserProfile

    func open(with userId: String) async throws -> AsyncStream<UserProfile> {
        // 实际由 ResourceLoader 处理，这里通常不需要直接实现
    }
}

// 2. 调用
let profile = try await UserProfileResource().openOnce(with: "user_123")
```

**依赖:** module-monitor

**平台:** iOS 15+, macOS 12+, tvOS 15+, watchOS 8+
