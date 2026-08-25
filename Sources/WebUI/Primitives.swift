import Foundation

// MARK: - Horizontal Alignment
public enum HorizontalAlignment: Sendable {
    case leading
    case center
    case trailing
    public var cssValue: String {
        switch self {
        case .leading:  return "flex-start"
        case .center:   return "center"
        case .trailing: return "flex-end"
        }
    }
}
public enum VerticalAlignment: Sendable {
    case top
    case center
    case bottom
    public var cssValue: String {
        switch self {
        case .top:    return "flex-start"
        case .center: return "center"
        case .bottom: return "flex-end"
        }
    }
}

// MARK: - Text
public struct Text: View {
    public let content: String
    public init(_ content: String) {
        self.content = content
    }

    public func render() -> String {
        htmlEscape(content)
    }
}

// MARK: - Raw
public struct Raw: View {
    public let content: String
    public init(_ content: String) {
        self.content = content
    }

    public func render() -> String {
        content
    }
}

// MARK: - Div
public struct Div: View {
    public let id: String?
    public let `class`: String?
    public let children: [any View]
    public init(
        id: String? = nil,
        class: String? = nil,
        @ViewBuilder content: () -> [any View]
    ) {
        self.id = id
        self.class = `class`
        self.children = content()
    }

    public func render() -> String {
        var html = "<div"
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        html += ">"
        for child in children {
            html += child.render()
        }
        html += "</div>"
        return html
    }
}

// MARK: - Span
public struct Span: View {
    public let id: String?
    public let `class`: String?
    public let children: [any View]
    public init(
        id: String? = nil,
        class: String? = nil,
        @ViewBuilder content: () -> [any View]
    ) {
        self.id = id
        self.class = `class`
        self.children = content()
    }

    public func render() -> String {
        var html = "<span"
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        html += ">"
        for child in children {
            html += child.render()
        }
        html += "</span>"
        return html
    }
}

// MARK: - Button
public struct Button: View {
    public let label: String
    public let id: String?
    public let `class`: String?
    public let type: ButtonType
    public let disabled: Bool
    public let name: String?
    public enum ButtonType: String, Sendable {
        case submit = "submit"
        case button = "button"
        case reset = "reset"
    }
    public init(
        _ label: String,
        id: String? = nil,
        class: String? = nil,
        type: ButtonType = .submit,
        disabled: Bool = false,
        name: String? = nil
    ) {
        self.label = label
        self.id = id
        self.class = `class`
        self.type = type
        self.disabled = disabled
        self.name = name
    }

    public func render() -> String {
        var html = "<button"
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        if let name { html += " name=\"\(htmlEscape(name))\"" }
        html += " type=\"\(type.rawValue)\""
        if disabled { html += " disabled" }
        html += ">\(htmlEscape(label))</button>"
        return html
    }
}

// MARK: - Input Type
public enum InputType: String, Sendable {
    case button
    case checkbox
    case color
    case date
    case datetimeLocal = "datetime-local"
    case email
    case file
    case hidden
    case image
    case month
    case number
    case password
    case radio
    case range
    case reset
    case search
    case submit
    case tel
    case text
    case time
    case url
    case week
}

// MARK: - Input
public struct Input: View {
    public let id: String?
    public let name: String?
    public let placeholder: String
    public let type: InputType
    public let value: String
    public let disabled: Bool
    public let required: Bool
    public let attributes: [(String, String)]
    public init(
        id: String? = nil,
        name: String? = nil,
        placeholder: String = "",
        type: InputType = .text,
        value: String = "",
        disabled: Bool = false,
        required: Bool = false,
        attributes: [(String, String)] = []
    ) {
        self.id = id
        self.name = name
        self.placeholder = placeholder
        self.type = type
        self.value = value
        self.disabled = disabled
        self.required = required
        self.attributes = attributes
    }

    public func render() -> String {
        var html = "<input"
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        if let name { html += " name=\"\(htmlEscape(name))\"" }
        html += " type=\"\(type.rawValue)\""
        if !placeholder.isEmpty { html += " placeholder=\"\(htmlEscape(placeholder))\"" }
        if !value.isEmpty { html += " value=\"\(htmlEscape(value))\"" }
        if disabled { html += " disabled" }
        if required { html += " required" }
        for (key, value) in attributes {
            let safeKey = htmlEscape(key)
            guard !safeKey.isEmpty else { continue }
            html += " \(safeKey)=\"\(htmlEscape(value))\""
        }
        html += ">"
        return html
    }
}

// MARK: - Image
public struct Image: View {
    public let src: String
    public let alt: String
    public let `class`: String?
    public let loading: ImageLoading?
    public let decoding: ImageDecoding?
    public enum ImageLoading: String, Sendable {
        case eager = "eager"
        case lazy = "lazy"
    }
    public enum ImageDecoding: String, Sendable {
        case sync = "sync"
        case async = "async"
        case auto = "auto"
    }
    public init(
        src: String,
        alt: String,
        class: String? = nil,
        loading: ImageLoading? = nil,
        decoding: ImageDecoding? = nil
    ) {
        self.src = src
        self.alt = alt
        self.class = `class`
        self.loading = loading
        self.decoding = decoding
    }

