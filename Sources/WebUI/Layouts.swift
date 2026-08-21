import Foundation

// MARK: - VStack
public struct VStack: View {
    public let alignment: HorizontalAlignment
    public let spacing: Int
    public let children: [any View]
    public init(
        alignment: HorizontalAlignment = .leading,
        spacing: Int = 8,
        @ViewBuilder content: () -> [any View]
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.children = content()
    }

    public func render() -> String {
        let alignClass = "align-\(alignment.cssValue)"
        return """
        <div class="vstack spacing-\(spacing) \(alignClass)">
        \(children.map { $0.render() }.joined())
        </div>
        """
    }
}

// MARK: - HStack
public struct HStack: View {
    public let alignment: VerticalAlignment
    public let spacing: Int
    public let children: [any View]
    public init(
        alignment: VerticalAlignment = .center,
        spacing: Int = 8,
        @ViewBuilder content: () -> [any View]
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.children = content()
    }

    public func render() -> String {
        let alignClass = "align-\(alignment.cssValue)"
        return """
        <div class="hstack spacing-\(spacing) \(alignClass)">
        \(children.map { $0.render() }.joined())
        </div>
        """
    }
}

// MARK: - ZStack
public struct ZStack: View {
    public let alignment: HorizontalAlignment
    public let verticalAlignment: VerticalAlignment
    public let children: [any View]
    public init(
        alignment: HorizontalAlignment = .center,
        verticalAlignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> [any View]
    ) {
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.children = content()
    }

    public func render() -> String {
        let hAlign = alignment.cssValue
        let vAlign = verticalAlignment.cssValue
        return """
        <div class="zstack" style="display:grid;place-items:\(hAlign) \(vAlign);">
        \(children.map { $0.render() }.joined())
        </div>
        """
    }
}

// MARK: - Spacer
public struct Spacer: View {
    public let minSize: Int
    public init(minSize: Int = 0) {
        self.minSize = minSize
    }

    public func render() -> String {
        "<div class=\"spacer\" style=\"flex:1;min-width:\(minSize)px;min-height:\(minSize)px\"></div>"
    }
}

// MARK: - ScrollView
public struct ScrollView: View {
    public let children: [any View]
    public init(@ViewBuilder content: () -> [any View]) {
        self.children = content()
    }

    public func render() -> String {
        """
        <div class="scrollview">
        \(children.map { $0.render() }.joined())
        </div>
        """
    }
}

// MARK: - Grid Columns
public enum GridColumns: Sendable {
    case fixed(Int)
    case fraction(Int)
    case minmax(String, String)
    case autoFill(Int)
    case autoFit(Int)
    case custom(String)

    public var cssValue: String {
        switch self {
        case .fixed(let n):     return "repeat(\(n), 1fr)"
        case .fraction(let n):  return "repeat(\(n), 1fr)"
        case .minmax(let a, let b): return "repeat(auto-fill, minmax(\(a), \(b)))"
        case .autoFill(let n):  return "repeat(auto-fill, \(n)fr)"
        case .autoFit(let n):   return "repeat(auto-fit, \(n)fr)"
        case .custom(let v):    return v
        }
    }
}

// MARK: - Grid
public struct Grid: View {
    public let columns: GridColumns
    public let spacing: Int
    public let children: [any View]
    public init(
        columns: GridColumns = .fraction(2),
        spacing: Int = 16,
        @ViewBuilder content: () -> [any View]
    ) {
        self.columns = columns
        self.spacing = spacing
        self.children = content()
    }

    public func render() -> String {
        """
        <div class="grid" style="display:grid;grid-template-columns:\(columns.cssValue);gap:\(spacing)px;">
        \(children.map { $0.render() }.joined())
        </div>
        """
    }
}

// MARK: - Section
public struct Section: View {
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
        var html = "<section"
        if let id { html += " id=\"\(id)\"" }
        if let `class` { html += " class=\"\(`class`)\"" }
        html += ">"
        for child in children {
            html += child.render()
        }
        html += "</section>"
        return html
    }
}

// MARK: - Navigation
public struct Navigation: View {
    public let `class`: String?
    public let children: [any View]

    public init(
        class: String? = nil,
        @ViewBuilder content: () -> [any View]
    ) {
        self.class = `class`
        self.children = content()
    }

    public func render() -> String {
        var html = "<nav"
        if let `class` { html += " class=\"\(`class`)\"" }
        html += ">"
        for child in children {
            html += child.render()
        }
        html += "</nav>"
        return html
    }
}

// MARK: - Header
public struct Header: View {
    public let `class`: String?
    public let children: [any View]

    public init(
        class: String? = nil,
        @ViewBuilder content: () -> [any View]
    ) {
        self.class = `class`
        self.children = content()
    }

    public func render() -> String {
        var html = "<header"
        if let `class` { html += " class=\"\(`class`)\"" }
        html += ">"
        for child in children {
            html += child.render()
        }
        html += "</header>"
        return html
    }
}

// MARK: - Footer
public struct Footer: View {
    public let `class`: String?
    public let children: [any View]

    public init(
        class: String? = nil,
        @ViewBuilder content: () -> [any View]
    ) {
        self.class = `class`
        self.children = content()
    }

    public func render() -> String {
        var html = "<footer"
        if let `class` { html += " class=\"\(`class`)\"" }
        html += ">"
        for child in children {
            html += child.render()
        }
        html += "</footer>"
        return html
    }
}

// MARK: - Main
public struct Main: View {
    public let `class`: String?
    public let children: [any View]

    public init(
        class: String? = nil,
        @ViewBuilder content: () -> [any View]
    ) {
        self.class = `class`
        self.children = content()
    }

    public func render() -> String {
        var html = "<main"
        if let `class` { html += " class=\"\(`class`)\"" }
        html += ">"
        for child in children {
            html += child.render()
        }
        html += "</main>"
        return html
    }
}

// MARK: - Aside
public struct Aside: View {
    public let `class`: String?
    public let children: [any View]

    public init(
        class: String? = nil,
        @ViewBuilder content: () -> [any View]
    ) {
        self.class = `class`
        self.children = content()
    }

    public func render() -> String {
        var html = "<aside"
        if let `class` { html += " class=\"\(`class`)\"" }
        html += ">"
        for child in children {
            html += child.render()
        }
        html += "</aside>"
        return html
    }
}
