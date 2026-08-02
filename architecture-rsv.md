# RSV 架构实现指南

RSV (Resource-State-View) 架构模式的应用实现方案，展示如何使用 swift-modules 框架构建完整业务应用。

> 最后验证：2026-08-03（已对齐源码）

## RSV 架构核心概念

**Resource-State-View** 是 MieJoy 框架推荐的架构模式：

- **Resource**：资源层，通过 `LoadableResource` 协议声明可加载资源，由 `ResourceCenter` 统一路由到 `ResourceLoader` 加载（文件、网络等）
- **State**：数据层，定义状态结构和 Action，使用 DataFlow 管理
- **View**：SwiftUI 视图，纯粹的 UI 渲染，通过 `@SharedState` 订阅状态

### 数据流

```
User Interaction
    ↓ send Action
View ──→ Reducer ──→ State 更新 ──→ View 自动刷新
    ↑                    │
    └────────────────────┘
              @SharedState 自动订阅

异步操作：
Reducer ──→ 异步任务 ──→ dispatch Action ──→ State 更新

Resource 加载：
Resource.open() ──→ ResourceCenter 路由 ──→ ResourceLoader 加载 ──→ AsyncStream<Response>
```

### 三层职责

| 层 | 职责 | 框架支持 |
|------|------|---------|
| **View** | UI 渲染、用户交互 → 发送 Action | `@SharedState` / `@ViewState` / ViewFlow |
| **State** | 状态结构定义、Reducer 处理逻辑 | DataFlow (`Store` / `Action` / `Reducer`) |
| **Resource** | 声明式资源加载（文件/网络等） | `LoadableResource` / `ResourceCenter` / `ResourceLoader` |

---

## 一、State 定义模式

### 1.1 AppState - 全局根状态

框架已内置 `AppState`，定义在 DataFlow 中，作为所有子 State 的根：

```swift
// 框架内置定义（无需自己实现）
public struct AppState: StateContainable, SharableState {
    public var subStates: [String: StorableState] = [:]
    public typealias UpState = Never
    public init() {}
}
```

子 State 通过 `typealias UpState = AppState` 声明归属关系，DataFlow 框架自动管理层级。

### 1.2 SharedState - 跨视图共享状态

每个子 State 通过 `typealias UpState = AppState` 声明挂载到根状态。以用户认证状态为例：

```swift
// States/Auth/AuthState.swift

enum AuthAction: Action {
    case login(String, String)       // 用户名, 密码
    case loginSuccess
    case loginFailed(AuthError)      // Error 需为 Sendable 类型
    case logout
}

struct AuthState: FullSharableState {
    typealias UpState = AppState
    typealias BindAction = AuthAction
    
    var isLoggedIn: Bool = false
    var isLoggingIn: Bool = false
    var loginError: AuthError?
    
    static func loadReducers(on store: Store<AuthState>) {
        store.register { (state, action: AuthAction) in
            switch action {
            case .login(let username, let password):
                state.isLoggingIn = true
                state.loginError = nil
                // 异步任务完成后 dispatch 结果
                Task {
                    do {
                        let success = try await AuthService.login(username, password)
                        Store<AuthState>.shared.dispatch(action: .loginSuccess)
                    } catch {
                        Store<AuthState>.shared.dispatch(action: .loginFailed(.networkError(error)))
                    }
                }
                
            case .loginSuccess:
                state.isLoggedIn = true
                state.isLoggingIn = false
                
            case .loginFailed(let error):
                state.isLoggingIn = false
                state.loginError = error
                
            case .logout:
                state.isLoggedIn = false
            }
        }
    }
}
```

> **注意**：`Action` 协议要求 `Sendable`，`case` 中的关联值类型也必须满足 `Sendable`。`Error` 协议本身不满足 `Sendable`，需用具体的 `enum` Error 类型并标记 `Sendable`。

### 1.3 多个子 State 的组织

每个功能模块定义独立的 State，通过 `UpState` 挂载到 `AppState`：

```swift
// States/Settings/SettingsState.swift
enum SettingsAction: Action {
    case toggleDarkMode
    case changeLanguage(String)
}

struct SettingsState: FullSharableState {
    typealias UpState = AppState
    typealias BindAction = SettingsAction
    
    var isDarkMode: Bool = false
    var language: String = "zh-Hans"
    
    static func loadReducers(on store: Store<SettingsState>) {
        store.register { (state, action: SettingsAction) in
            switch action {
            case .toggleDarkMode:
                state.isDarkMode.toggle()
            case .changeLanguage(let lang):
                state.language = lang
            }
        }
    }
}
```

