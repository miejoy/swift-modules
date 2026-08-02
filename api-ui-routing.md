# UI 路由与导航 API

界面路由框架：导航栈（NavigationFlow）、模态呈现（PresentFlow）、弹窗（AlertFlow）、Toast（ToastFlow）、Window 管理（WindowFlow）。

> 配套文档：`overview.md`（模块索引）、`api-rsv.md`（ViewFlow 路由协议体系）
> 最后验证：2026-08-02（已对齐源码）

---

## 前置条件：主界面 Modifier 挂载

各 Flow 需要在主界面（或场景根视图）挂载对应的 ViewModifier，才能实际渲染导航栈、弹窗、模态呈现等 UI。Toast 和 Window 不需要 Modifier——Toast 通过 WindowFlow 自动管理独立窗口，Window 通过 Store 直接操作。

### 必须挂载的 Modifier

| Modifier | 模块 | 初始化参数 | 作用 |
|----------|------|-----------|------|
| `NavigationStackModifier` | NavigationFlow | `init(_ stackId:)` 或 `init(shared:)` | 渲染导航栈，绑定到指定 stackId |
| `AlertModifier` | AlertFlow | `init(level: UInt = 0)` | 渲染弹窗层，level 对应 present 层级 |
| `PresentModifier` | PresentFlow | `init()` | 渲染模态呈现层 |

### 完整挂载示例

```swift
struct MainView: View {
    var body: some View {
        TabView {
            NavigationRootView()
                .modifier(NavigationStackModifier(shared: .root))
                .tabItem { Label("Navigation", systemImage: "circle.grid.3x3") }

            PresentRootView()
                .tabItem { Label("Present", systemImage: "circle.grid.3x3") }

            AlertRootView()
                .tabItem { Label("Alert", systemImage: "circle.grid.3x3") }
        }
        .modifier(NavigationStackModifier(shared: .main))
        .modifier(AlertModifier())
        .modifier(PresentModifier())
        .registerPresentOn { presentCenter in
            presentCenter.registerPresentableView(SomeView.self, for: customRoute)
        }
        .registerPresentedModifier { content, sceneId, level in
            content
                .modifier(NavigationStackModifier("Level-\(level)-"))
                .modifier(AlertModifier(level: level))
        }
    }
}
```

### 挂载要点

- **NavigationStackModifier**：可挂载多个（不同 stackId），子视图可拥有独立导航栈；共享栈用 `init(shared:)`，普通栈用 `init(_:)`
- **AlertModifier**：每个 present 层级需独立挂载，通过 `level` 参数区分；根级 `level: 0`（默认值）
- **PresentModifier**：只需在最外层挂载一次，内部自动管理层级栈
- **registerPresentOn**：在 `onAppear` 时注册路由到 `PresentCenter`，内部通过 `CallId(function:line)` 去重，重复调用安全
- **registerPresentedModifier**：为所有 presented 视图追加额外 Modifier（如嵌套 Alert/Navigation），回调参数为 `(content, sceneId, level)`
- **ToastFlow**：无需 Modifier，`toastManager.show(message:)` 调用后自动通过 WindowFlow 创建窗口显示
- **WindowFlow**：无需 Modifier，通过 `Store<WindowSceneState>.shared(on:).showViewWithWindowIfNeed()` 直接操作窗口

---

## NavigationFlow - 导航栈管理

**用途:** 管理导航栈的 push/pop 操作，支持多导航堆栈和共享堆栈

**依赖:** data-flow, view-flow, module-monitor

**核心类型:**
- `NavigationManager` — 导航管理器（`@MainActor class`，按场景缓存于 `SceneState`，管理共享导航堆栈和路由注册表）
- `NavigationState` — 导航栈状态（`FullStorableViewState`，持有 `arrPaths: [NavigationPage]`）
- `NavigationAction` — 导航操作（push/pop/remove，静态方法构造）
- `NavigationStack` — SwiftUI 视图，渲染导航栈
- `NavigationStackId` / `SharedNavigationStackId` — 栈标识（共享栈可跨视图访问）

**环境变量:**
```swift
@Environment(\.navManager)   // NavigationManager（当前场景）
@Environment(\.navStack)     // Store<NavigationState>?（当前导航栈，Optional）
```

**PushableView 协议（定义在 navigation-flow）:**
```swift
public protocol PushableView: RoutableView, Sendable { }
public protocol VoidPushableView: PushableView, VoidInitializableView { }
```

