import WebUICore

// MARK: - p7 long tail: carousel (t2) and menubar (t3)
//
// both are deliberately zero-js. the engine delivers only declared events, so a
// component that ships a client script would break the contract the rest of the
// design system holds; where a full-fidelity interaction needs javascript, the
// divergence is documented here and in Documentation/DESIGN_SYSTEM.md rather
// than paid for with a script.

/// A horizontally scrollable slide track built on css scroll-snap.
///
/// the track is focusable, so arrow keys scroll it natively; the dots are
/// anchors into the slides, which means they *navigate* but cannot reflect the
/// current slide without javascript (the documented divergence).
public struct WebUICarousel: View {

    public let id: String
    /// accessible name for the scroll region
    public let label: String
    /// one entry per slide, in order
    public let slides: [any View]
    public let showsDots: Bool

    public init(id: String, label: String, showsDots: Bool = true, slides: [any View]) {
        self.id = id
        self.label = label
        self.showsDots = showsDots
        self.slides = slides
    }

    public func render() -> String {
        var html = "<div class=\"carousel\" id=\"\(htmlEscape(id))\">"
        html += "<div class=\"carousel__track\" tabindex=\"0\" role=\"group\" aria-label=\"\(htmlEscape(label))\">"
        for (i, slide) in slides.enumerated() {
            html += "<div class=\"carousel__slide\" id=\"\(htmlEscape(id))-\(i)\">"
            html += slide.render()
            html += "</div>"
        }
        html += "</div>"
        if showsDots && slides.count > 1 {
            html += "<div class=\"carousel__dots\">"
            for i in slides.indices {
                html += "<a class=\"carousel__dot\" href=\"#\(htmlEscape(id))-\(i)\" aria-label=\"Slide \(i + 1)\"></a>"
            }
            html += "</div>"
        }
        html += "</div>"
        return html
    }
}

/// A horizontal menu bar whose panels open on hover or keyboard focus.
///
/// panel visibility is `:hover` + `:focus-within`, so the bar is reachable by
/// tabbing onto a trigger and needs no javascript. escape-to-close and
/// click-to-toggle are the divergences: both need a keydown/click channel the
/// engine does not provide for non-routed chrome.
public struct WebUIMenubar: View {

    /// one entry inside a panel: a navigation link, or a plain row when `href`
    /// is nil (application menus carry handlers instead, wired by the caller).
    public struct Entry: Sendable {
        public let label: String
        public let href: String?

        public init(_ label: String, href: String? = nil) {
            self.label = label
            self.href = href
        }
    }

    /// one top-level item: a trigger plus its panel entries.
    public struct Item: Sendable {
        public let label: String
        public let entries: [Entry]

        public init(_ label: String, entries: [Entry]) {
            self.label = label
            self.entries = entries
        }
    }

    public let items: [Item]
    public let id: String?

    public init(items: [Item], id: String? = nil) {
        self.items = items
        self.id = id
    }

    public func render() -> String {
        var html = "<nav class=\"menubar\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        html += " aria-label=\"Main\">"
        for (i, item) in items.enumerated() {
            html += "<div class=\"menubar__item\">"
            html += "<button type=\"button\" class=\"menubar__trigger\" aria-haspopup=\"true\" aria-expanded=\"false\""
            html += " aria-controls=\"\(htmlEscape(id ?? "menubar"))-panel-\(i)\">"
            html += htmlEscape(item.label)
            html += "</button>"
            html += "<div class=\"menubar__panel\" id=\"\(htmlEscape(id ?? "menubar"))-panel-\(i)\" role=\"menu\">"
            for entry in item.entries {
                if let href = entry.href {
                    html += "<a class=\"menubar__link\" role=\"menuitem\" href=\"\(htmlEscape(href))\">"
                } else {
                    html += "<span class=\"menubar__link\" role=\"menuitem\">"
                }
                html += htmlEscape(entry.label)
                html += entry.href == nil ? "</span>" : "</a>"
            }
            html += "</div>"
            html += "</div>"
        }
        html += "</nav>"
        return html
    }
}