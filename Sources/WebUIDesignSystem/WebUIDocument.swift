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
        rawStyles: [String] = []
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
    }

    /// the design-system sheet (layout rules + embedded css), minified once
    /// and embedded verbatim on every render. previously every page build
    /// re-minified the full ~300 kb asset (~10 ms in release, per request).
    public static let minifiedDesignStyles: String = {
        let combined = CSSStylesheet(LayoutStyles.complete).render() + "\n\n" + WebUIAssets.css
        return minifyCSS(combined)
    }()

    public func render() -> String {
        // the theme block lands after the base sheet, so its `:root`
        // overrides win the cascade. `.standard` contributes nothing and the
        // document stays byte-identical to the unthemed one.
        let themeCSS = theme.stylesheet()
        var rawStyles = [Self.minifiedDesignStyles]
        if !themeCSS.isEmpty {
            rawStyles.append(themeCSS)
        }
        // page-scoped styles (e.g. the login page's card layout) land after
        // the sheet so they can extend it without being overridden.
        rawStyles.append(contentsOf: self.rawStyles)
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
            preMinifiedStyles: true
        )
        return doc.render()
    }
}