**路由注册（View 扩展，onAppear 时自动注册，内部去重）:**
```swift
// 注册单个可推入视图（使用默认路由）
SomeView()
    .registerPushableView(SomeView.self)

// 注册到自定义路由
SomeView()
    .registerPushableView(SomeView.self, for: customRoute)

// 批量注册
SomeView()
    .registerPushOn { navManager in
        navManager.registerPushableView(FirstView.self)
        navManager.registerPushableView(SecondView.self, for: customRoute)
    }
```

**Push/Pop API（Store<NavigationState> 包装方法，自带动画）:**
```swift
// 通过环境变量获取 navStack
@Environment(\.navStack) var navStack

// Push 视图实例
navStack?.push(SomeView())

// Push 视图类型 + 数据
navStack?.push(SomeView.self, initData)
navStack?.push(SomeView.self)               // VoidInitizableView 无参

// 从根视图 push
navStack?.pushOnRoot(SomeView.self, initData)
navStack?.pushOnRoot(SomeView.self)

// Pop
navStack?.pop()              // 弹出 1 个（默认）
navStack?.pop(3)             // 弹出 3 个
navStack?.popToRoot()        // 弹到根

// Remove 指定路由（注意：可能导致意外动画，尽量少用）
navStack?.remove(with: someRoute)
```

**结果路由（async/await）:**
```swift
// push 带结果返回的路由
let result = try await navStack?.push(
    ResultViewRoute<InitData, ResultData>(), data
)
```

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

---

## PresentFlow - 模态呈现

**用途:** 管理模态弹出/消失，支持 sheet、fullScreenCover（iOS），支持多层级嵌套 present

**依赖:** data-flow, view-flow, module-monitor

**核心类型:**
- `PresentState` — 呈现状态（管理弹出层级栈）
- `PresentAction` — 呈现操作
- `PresentManager` = `Store<PresentState>` — 呈现管理器
- `PresentCenter` — 全局注册中心（类似 NavigationCenter）

**环境变量:**
```swift
@Environment(\.presentManager) // Store<PresentState>（当前场景）
@Environment(\.presentLevel)   // UInt（当前呈现层级，从 0 开始）
```

**PresentableView 协议（定义在 present-flow）:**
```swift
public protocol PresentableView: RoutableView { }
public protocol VoidPresentableView: PresentableView, VoidInitializableView { }
```

**路由注册（View 扩展，onAppear 时自动注册，内部去重）:**
```swift
// 注册单个可呈现视图（使用默认路由）
SomeView()
    .registerPresentableView(SomeView.self)

// 注册到自定义路由
SomeView()
    .registerPresentableView(SomeView.self, for: customRoute)

// 批量注册
SomeView()
    .registerPresentOn { presentCenter in
        presentCenter.registerPresentableView(FirstView.self)
        presentCenter.registerPresentableView(SecondView.self, for: customRoute)
    }

// 为所有 presented 视图追加额外 Modifier（如嵌套 Alert/Navigation）
SomeView()
    .registerPresentedModifier { content, sceneId, level in
        content
            .modifier(NavigationStackModifier("Level-\(level)-"))
            .modifier(AlertModifier(level: level))
    }
```

**Present API:**
```swift
@Environment(\.presentManager) var presentManager

// Present 视图实例
presentManager.present(SomeView())

// Present 视图类型 + 数据
presentManager.present(SomeView.self, initData)
presentManager.present(VoidPresentableView.self)  // 无参

// Present 路由
presentManager.present(ViewRoute<InitData>(), data)
presentManager.present(ViewRoute<Void>())

// Present 路由数据
presentManager.present(routeData)

// 全屏覆盖（iOS/tvOS/watchOS only）
presentManager.presentFullCover(SomeView.self, initData)

// 结果路由（async/await）
let result = try await presentManager.present(
    ResultViewRoute<InitData, ResultData>(), data
)
let result = try await presentManager.present(
    ResultViewRoute<Void, ResultData>()  // 无参版本
)

// 全屏结果路由
let result = try await presentManager.presentFullCover(
    ResultViewRoute<InitData, ResultData>(), data
)

// Dismiss
presentManager.dismissTopView()        // 消失最顶层
presentManager.dismissViewOnLevel(2)   // 消失指定层级
presentManager.dismissToRootView()     // 消失到根
```

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

---

## AlertFlow - 弹窗管理