子 State 无需手动注册——访问 `Store<AuthState>.shared` 时框架自动调用 `loadReducers` 并挂载到父层级。

### 协议继承关系

```
StorableState (Sendable)
├── StateContainable           ← AppState 实现
└── AttachableState            ← 子 State 实现（需指定 UpState: StateContainable）
    └── SharableState          ← 跨视图共享状态（含 InitializableState）
        └── FullSharableState  ← SharableState + ReducerLoadableState + ActionBindable

ViewFlow 中的视图状态：
StorableViewState: AttachableState (UpState == SceneState)
FullStorableViewState: StorableViewState + ReducerLoadableState + ActionBindable
```

---

## 二、View 连接 State

### 2.1 使用 @SharedState 访问状态

```swift
struct HomeView: View {
    @SharedState private var authState: AuthState
    @SharedState private var settingsState: SettingsState
    
    var body: some View {
        VStack {
            if authState.isLoggedIn {
                ContentView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(settingsState.isDarkMode ? .dark : .light)
    }
}
```

### 2.2 发送 Action 的三种方式

```swift
// 方式 1: send - 用户操作触发的事件
$authState.send(action: .login(username, password))

// 方式 2: dispatch - 异步操作完成后发送事件
Store<AuthState>.shared.dispatch(action: .loginSuccess)

// 方式 3: apply - 同步执行另一个事件（在某个事件处理过程中需要嵌套触发时使用）
Store<SettingsState>.shared.apply(action: .toggleDarkMode)
```

- **`send`** — 用户交互产生的事件，如点击按钮、输入文本等，从 View 层发出
- **`dispatch`** — 异步任务（网络请求、定时器等）完成后将结果以 Action 形式发送回 Store
- **`apply`** — 在 Reducer 处理某个 Action 的过程中，需要同步触发另一个 Action 时使用

### 2.3 ViewState - 视图私有状态

只有该视图使用的短期状态，不与其他视图共享：

```swift
struct ListViewState: StorableViewState, InitializableState {
    var displayMode: DisplayMode = .list
    var isSelectionMode: Bool = false
    var selectedIds: Set<String> = []
}

struct ListView: View {
    @SharedState private var dataState: DataState
    @ViewState private var viewState: ListViewState  // 视图私有状态
    
    var body: some View {
        VStack {
            Picker("Display", selection: $viewState.displayMode) {
                Text("列表").tag(DisplayMode.list)
                Text("网格").tag(DisplayMode.grid)
            }
            .pickerStyle(.segmented)
            
            if viewState.isSelectionMode {
                Text("已选择 \(viewState.selectedIds.count) 项")
            }
        }
    }
}
```

---

## 三、Resource 层实现

Resource 层通过 `LoadableResource` 协议声明可加载资源，`ResourceCenter` 根据资源类别路由到对应的 `ResourceLoader`。

### 3.1 定义资源

```swift
// Resources/UserResource.swift

struct UserResource: LoadableResource {
    static var category: ResourceCategory { .web }
    
    typealias ExtraData = Void
    typealias Response = User
    
    // open() 默认通过 ResourceCenter 路由到对应 ResourceLoader
    // 无需自己实现 open(with:)，框架提供默认扩展
}
```

### 3.2 实现 ResourceLoader

```swift
// Resources/UserResourceLoader.swift

final class UserResourceLoader: ResourceLoader {
    static let categories: Set<ResourceCategory> = [.web]
    
    func load<Resource: LoadableResource>(
        _ resource: Resource,
        with extraData: Resource.ExtraData
    ) async throws -> AsyncStream<Resource.Response> {
        return AsyncStream { continuation in
            // 执行实际加载逻辑
            let user = try? await APIClient.fetchUser()
            if let user = user {
                continuation.yield(user as! Resource.Response)
            }
            continuation.finish()
        }
    }
}
```

### 3.3 注册并使用

```swift
// 启动时注册 Loader
ResourceCenter.shared.registerLoader(UserResourceLoader())

// 在 Reducer 中使用
case .loadUser:
    state.isLoading = true
    Task {
        do {
            // openOnce 只取第一个值并返回
            let user = try await UserResource().openOnce()
            Store<UserState>.shared.dispatch(action: .userLoaded(user))
        } catch {
            Store<UserState>.shared.dispatch(action: .loadFailed)
        }
    }
```

