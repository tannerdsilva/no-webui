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

    /// the buffer route writes the escaped bytes straight in. text frames no
    /// element, so there is nothing for a buffer round trip to buy and
    /// `render()` stays the direct call — a text node under a not-yet-migrated
    /// parent (the design system, until S4) would otherwise pay an allocation
    /// pair around the same escape work. a modifier wrapping text still
    /// settles against it through the string-path fallback.
    public func render(into buffer: inout HTMLBuffer) {
        buffer.appendEscaped(content)
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

    /// the buffer route appends the caller's bytes verbatim — `Raw`'s contract —
    /// and `render()` stays direct for the same reason as `Text`: no element is
    /// framed, so a round trip would buy nothing. a modifier wrapping `Raw`
    /// settles against this fragment (its own scan, never the page).
    public func render(into buffer: inout HTMLBuffer) {
        buffer.append(content)
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributes = ""
        if let id { attributes += " id=\"\(htmlEscape(id))\"" }
        if let `class` { attributes += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("div", attributes)
        buffer.endOpenTag()
        for child in children {
            child.render(into: &buffer)
        }
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributes = ""
        if let id { attributes += " id=\"\(htmlEscape(id))\"" }
        if let `class` { attributes += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("span", attributes)
        buffer.endOpenTag()
        for child in children {
            child.render(into: &buffer)
        }
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let id { attributeText += " id=\"\(htmlEscape(id))\"" }
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        if let name { attributeText += " name=\"\(htmlEscape(name))\"" }
        attributeText += " type=\"\(type.rawValue)\""
        if disabled { attributeText += " disabled" }
        buffer.beginElement("button", attributeText)
        buffer.endOpenTag()
        buffer.appendEscaped(label)
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let id { attributeText += " id=\"\(htmlEscape(id))\"" }
        if let name { attributeText += " name=\"\(htmlEscape(name))\"" }
        attributeText += " type=\"\(type.rawValue)\""
        if !placeholder.isEmpty { attributeText += " placeholder=\"\(htmlEscape(placeholder))\"" }
        if !value.isEmpty { attributeText += " value=\"\(htmlEscape(value))\"" }
        if disabled { attributeText += " disabled" }
        if required { attributeText += " required" }
        for (key, value) in attributes {
            let safeKey = htmlEscape(key)
            guard !safeKey.isEmpty else { continue }
            attributeText += " \(safeKey)=\"\(htmlEscape(value))\""
        }
        buffer.voidElement("input", attributeText)
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        guard let safeSrc = sanitizeURL(src) else {
            buffer.voidElement("img", " alt=\"\(htmlEscape(alt))\"")
            return
        }
        var attributeText = " src=\"\(htmlEscape(safeSrc))\" alt=\"\(htmlEscape(alt))\""
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        if let loading { attributeText += " loading=\"\(loading.rawValue)\"" }
        if let decoding { attributeText += " decoding=\"\(decoding.rawValue)\"" }
        buffer.voidElement("img", attributeText)
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        guard let safeHref = sanitizeURL(href) else {
            buffer.appendEscaped(text)
            return
        }
        var attributeText = " href=\"\(htmlEscape(safeHref))\""
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        if let target { attributeText += " target=\"\(target.rawValue)\"" }
        if let rel { attributeText += " rel=\"\(rel.htmlValue)\"" }
        buffer.beginElement("a", attributeText)
        buffer.endOpenTag()
        buffer.appendEscaped(text)
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let lvl = level.rawValue
        var attributeText = ""
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("h\(lvl)", attributeText)
        buffer.endOpenTag()
        buffer.appendEscaped(text)
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("p", attributeText)
        buffer.endOpenTag()
        buffer.appendEscaped(text)
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributes = ""
        if let `class` { attributes += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("ul", attributes)
        buffer.endOpenTag()
        for item in items {
            buffer.beginElement("li")
            buffer.endOpenTag()
            item.render(into: &buffer)
            buffer.endElement()
        }
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributes = ""
        if let `class` { attributes += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("ol", attributes)
        buffer.endOpenTag()
        for item in items {
            buffer.beginElement("li")
            buffer.endOpenTag()
            item.render(into: &buffer)
            buffer.endElement()
        }
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("table", attributeText)
        buffer.endOpenTag()

        if !headers.isEmpty {
            buffer.beginElement("thead")
            buffer.endOpenTag()
            buffer.beginElement("tr")
            buffer.endOpenTag()
            for h in headers {
                buffer.beginElement("th")
                buffer.endOpenTag()
                buffer.appendEscaped(h)
                buffer.endElement()
            }
            buffer.endElement()
            buffer.endElement()
        }

        buffer.beginElement("tbody")
        buffer.endOpenTag()
        for row in rows {
            buffer.beginElement("tr")
            buffer.endOpenTag()
            for cell in row {
                buffer.beginElement("td")
                buffer.endOpenTag()
                cell.render(into: &buffer)
                buffer.endElement()
            }
            buffer.endElement()
        }
        buffer.endElement()
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let forVal = `for` { attributeText += " for=\"\(htmlEscape(forVal))\"" }
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("label", attributeText)
        buffer.endOpenTag()
        buffer.appendEscaped(text)
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let id { attributeText += " id=\"\(htmlEscape(id))\"" }
        if let name { attributeText += " name=\"\(htmlEscape(name))\"" }
        attributeText += " rows=\"\(rows)\""
        if !placeholder.isEmpty { attributeText += " placeholder=\"\(htmlEscape(placeholder))\"" }
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("textarea", attributeText)
        buffer.endOpenTag()
        buffer.appendEscaped(value)
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let id { attributeText += " id=\"\(htmlEscape(id))\"" }
        if let name { attributeText += " name=\"\(htmlEscape(name))\"" }
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("select", attributeText)
        buffer.endOpenTag()
        for option in options {
            let sel = option.value == selected ? " selected" : ""
            buffer.beginElement("option", " value=\"\(htmlEscape(option.value))\"\(sel)")
            buffer.endOpenTag()
            buffer.appendEscaped(option.label)
            buffer.endElement()
        }
        buffer.endElement()
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        for element in data {
            for child in content(element) {
                child.render(into: &buffer)
            }
        }
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        for child in children {
            child.render(into: &buffer)
        }
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
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let id { attributeText += " id=\"\(htmlEscape(id))\"" }
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        let safeAction = sanitizeURL(action) ?? ""
        attributeText += " action=\"\(htmlEscape(safeAction))\""
        attributeText += " method=\"\(htmlEscape(method))\""
        buffer.beginElement("form", attributeText)
        buffer.endOpenTag()
        if let token = csrfToken {
            buffer.voidElement("input", " type=\"hidden\" name=\"_csrf\" value=\"\(htmlEscape(token))\"")
        }
        for child in children {
            child.render(into: &buffer)
        }
        buffer.endElement()
    }
}