**用途:** 管理弹窗的显示和消失，支持三种弹窗类型（强/普通/弱），支持中断机制

**依赖:** view-flow, module-monitor

**核心类型:**
- `AlertState` — 弹窗状态（管理弹窗栈，支持多层级）
- `AlertManager` = `Store<AlertState>` — 弹窗管理器
- `AlertInfo` — 弹窗信息（标题/消息/按钮/输入框/自定义内容）
- `AlertType` — 弹窗类型（`.strong` / `.normal` / `.weak`）
- `AlertButtonInfo` — 弹窗按钮
- `AlertTextFieldInfo` — 弹窗输入框
- `InterruptInfo` — 中断信息（用于绑定 UI 状态与弹窗中断）
- `AlertResult` / `AlertResultButtonInfo` — 带结果返回的弹窗

**环境变量:**
```swift
@Environment(\.alertManager)  // Store<AlertState>（当前场景）
```

**弹窗类型说明:**
| 类型 | 行为 |
|------|------|
| `.strong` | 强弹窗，不可被中断，不可被其他弹窗覆盖（包括其他强弹窗） |
| `.normal` | 普通弹窗，可被中断，可被其他弹窗覆盖 |
| `.weak` | 弱弹窗，可被中断，被中断直接销毁；显示时如存在其他弹窗/中断则直接销毁 |

**API:**
```swift
@Environment(\.alertManager) var alertManager

// 显示弹窗（返回 UUID）
let alertId = alertManager.showAlert("标题", "消息", [
    AlertButtonInfo(title: "确定", action: { ... }),
    AlertButtonInfo.cancelButton(title: "取消")
])

// 强弹窗
alertManager.showStrongAlert("重要通知", "内容")

// 弱弹窗（可能返回 nil——如被其他弹窗/中断挤掉）
let id = alertManager.showWeakAlert("推广信息")

// 带输入框
alertManager.showAlert("登录", "请输入密码", [], [
    AlertTextFieldInfo(title: "密码", text: $password)
])

// 自定义内容
let id = alertManager.showAlert(AlertInfo(
    title: "自定义",
    message: "",
    contentMaker: { info in MyCustomAlertView(info) }
))

// 销毁
alertManager.dismissAlert(with: alertId)

// 中断绑定（将 Binding<Bool> 关联到视图路径，弹窗显示时自动中断）
let binding = alertManager.bindingWithInterrupt($showSheet, viewPath, "sheetInterrupt")
```

**带结果的弹窗（AlertManager+Async）:**
```swift
// async/await 方式等待用户选择
enum LoginAlertResult: AlertResult {
    case confirm, cancel
    static var cancel: Self { .cancel }
}

let result = try await alertManager.showAlertForResult(
    "登录",
    "确认登录？",
    buttons: [
        AlertResultButtonInfo(title: "确认", result: .confirm),
        AlertResultButtonInfo.cancelButton(title: "取消")
    ]
)
// result == .confirm 或 .cancel（用户取消时）
```

**平台:** iOS 17+, macOS 14+, tvOS 17+, watchOS 10+

---

## WindowFlow - Window 管理

**用途:** 管理独立 Window 的创建、显示和隐藏，支持跨平台（iOS/macOS），是 AlertFlow/ToastFlow 等浮层的基础设施

**依赖:** data-flow, view-flow, logger

**核心类型:**
- `WindowSceneState` — 场景 Window 管理状态（`FullSceneWithIdSharableState`，维护 `windowId → AppWindow` 映射）
- `WindowSceneAction` — Window 操作（`.bindWith` / `.showViewWithWindowIfNeed` / `.hideWindowOfViewIfNeed`）
- `WindowOperableState` — 可操作 Window 的状态协议（ToastState/AlertState 等遵循）
- `WindowWithViewOperableState` — 带关联视图类型的 Window 状态协议
- `WindowSceneInfo` — 平台场景信息（iOS: `windowScene`/`sceneSession`，macOS: `parentWindow`）
- `WindowHideAnimation` — 消失动画（`.none` / `.fadeOut` / `.slideDown` / `.custom`）

**跨平台类型别名:**
```swift
// iOS
AppWindow = UIWindow
AppKeyWindow = UIWindow
AppWindowLevel = UIWindow.Level
AppHostingController = UIHostingController

// macOS
AppWindow = NSPanel
AppKeyWindow = NSWindow
AppWindowLevel = NSWindow.Level
AppHostingController = NSHostingController
```

