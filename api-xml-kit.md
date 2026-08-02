# XMLKit - XML 处理

XML 解析与处理工具框架，提供完整的 `Codable` 兼容的 XML 编码/解码能力，支持属性映射、兄弟元素数组、纯文本绑定等特性。

> 配套文档：`overview.md`（模块索引）
> 最后验证：2026-08-02（已对齐源码）

---

## XMLKit

**用途:** XML 解析与处理，提供与 `JSONEncoder`/`JSONDecoder` 对等的 `XMLEncoder`/`XMLDecoder`，支持 `Codable` 自动编解码

**核心类型:**
- `XMLDecoder` — XML 解码器（`open class`），遵循标准 `Decoder` 协议
- `XMLEncoder` — XML 编码器（`open class`），遵循标准 `Encoder` 协议，支持 Combine `TopLevelEncoder`
- `XMLHeader` — XML 头部（`<?xml version="1.0" encoding="UTF-8"?>`）
- `Attr<Value>` — 属性包装器，绑定 XML 标签属性
- `Plaintext<Value>` — 属性包装器，绑定 XML 标签纯文本内容
- `Brothers<Value>` — 属性包装器，绑定同名兄弟元素数组
- `_XMLParser` — 内部 XML 解析器（基于 `XMLParser`/`XMLParserDelegate`，支持 CDATA）
- `_XMLElement` — 内部 XML 元素模型（name/value/attributes/children）

**属性包装器:**

| 包装器 | 用途 | 示例 |
|--------|------|------|
| `@Attr<Value>` | 绑定 XML 标签**属性**（支持 Optional） | `<user id="123"/>` → `@Attr var id: Int` |
| `@Plaintext<Value>` | 绑定 XML 标签**纯文本内容**（支持 Optional） | `<name>张三</name>` → `@Plaintext var name: String` |
| `@Brothers<Value>` | 绑定**同名兄弟元素数组**（空时返回 `[]`） | `<item/><item/>` → `@Brothers var items: [Item]` |

> **三个包装器都支持 Optional 类型**，内部通过 `_AnyOptionalType` 协议判断是否为 Optional，解码时遇到 nil 正确处理。

**XMLDecoder 策略:**

| 策略 | 选项 | 默认值 |
|------|------|--------|
| `dateDecodingStrategy` | `.deferredToDate` / `.secondsSince1970` / `.millisecondsSince1970` / `.iso8601` / `.formatted(DateFormatter)` / `.custom` | `.deferredToDate` |
| `dataDecodingStrategy` | `.deferredToData` / `.base64` / `.custom` | `.base64` |
| `elementNameDecodingStrategy` | `.useDefaultKeys` / `.convertFromSnakeCase` / `.lowercaseFirstLetter` / `.custom` | `.useDefaultKeys` |
| `attrNameDecodingStrategy` | 同上 | `.useDefaultKeys` |

**XMLEncoder 策略:**

| 策略 | 选项 | 默认值 |
|------|------|--------|
| `outputFormatting` | `.prettyPrinted` / `.sortedAttrs` | `[]` |
| `dateEncodingStrategy` | `.deferredToDate` / `.secondsSince1970` / `.iso8601` / `.formatted` / `.custom` | `.deferredToDate` |
| `dataEncodingStrategy` | `.deferredToData` / `.base64` / `.custom` | `.base64` |
| `elementNameEncodingStrategy` | `.useDefaultKeys` / `.convertToSnakeCase` / `.uppercaseFirstLetter` / `.custom` | `.useDefaultKeys` |
| `attrNameEncodingStrategy` | 同上 | `.useDefaultKeys` |
| `arrayIndexKeyStrategy` | `.defaultIndexPrefix` / `.useTypeName` / `.customPrefix(String)` | `.defaultIndexPrefix` |

> **数组编码策略：** XML 没有原生数组概念，`XMLEncoder` 通过 `arrayIndexKeyStrategy` 决定数组元素的标签名。默认 `.defaultIndexPrefix` 生成 `<Index0>` / `<Index1>`，也可用类名或自定义前缀。

**使用示例:**
```swift
// 1. 定义 Codable 模型
struct User: Codable {
    @Attr var id: Int
    @Attr var name: String
    @Attr var age: Int?
    @Plaintext var bio: String
    @Brothers var tags: [String]
}

// 2. 编码
let encoder = XMLEncoder()
encoder.outputFormatting = .prettyPrinted
let xmlData = try encoder.encode(user, withRootKey: "User", header: XMLHeader(version: 1.0, encoding: "UTF-8"))
// 输出:
// <?xml version="1.0" encoding="UTF-8"?>
// <User id="123" name="张三" age="25">
//     <bio>开发者</bio>
//     <tags>swift</tags>
//     <tags>ios</tags>
// </User>

// 3. 解码
let decoder = XMLDecoder()
decoder.dateDecodingStrategy = .iso8601
let user = try decoder.decode(User.self, from: xmlData)

// 4. Combine 支持（TopLevelEncoder/TopLevelDecoder）
extension XMLDecoder: TopLevelDecoder { ... }
extension XMLEncoder: TopLevelEncoder { ... }
```

**XML 转义:** 自动处理 `&` / `<` / `>` / `'` / `"` 五种特殊字符转义。

**依赖:** (无)（构建时可选 SwiftLint 插件，通过 `DISABLE_SWIFTLINT=1` 环境变量跳过）

**平台:** macOS 12+（仅声明 macOS，实际通过 `FoundationXML` 支持各平台）
