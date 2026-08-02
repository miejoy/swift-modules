# PushManager - 推送通知管理

处理 APNs 推送通知的框架模块，支持通知授权、分类注册、点击事件处理、应用内展示策略、静默推送内容拉取等。

> 配套文档：`overview.md`（模块索引）
> 最后验证：2026-08-02（已对齐源码）

---

## PushManager

**用途:** 处理 APNs 推送通知的完整生命周期管理

**核心类型:**
- `PushManager` — 推送管理单例（`final class`, `UNUserNotificationCenterDelegate`, `Sendable`），通过 `PushManager.shared` 访问
- `HandleInAppNotification` — 应用内通知展示策略枚举
- `NotificationHandler` — 内部通知处理类（按 category 管理 clickActions + inAppHandler + contentDeliverHandlers）
- `NotificationAppDelegate` — AppDelegate 协议（转发 deviceToken 回调给 PushManager）
- `ConfigKey.pushInjectAlertKey` — 注入弹框内容的子字典 key（默认 `"injectAlert"`）
- `ConfigKey.pushDefaultSceneId` — 推送弹框默认场景 ID（默认 `.main`）

**HandleInAppNotification 枚举:**
| 值 | 行为 |
|----|------|
| `.silent` | 静默推送，不展示，通过 `contentDeliverHandler` 处理 |
| `.banner` | 弹出推送横幅（默认） |
| `.sound` | 播放声音 |
| `.bannerWithSound` | 横幅 + 声音 |
| `.waitMoreContentArrived(options)` | 等待后台数据处理完成后决定展示，需 `content-available: 1` + `pushRecordId` |
| `.injectAlert(options)` | 注入弹框，点确定后触发点击事件 |
| `.treatAsClick(options)` | 直接当做点击推送处理 |

**授权与注册:**
```swift
// 一步完成：请求权限 + 注册远程通知（返回 deviceToken: Data）
let deviceToken = try await PushManager.shared.requestAuthorizationAndRegisterForRemoteNotifications()

// 或分两步：
let granted = try await PushManager.shared.requestAuthorization()
let token = try await PushManager.shared.registerForRemoteNotifications()

// deviceToken 更新回调（可在此上报到服务器）
PushManager.shared.deviceTokenUpdate = { token in
    // 上报 token 到服务器
}
```

> **AppDelegate 要求:** App 的 AppDelegate 必须继承 `NotificationAppDelegate`（否则 deviceToken 回调无法触发）。PushManager 会在首次调用时检查并 `LogFault` 警告。

**注册通知处理（按 category）:**
```swift
// 基础注册（仅指定应用内展示方式）
PushManager.shared.register(on: "message", inAppHandler: .banner)

// 注册 + 点击事件（TriggerableAsyncAction，TriggerData == UNNotification）
PushManager.shared.registerAction(
    on: "message",
    clickAction: ExecuteBlockAction { notification in
        // 处理点击
    },
    inAppHandler: .banner
)

// 注册 + 解码点击事件（TriggerData: Decodable，自动从 pushDetail 解码）
PushManager.shared.registerAction(
    on: "order",
    clickAction: OpenUrlAction(sceneId),
    inAppHandler: .treatAsClick(.banner)
)

// 注册 + 静默推送内容处理（需开启 remote-notification 后台模式）
PushManager.shared.register(
    on: "sync",
    inAppHandler: .silent,
    contentDeliverBlock: { (detail: SyncData) async throws -> Bool in
        // 处理静默推送内容，返回是否成功
        return true
    }
)

// 注销
PushManager.shared.unregisterAction(on: "message")
```

**内置 ClickAction:**

| Action | 说明 | TriggerData |
|--------|------|-------------|
| `OpenUrlAction` | 打开 URL（支持应用内 SFSafariViewController） | `OpenUrl`（Decodable，含 `url` + `openInApp`） |
| `ShowAlertAction` | 显示弹窗（从 pushDetail 读取 title/message，支持 confirm 后触发后续 action） | `UNNotification` |
| `ShowPageAction<T>` | 展示页面（`T: PushPresentableView`，从 pushDetail 解码 InitData） | `UNNotification` |
| `ExecuteBlockAction` | 执行自定义闭包 | `UNNotification` |

**PushPresentableView 协议:**
```swift
public protocol PushPresentableView: PresentableView & Sendable {
    static var pushCategory: String { get }
    static func makeInitData(_ data: Data?) -> InitData?
}

// 便捷注册（自动用 pushCategory 作为 category）
PushManager.shared.registerShowPage(type: MyPage.self, on: sceneId, inAppHandler: .banner)
```

**清理通知:**
```swift
PushManager.shared.clearAllDeliveredNotifications()
PushManager.shared.clearNotification(of: "message")
```

**静默推送处理:**
```swift
// 在 AppDelegate 的 application(_:didReceiveRemoteNotification:fetchCompletionHandler:) 中调用
Task {
    let success = try await PushManager.shared.didReceiveRemoteNotification(with: userInfo)
    completionHandler(success ? .newData : .failed)
}
```

**线程安全:** 所有属性读写通过 `DispatchQueue.syncOnPushQueue` 串行队列保护（`com.miejoy.push_queue`）。

**依赖:** TriggerableAction, Logger, AlertFlow, PresentFlow, AutoConfig, ViewFlow, DataFlow

**平台:** iOS 17+, macOS 14+, tvOS 17+, watchOS 10+