**WindowOperableState 协议:**
```swift
public protocol WindowOperableState: SceneWithIdSharableState {
    var sceneId: SceneId { get }
    var windowLevel: AppWindowLevel { get }        // 默认 .normal
    var windowId: ObjectIdentifier { get }          // 唯一标识
    var hideAnimation: WindowHideAnimation { get }  // 默认 .none
    @MainActor func makeView() -> AnyView           // 构建根视图
    @MainActor func modify(_ window: AppWindow)     // 配置 Window（默认空操作）
}

// 带视图类型的便利协议（windowId/makeView 自动推导）
public protocol WindowWithViewOperableState: WindowOperableState {
    associatedtype WindowView: VoidInitializableView
}
```

**Store 扩展 API（任何遵循 WindowOperableState 的 State）:**
```swift
// 显示 Window（如已存在则取消隐藏）
store.showWindowIfNeed()

// 隐藏 Window（如不存在则无操作）
store.hideWindowIfNeed()
```

**直接操作 WindowSceneState:**
```swift
// 通过视图类型显示 Window
Store<WindowSceneState>.shared(on: sceneId).showViewWithWindowIfNeed(MyView())

// 通过 windowId 显示 Window（适用于无法推断视图类型的场景）
Store<WindowSceneState>.shared(on: sceneId).showViewWithWindowIfNeed(
    windowId, AnyView(MyView()), windowLevel
)

// 隐藏指定视图类型的 Window
Store<WindowSceneState>.shared(on: sceneId).hideWindowOfViewIfNeed(MyView.self)

// 带动画隐藏
Store<WindowSceneState>.shared(on: sceneId).hideWindowOfViewIfNeed(windowId, animation: .fadeOut())
```

**平台绑定:**
```swift
// iOS: 在 SceneDelegate 中绑定场景信息
Store<WindowSceneState>.shared(on: sceneId).apply(action: .bindWith(
    WindowSceneInfo(windowScene: windowScene, sceneSession: session)
))

// macOS: 在 AppDelegate 中绑定父窗口
Store<WindowSceneState>.shared(on: sceneId).apply(action: .bindWith(
    WindowSceneInfo(parentWindow: mainWindow)
))
```

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

---

## ToastFlow - Toast 提示

**用途:** 显示短暂消息提示，自动消失，支持自定义样式

**依赖:** window-flow, auto-config

**核心类型:**
- `ToastState` — Toast 状态（`WindowOperableState`，管理 Toast 窗口生命周期）
- `ToastManager` = `Store<ToastState>` — Toast 管理器
- `ToastView` — 默认 Toast 视图
- `CustomToastView` — 自定义 Toast 视图协议
- `ConfigKey.toastSecondOnDisplay` — 显示时长（默认 2.5s，可配置）
- `ConfigKey.toastSecondOnDisappearing` — 消失动画时长（默认 0.5s，可配置）

**环境变量:**
```swift
@Environment(\.toastManager)  // Store<ToastState>（当前场景）
```

**API:**
```swift
@Environment(\.toastManager) var toastManager

// 显示 Toast（连续调用只显示最后一条）
toastManager.show(message: "操作成功")

// 注册自定义 Toast 样式
toastManager.registerToastView(MyCustomToastView())
```

> **实现机制:** Toast 通过 `WindowFlow` 创建独立 Window（`windowLevel = .statusBar + 1`），显示在所有内容之上。内部用 `showCount` 保证只显示最后一条消息。`ToastState` 遵循 `WindowOperableState`，自动管理窗口的创建/销毁。

**平台:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

---

## 路由系统总览

| 模块 | 管理器类型 | 环境变量 | 平台 |
|------|-----------|---------|------|
| NavigationFlow | `Store<NavigationState>` / `NavigationManager` | `\.navManager` / `\.navStack` | iOS 16+ |
| PresentFlow | `Store<PresentState>` | `\.presentManager` / `\.presentLevel` | iOS 16+ |
| AlertFlow | `Store<AlertState>` | `\.alertManager` | iOS 17+ |
| ToastFlow | `Store<ToastState>` | `\.toastManager` | iOS 16+ |
| WindowFlow | `Store<WindowSceneState>` | `\.window` | iOS 16+ |

**路由注册中心:**
- `NavigationCenter.shared` — 导航路由全局注册
- `PresentCenter.shared` — 呈现路由全局注册
- 两者都支持 `registerPushableView` / `registerPresentableView`（在视图初始化时调用）
