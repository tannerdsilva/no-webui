import Foundation
import WebUI

// MARK: - WebUIDocument
public struct WebUIDocument: View {
    public let title: String
    public let body: String
    public let scripts: String
    public let head: String
    public let bodyAttributes: String
    public let devMode: Bool
    public let lang: String
    public let includeRuntime: Bool
    public let runtimeConfig: RuntimeConfig?
    public let contentSecurityPolicy: String?
    public let theme: WebUITheme
    public let clientMode: ClientBoot?
    public let rawStyles: [String]
    /// when set, the design-system sheet is emitted as a cacheable
    /// `<link rel="stylesheet">` instead of being inlined (default
    /// `/__assets/css` — hosts serve the same bytes via
    /// `DesignSystemAssets.minifiedCss`). pass `nil` to inline like before.
    public let stylesheetURL: String?
    public init(
        title: String = "WebUI",
        body: String,
        scripts: String = "",
        head: String = "",
        bodyAttributes: String = "",
        clientMode: ClientBoot? = nil,
        devMode: Bool = false,
        lang: String = "en",
        includeRuntime: Bool = true,
        runtimeConfig: RuntimeConfig? = nil,
        contentSecurityPolicy: String? = nil,
        theme: WebUITheme = .standard,
        rawStyles: [String] = [],
        stylesheetURL: String? = "/__assets/css"
    ) {
        self.title = title
        self.body = body
        self.scripts = scripts
        self.head = head
        self.bodyAttributes = bodyAttributes
        self.clientMode = clientMode
        self.devMode = devMode
        self.lang = lang
        self.includeRuntime = includeRuntime
        self.runtimeConfig = runtimeConfig
        self.contentSecurityPolicy = contentSecurityPolicy
        self.theme = theme
        self.rawStyles = rawStyles
        self.stylesheetURL = stylesheetURL
    }

    /// the design-system sheet (layout rules + embedded css), minified once —
    /// the same bytes the servers serve on `/__assets/css` (see
    /// `DesignSystemAssets.minifiedCss`), so a page that links instead of
    /// inlining is byte-equivalent.
    public static let minifiedDesignStyles: String = DesignSystemAssets.minifiedCss

    public func render() -> String {
        // the theme block lands after the base sheet, so its `:root`
        // overrides win the cascade. `.standard` contributes nothing and the
        // document stays byte-identical to the unthemed one.
        let themeCSS = theme.stylesheet()
        var rawStyles: [String]
        if stylesheetURL != nil {
            // linked sheet mode: only theme + page-scoped styles stay inline.
            rawStyles = []
            if !themeCSS.isEmpty { rawStyles.append(themeCSS) }
            rawStyles.append(contentsOf: self.rawStyles)
        } else {
            rawStyles = [Self.minifiedDesignStyles]
            if !themeCSS.isEmpty { rawStyles.append(themeCSS) }
            rawStyles.append(contentsOf: self.rawStyles)
        }
        let doc = HTMLDocument(
            title: title,
            body: body,
            styles: CSSStylesheet([]),
            rawStyles: rawStyles,
            scripts: scripts,
            head: head,
            bodyAttributes: bodyAttributes,
            clientMode: clientMode,
            devMode: devMode,
            lang: lang,
            includeRuntime: includeRuntime,
            runtimeConfig: runtimeConfig,
            contentSecurityPolicy: contentSecurityPolicy,
            preMinifiedStyles: true,
            stylesheetURL: stylesheetURL
        )
        return doc.render()
    }
}
