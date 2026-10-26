// MARK: - VStack
public struct VStack<Content: View>: View {
    public let alignment: HorizontalAlignment
    public let spacing: Int
    public let content: Content
    public init(
        alignment: HorizontalAlignment = .leading,
        spacing: Int = 8,
        @ElementBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let alignClass = "align-\(alignment.cssValue)"
        buffer.beginElement("div", " class=\"vstack spacing-\(spacing) \(alignClass)\"")
        buffer.endOpenTag()
        buffer.append("\n")
        content.render(into: &buffer)
        buffer.append("\n")
        buffer.endElement()
    }
}

// MARK: - HStack
public struct HStack<Content: View>: View {
    public let alignment: VerticalAlignment
    public let spacing: Int
    public let content: Content
    public init(
        alignment: VerticalAlignment = .center,
        spacing: Int = 8,
        @ElementBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let alignClass = "align-\(alignment.cssValue)"
        buffer.beginElement("div", " class=\"hstack spacing-\(spacing) \(alignClass)\"")
        buffer.endOpenTag()
        buffer.append("\n")
        content.render(into: &buffer)
        buffer.append("\n")
        buffer.endElement()
    }
}

// MARK: - ZStack
public struct ZStack<Content: View>: View {
    public let alignment: HorizontalAlignment
    public let verticalAlignment: VerticalAlignment
    public let content: Content
    public init(
        alignment: HorizontalAlignment = .center,
        verticalAlignment: VerticalAlignment = .center,
        @ElementBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.content = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let hAlign = alignment.cssValue
        let vAlign = verticalAlignment.cssValue
        buffer.beginElement("div", " class=\"zstack\" style=\"display:grid;place-items:\(hAlign) \(vAlign);\"")
        buffer.endOpenTag()
        buffer.append("\n")
        content.render(into: &buffer)
        buffer.append("\n")
        buffer.endElement()
    }
}

// MARK: - Spacer
public struct Spacer: View {
    public let minSize: Int
    public init(minSize: Int = 0) {
        self.minSize = minSize
    }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.beginElement("div", " class=\"spacer\" style=\"flex:1;min-width:\(minSize)px;min-height:\(minSize)px\"")
        buffer.endOpenTag()
        buffer.endElement()
    }
}

// MARK: - ScrollView
public struct ScrollView<Content: View>: View {
    public let content: Content
    public init(@ElementBuilder content: () -> Content) {
        self.content = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.beginElement("div", " class=\"scrollview\"")
        buffer.endOpenTag()
        buffer.append("\n")
        content.render(into: &buffer)
        buffer.append("\n")
        buffer.endElement()
    }
}

// MARK: - Grid Columns

// `.fixed(n)` is a count-based track template made grid-safe (minmax(0, 1fr)
// prevents min-content blowout), distinct from `.fraction(n)` which emits the
// legacy plain 1fr tracks. `.autoFill(n)`/`.autoFit(n)` treat n as the
// minimum track size in px — `repeat(auto-fill, minmax(npx, 1fr))` — because
// an auto-* repetition without a concrete min size is meaningless.
public enum GridColumns: Sendable {
    case fixed(Int)
    case fraction(Int)
    case minmax(String, String)
    case autoFill(Int)
    case autoFit(Int)
    case custom(String)

    public var cssValue: String {
        switch self {
        case .fixed(let n):     return "repeat(\(n), minmax(0, 1fr))"
        case .fraction(let n):  return "repeat(\(n), 1fr)"
        case .minmax(let a, let b): return "repeat(auto-fill, minmax(\(a), \(b)))"
        case .autoFill(let n):  return "repeat(auto-fill, minmax(\(n)px, 1fr))"
        case .autoFit(let n):   return "repeat(auto-fit, minmax(\(n)px, 1fr))"
        case .custom(let v):    return v
        }
    }
}

// MARK: - Grid
public struct Grid<Content: View>: View {
    public let columns: GridColumns
    public let spacing: Int
    public let content: Content
    public init(
        columns: GridColumns = .fraction(2),
        spacing: Int = 16,
        @ElementBuilder content: () -> Content
    ) {
        self.columns = columns
        self.spacing = spacing
        self.content = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.beginElement("div", " class=\"grid\" style=\"display:grid;grid-template-columns:\(columns.cssValue);gap:\(spacing)px;\"")
        buffer.endOpenTag()
        buffer.append("\n")
        content.render(into: &buffer)
        buffer.append("\n")
        buffer.endElement()
    }
}

// MARK: - Section
public struct Section<Content: View>: View {
    public let id: String?
    public let `class`: String?
    public let content: Content

    public init(
        id: String? = nil,
        class: String? = nil,
        @ElementBuilder content: () -> Content
    ) {
        self.id = id
        self.class = `class`
        self.content = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributes = ""
        if let id { attributes += " id=\"\(htmlEscape(id))\"" }
        if let `class` { attributes += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("section", attributes)
        buffer.endOpenTag()
        content.render(into: &buffer)
        buffer.endElement()
    }
}

// MARK: - Navigation
public struct Navigation<Content: View>: View {
    public let `class`: String?
    public let content: Content

    public init(
        class: String? = nil,
        @ElementBuilder content: () -> Content
    ) {
        self.class = `class`
        self.content = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("nav", attributeText)
        buffer.endOpenTag()
        content.render(into: &buffer)
        buffer.endElement()
    }
}

// MARK: - Header
public struct Header<Content: View>: View {
    public let `class`: String?
    public let content: Content

    public init(
        class: String? = nil,
        @ElementBuilder content: () -> Content
    ) {
        self.class = `class`
        self.content = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("header", attributeText)
        buffer.endOpenTag()
        content.render(into: &buffer)
        buffer.endElement()
    }
}

// MARK: - Footer
public struct Footer<Content: View>: View {
    public let `class`: String?
    public let content: Content

    public init(
        class: String? = nil,
        @ElementBuilder content: () -> Content
    ) {
        self.class = `class`
        self.content = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("footer", attributeText)
        buffer.endOpenTag()
        content.render(into: &buffer)
        buffer.endElement()
    }
}

// MARK: - Main
public struct Main<Content: View>: View {
    public let `class`: String?
    public let content: Content

    public init(
        class: String? = nil,
        @ElementBuilder content: () -> Content
    ) {
        self.class = `class`
        self.content = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("main", attributeText)
        buffer.endOpenTag()
        content.render(into: &buffer)
        buffer.endElement()
    }
}

// MARK: - Aside
public struct Aside<Content: View>: View {
    public let `class`: String?
    public let content: Content

    public init(
        class: String? = nil,
        @ElementBuilder content: () -> Content
    ) {
        self.class = `class`
        self.content = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = ""
        if let `class` { attributeText += " class=\"\(htmlEscape(`class`))\"" }
        buffer.beginElement("aside", attributeText)
        buffer.endOpenTag()
        content.render(into: &buffer)
        buffer.endElement()
    }
}