### Resource 体系核心 API

| 组件 | 职责 |
|------|------|
| `LoadableResource` | 资源声明协议，定义 `category` / `ExtraData` / `Response` |
| `ResourceCategory` | 资源类别（`.file` / `.web` / `.custom(String)`） |
| `ResourceLoader` | 加载器协议，实现具体加载逻辑 |
| `ResourceCenter` | 全局路由中心，`registerLoader` 注册、`load` 路由 |
| `open(with:)` | 持续监听，返回 `AsyncStream<Response>` |
| `openOnce(with:)` | 只取第一个值即返回 |

---

## 四、异步操作模式

Reducer 中需要执行异步操作时的标准模式：

```swift
enum DataAction: Action {
    case loadData
    case dataLoaded([Item])
    case loadFailed(DataError)
    case saveItem(Item)
    case saveSuccess
}

struct DataState: FullSharableState {
    typealias UpState = AppState
    typealias BindAction = DataAction
    
    var items: [Item] = []
    var isLoading: Bool = false
    var error: DataError?
    
    static func loadReducers(on store: Store<DataState>) {
        store.register { (state, action: DataAction) in
            switch action {
            case .loadData:
                state.isLoading = true
                state.error = nil
                // 发起异步任务，完成后 dispatch 结果
                Task {
                    do {
                        let items = try await DataService.fetchAll()
                        Store<DataState>.shared.dispatch(action: .dataLoaded(items))
                    } catch {
                        Store<DataState>.shared.dispatch(action: .loadFailed(.fetchFailed(error)))
                    }
                }
                
            case .dataLoaded(let items):
                state.items = items
                state.isLoading = false
                
            case .loadFailed(let error):
                state.isLoading = false
                state.error = error
                
            case .saveItem(let item):
                Task {
                    do {
                        try await DataService.save(item)
                        Store<DataState>.shared.dispatch(action: .saveSuccess)
                    } catch {
                        Store<DataState>.shared.dispatch(action: .loadFailed(.saveFailed(error)))
                    }
                }
                
            case .saveSuccess:
                // 保存成功后同步触发重新加载
                Store<DataState>.shared.apply(action: .loadData)
            }
        }
    }
}
```

**要点**：
- Reducer 中只发起异步任务，不阻塞等待结果
- 异步完成后用 `dispatch` 发送结果 Action
- 需要在 Reducer 中链式触发另一个 Action 时用 `apply`
- Action 的关联值类型必须满足 `Sendable`

---

## 五、最佳实践

### 5.1 何时使用 SharedState vs ViewState

| 场景 | 使用 | 说明 |
|------|------|------|
| 多个视图需要访问 | SharedState | 如登录状态、全局设置 |
| 单个视图的 UI 临时状态 | ViewState | 如表单输入值、选中模式 |
| 需要跨模块传递 | SharedState | 如语言选择影响全局 UI |
| 与业务逻辑相关 | SharedState | 如数据列表、加载状态 |

### 5.2 Action 设计原则

```swift
// ✅ 清晰、具体、携带数据
enum DataAction: Action {
    case loadData
    case dataLoaded([Item])       // 结果反映在 payload
    case saveItem(Item)           // 清晰的意图
    case saveFailed(DataError)    // 错误信息完整
}

// ❌ 避免含糊、无数据的 Action
enum BadAction: Action {
    case update                    // 含糊不清
    case processing                // 不携带数据
    case error                     // 信息不完整
}
```

### 5.3 异步操作原则

```swift
// ✅ Reducer 中发起异步任务，完成后 dispatch 结果
case .loadData:
    state.isLoading = true
    Task {
        let result = try await DataService.fetch()
        Store<DataState>.shared.dispatch(action: .dataLoaded(result))
    }

// ❌ 不要在 Reducer 中阻塞等待
case .loadData:
    state.isLoading = true
    let data = try await DataService.fetch()  // ❌ 阻塞 Reducer
    state.isLoading = false
```

---

## 参考

- MieJoy DataFlow: https://github.com/miejoy/data-flow
- MieJoy ViewFlow: https://github.com/miejoy/view-flow
- MieJoy ResourceLoadable: https://github.com/miejoy/resource-loadable
