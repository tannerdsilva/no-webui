// the typed `<head>` builder (W2.3).
//
// `head:` used to be a raw `String`, which made every meta tag, every link and
// every script in it the caller's job to escape — and a host that forgot produced
// a page the framework had no way to know was wrong. `HeadContent` is the same
// output with the escaping done, the urls sanitized, and the render nonce
// injected where a script needs one.

/// the `<link rel>` relations the builder can emit.
///
/// not to be confused with `LinkRel`, which is the `rel="noopener"` attribute
/// set on an `<a>` — a different axis with a confusingly adjacent name.
public enum LinkRelation: String, Sendable, CaseIterable {
    case stylesheet
    case icon
    case preload
    case modulepreload
    case preconnect
    case dnsPrefetch = "dns-prefetch"
    case manifest
    case canonical
    case alternate
}

/// typed `<head>` content for ``HTMLDocument`` and ``WebUIDocument``.
public struct HeadContent: Sendable {
    /// one piece of head markup.
    ///
    /// scripts are deliberately *not* pre-rendered strings: a script needs the
    /// document's render nonce, and the document only mints that when it renders.
    /// keeping the piece typed until then is what makes the nonce impossible to
    /// forget — including on the inline JSON-LD script, which is the one a host
    /// would least expect to carry one.
    public enum Node: Sendable, Equatable {
        /// markup this builder already escaped and sanitized.
        case markup(String)
        /// an external script; the document adds the nonce, and `type="module"`
        /// when asked.
        case externalScript(src: String, module: Bool)
        /// an inline `application/ld+json` script; the document adds the nonce.
        /// the json is stored already script-safe (see ``scriptSafeJSON(_:)``).
        case jsonScript(json: String)
    }

    public let nodes: [Node]

    public init(nodes: [Node]) { self.nodes = nodes }

    public init(@HeadContentBuilder _ build: () -> [Node]) { self.nodes = build() }

    /// render every piece, injecting `nonce` into each script.
    ///
    /// `nonce` is optional because a host policy may name no nonce source, in
    /// which case the document suppresses inline scripts anyway — carrying the
    /// attribute would not help and the absence is the honest rendering.
    public func render(nonce: String?) -> String {
        var out = ""
        for node in nodes {
            switch node {
                case .markup(let html):
                    out += html
                case .externalScript(let src, let module):
                    let type = module ? " type=\"module\"" : ""
                    out += "<script src=\"\(htmlEscape(src))\"\(type)\(Self.nonceAttribute(nonce))></script>"
                case .jsonScript(let json):
                    out += "<script type=\"application/ld+json\"\(Self.nonceAttribute(nonce))>\(json)</script>"
            }
        }
        return out
    }

    private static func nonceAttribute(_ nonce: String?) -> String {
        guard let nonce, !nonce.isEmpty else { return "" }
        return " nonce=\"\(htmlEscape(nonce))\""
    }
}

// MARK: - the builders

extension HeadContent {

    /// `<meta charset>`.
    public static func charset(_ encoding: String = "utf-8") -> HeadContent {
        HeadContent(nodes: [.markup("<meta charset=\"\(htmlEscape(encoding))\">")])
    }

    /// one `<meta name content>` pair.
    public static func meta(name: String, content: String) -> HeadContent {
        HeadContent(nodes: [.markup("<meta name=\"\(htmlEscape(name))\" content=\"\(htmlEscape(content))\">")])
    }

    /// the open-graph trio.
    ///
    /// a `nil` image emits no `og:image` at all rather than an empty one: an
    /// empty `content=""` is a fact a crawler reads and a consumer displays.
    public static func og(title: String, description: String, image: String? = nil) -> HeadContent {
        var nodes: [Node] = [
            .markup("<meta property=\"og:title\" content=\"\(htmlEscape(title))\">"),
            .markup("<meta property=\"og:description\" content=\"\(htmlEscape(description))\">"),
        ]
        if let image, let safe = sanitizeURL(image) {
            nodes.append(.markup("<meta property=\"og:image\" content=\"\(htmlEscape(safe))\">"))
        }
        return HeadContent(nodes: nodes)
    }

    /// structured data.
    ///
    /// the payload is made script-safe before it is stored, so a value
    /// containing `</script>` cannot close the element it lives in — the one
    /// real trap in emitting JSON-LD by hand.
    public static func jsonLD(_ value: JSONValue) -> HeadContent {
        HeadContent(nodes: [.jsonScript(json: scriptSafeJSON(value.serialize()))])
    }

    /// a `<link>`. an unsanitizable href emits nothing rather than a dead or
    /// hostile link.
    public static func link(rel: LinkRelation, href: String, type: String? = nil) -> HeadContent {
        guard let safe = sanitizeURL(href) else { return HeadContent(nodes: []) }
        var html = "<link rel=\"\(htmlEscape(rel.rawValue))\" href=\"\(htmlEscape(safe))\""
        if let type { html += " type=\"\(htmlEscape(type))\"" }
        html += ">"
        return HeadContent(nodes: [.markup(html)])
    }

    /// an external script. the document adds the nonce at render time — without
    /// it, a nonce-bearing `script-src` policy blocks the script outright.
    public static func script(src: String, module: Bool = false) -> HeadContent {
        HeadContent(nodes: [.externalScript(src: src, module: module)])
    }

    /// markup the caller has explicitly taken responsibility for.
    public static func unsafe(_ markup: UnsafeMarkup) -> HeadContent {
        HeadContent(nodes: [.markup(markup.html)])
    }
}

/// makes a serialized json payload safe to sit inside a `<script>` element.
///
/// `</` is the one sequence that ends the element early, so it becomes `<\/` —
/// still valid JSON (an escaped solidus is legal in a JSON string) and inert to
/// the html parser. escaping it unconditionally is safe: json has no `</`
/// sequence outside a string, and inside one the escape is a no-op semantically.
func scriptSafeJSON(_ json: String) -> String {
    json.replacingOccurrences(of: "</", with: "<\\/")
}

/// composes ``HeadContent`` from expressions, so a `<head>` reads as a list of
/// the things it holds rather than a concatenated string.
@resultBuilder
public enum HeadContentBuilder {
    public static func buildExpression(_ content: HeadContent) -> [HeadContent.Node] { content.nodes }
    public static func buildExpression(_ node: HeadContent.Node) -> [HeadContent.Node] { [node] }
    public static func buildBlock(_ parts: [HeadContent.Node]...) -> [HeadContent.Node] { parts.flatMap { $0 } }
    public static func buildArray(_ parts: [[HeadContent.Node]]) -> [HeadContent.Node] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [HeadContent.Node]?) -> [HeadContent.Node] { part ?? [] }
    public static func buildEither(first part: [HeadContent.Node]) -> [HeadContent.Node] { part }
    public static func buildEither(second part: [HeadContent.Node]) -> [HeadContent.Node] { part }
}