    public func render() -> String {
        guard let safeSrc = sanitizeURL(src) else {
            return "<img alt=\"\(htmlEscape(alt))\">"
        }
        var html = "<img src=\"\(htmlEscape(safeSrc))\" alt=\"\(htmlEscape(alt))\""
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        if let loading { html += " loading=\"\(loading.rawValue)\"" }
        if let decoding { html += " decoding=\"\(decoding.rawValue)\"" }
        html += ">"
        return html
    }
}

// MARK: - Link Target
public enum LinkTarget: String, Sendable {
    case `self` = "_self"
    case blank = "_blank"
    case parent = "_parent"
    case top = "_top"
}

// MARK: - Link Rel
public struct LinkRel: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let noopener   = LinkRel(rawValue: 1 << 0)
    public static let noreferrer = LinkRel(rawValue: 1 << 1)
    public static let nofollow   = LinkRel(rawValue: 1 << 2)
    public static let external   = LinkRel(rawValue: 1 << 3)
    public static let help       = LinkRel(rawValue: 1 << 4)
    public static let license    = LinkRel(rawValue: 1 << 5)
    public static let next       = LinkRel(rawValue: 1 << 6)
    public static let prev       = LinkRel(rawValue: 1 << 7)
    public static let search     = LinkRel(rawValue: 1 << 8)
    public static let tag        = LinkRel(rawValue: 1 << 9)

    public var htmlValue: String {
        var values: [String] = []
        if contains(.noopener)   { values.append("noopener") }
        if contains(.noreferrer) { values.append("noreferrer") }
        if contains(.nofollow)   { values.append("nofollow") }
        if contains(.external)   { values.append("external") }
        if contains(.help)       { values.append("help") }
        if contains(.license)    { values.append("license") }
        if contains(.next)       { values.append("next") }
        if contains(.prev)       { values.append("prev") }
        if contains(.search)     { values.append("search") }
        if contains(.tag)        { values.append("tag") }
        return values.joined(separator: " ")
    }
}

// MARK: - Link
public struct Link: View {
    public let text: String
    public let href: String
    public let `class`: String?
    public let target: LinkTarget?
    public let rel: LinkRel?
    public init(
        _ text: String,
        href: String,
        class: String? = nil,
        target: LinkTarget? = nil,
        rel: LinkRel? = nil
    ) {
        self.text = text
        self.href = href
        self.class = `class`
        self.target = target
        self.rel = rel
    }

    public func render() -> String {
        guard let safeHref = sanitizeURL(href) else {
            return htmlEscape(text)
        }
        var html = "<a href=\"\(htmlEscape(safeHref))\""
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        if let target { html += " target=\"\(target.rawValue)\"" }
        if let rel { html += " rel=\"\(rel.htmlValue)\"" }
        html += ">\(htmlEscape(text))</a>"
        return html
    }
}

// MARK: - Heading Level
public enum HeadingLevel: Int, Sendable {
    case h1 = 1, h2 = 2, h3 = 3, h4 = 4, h5 = 5, h6 = 6
}

// MARK: - Header Elements
public struct Heading: View {
    public let level: HeadingLevel
    public let text: String
    public let `class`: String?

    public init(_ text: String, level: HeadingLevel = .h1, class: String? = nil) {
        self.text = text
        self.level = level
        self.class = `class`
    }

    public func render() -> String {
        let lvl = level.rawValue
        var html = "<h\(lvl)"
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        html += ">\(htmlEscape(text))</h\(lvl)>"
        return html
    }
}
public struct Paragraph: View {
    public let text: String
    public let `class`: String?

    public init(_ text: String, class: String? = nil) {
        self.text = text
        self.class = `class`
    }

    public func render() -> String {
        var html = "<p"
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        html += ">\(htmlEscape(text))</p>"
        return html
    }
}

// MARK: - List Elements
public struct UnorderedList: View {
    public let items: [any View]
    public let `class`: String?

    public init(class: String? = nil, @ViewBuilder items: () -> [any View]) {
        self.class = `class`
        self.items = items()
    }

    public func render() -> String {
        var html = "<ul"
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        html += ">"
        for item in items {
            html += "<li>\(item.render())</li>"
        }
        html += "</ul>"
        return html
    }
}
public struct OrderedList: View {
    public let items: [any View]
    public let `class`: String?

    public init(class: String? = nil, @ViewBuilder items: () -> [any View]) {
        self.class = `class`
        self.items = items()
    }

    public func render() -> String {
        var html = "<ol"
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        html += ">"
        for item in items {
            html += "<li>\(item.render())</li>"
        }
        html += "</ol>"
        return html
    }
}

// MARK: - Table Elements
public struct Table: View {
    public let headers: [String]
    public let rows: [[any View]]
    public let `class`: String?
    public init(headers: [String], rows: [[any View]], class: String? = nil) {
        self.headers = headers
        self.rows = rows
        self.class = `class`
    }

    public func render() -> String {
        var html = "<table"
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        html += ">"

        if !headers.isEmpty {
            html += "<thead><tr>"
            for h in headers {
                html += "<th>\(htmlEscape(h))</th>"
            }
            html += "</tr></thead>"
        }

        html += "<tbody>"
        for row in rows {
            html += "<tr>"
            for cell in row {
                html += "<td>\(cell.render())</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"
        return html
    }
}

// MARK: - Select Option
public struct SelectOption: Sendable {
    public let value: String
    public let label: String
    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

// MARK: - Form Elements
public struct Label: View {
    public let text: String
    public let `for`: String?
    public let `class`: String?

    public init(_ text: String, for: String? = nil, class: String? = nil) {
        self.text = text
        self.for = `for`
        self.class = `class`
    }

    public func render() -> String {
        var html = "<label"
        if let forVal = `for` { html += " for=\"\(htmlEscape(forVal))\"" }
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        html += ">\(htmlEscape(text))</label>"
        return html
    }
}
public struct TextArea: View {
    public let id: String?
    public let name: String?
    public let placeholder: String
    public let value: String
    public let rows: Int
    public let `class`: String?

    public init(
        id: String? = nil,
        name: String? = nil,
        placeholder: String = "",
        value: String = "",
        rows: Int = 3,
        class: String? = nil
    ) {
        self.id = id
        self.name = name
        self.placeholder = placeholder
        self.value = value
        self.rows = rows
        self.class = `class`
    }

    public func render() -> String {
        var html = "<textarea"
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        if let name { html += " name=\"\(htmlEscape(name))\"" }
        html += " rows=\"\(rows)\""
        if !placeholder.isEmpty { html += " placeholder=\"\(htmlEscape(placeholder))\"" }
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        html += ">\(htmlEscape(value))</textarea>"
        return html
    }
}
public struct Select: View {
    public let id: String?
    public let name: String?
    public let options: [SelectOption]
    public let selected: String?
    public let `class`: String?

    public init(
        id: String? = nil,
        name: String? = nil,
        options: [SelectOption],
        selected: String? = nil,
        class: String? = nil
    ) {
        self.id = id
        self.name = name
        self.options = options
        self.selected = selected
        self.class = `class`
    }

    public func render() -> String {
        var html = "<select"
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        if let name { html += " name=\"\(htmlEscape(name))\"" }
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        html += ">"
        for option in options {
            let sel = option.value == selected ? " selected" : ""
            html += "<option value=\"\(htmlEscape(option.value))\"\(sel)>\(htmlEscape(option.label))</option>"
        }
        html += "</select>"
        return html
    }
}

// MARK: - ForEach
public struct ForEach<Data: RandomAccessCollection & Sendable>: View {
    public let data: Data
    public let content: @Sendable (Data.Element) -> [any View]
    public init(_ data: Data, @ViewBuilder content: @escaping @Sendable (Data.Element) -> [any View]) {
        self.data = data
        self.content = content
    }

    public func render() -> String {
        data.map { content($0).map { $0.render() }.joined() }.joined()
    }
}
extension ForEach where Data == Range<Int> {
    public init(_ range: Range<Int>, @ViewBuilder content: @escaping @Sendable (Int) -> [any View]) {
        self.data = range
        self.content = content
    }
}

// MARK: - Group
public struct Group: View {
    public let children: [any View]
    public init(@ViewBuilder content: () -> [any View]) {
        self.children = content()
    }

    public func render() -> String {
        children.map { $0.render() }.joined()
    }
}

// MARK: - Form
public struct Form: View {
    public let action: String
    public let method: String
    public let id: String?
    public let `class`: String?
    public let csrfToken: String?
    public let children: [any View]
    public init(
        action: String = "",
        method: String = "post",
        id: String? = nil,
        class: String? = nil,
        csrfToken: String? = nil,
        @ViewBuilder content: () -> [any View]
    ) {
        self.action = action
        self.method = method
        self.id = id
        self.class = `class`
        self.csrfToken = csrfToken
        self.children = content()
    }

    public func render() -> String {
        var html = "<form"
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        if let `class` { html += " class=\"\(htmlEscape(`class`))\"" }
        let safeAction = sanitizeURL(action) ?? ""
        html += " action=\"\(htmlEscape(safeAction))\""
        html += " method=\"\(htmlEscape(method))\""
        html += ">"
        if let token = csrfToken {
            html += "<input type=\"hidden\" name=\"_csrf\" value=\"\(htmlEscape(token))\">"
        }
        for child in children {
            html += child.render()
        }
        html += "</form>"
        return html
    }
}
