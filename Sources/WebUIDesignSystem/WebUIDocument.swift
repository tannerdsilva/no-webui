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
    /// the document's base direction (`ltr` / `rtl`); nil omits the attribute.
    public let dir: String?
    public let includeRuntime: Bool
    public let runtimeConfig: RuntimeConfig?
    public let contentSecurityPolicy: String?
    /// Directives merged per name into the effective policy (the framework's nonce-aware
    /// default, or ``contentSecurityPolicy`` when set) — see `HTMLDocument`.
    public let contentSecurityPolicyExtras: String?
    public let theme: WebUITheme
    public let clientMode: ClientBoot?
    public let rawStyles: [String]
    /// when set, the design-system sheet is emitted as a cacheable
    /// `<link rel="stylesheet">` instead of being inlined (default
    /// `/__assets/css` — hosts serve the same bytes via
    /// `DesignSystemAssets.minifiedCss`). pass `nil` to inline like before.
    public let stylesheetURL: String?
    /// A content-addressed theme catalog (see ``ThemeSheet``) to LINK after the base sheet.
    ///
    /// When set, the inline theme is skipped: the sheet is immutable-cached, so a second
    /// navigation transfers zero theme bytes. Pair it with a ``ThemeSheet``'s `url`, and hand
    /// the same sheet to `WebUIServerConfig.themeSheet` so the route exists.
    public let themeStylesheetURL: String?
    /// dev-time class validation: when true, the rendered document is scanned
    /// against the shipped sheet and every undefined class is routed through
    /// `HTMLClassValidator.onUndefined`. catches typo'd class names that
    /// otherwise render silently unstyled. default false.
    public let checkClasses: Bool
    public init(
        title: String = "WebUI",
        body: String,
        scripts: String = "",
        head: String = "",
        bodyAttributes: String = "",
        clientMode: ClientBoot? = nil,
        devMode: Bool = false,
        lang: String = "en",
        dir: String? = nil,
        includeRuntime: Bool = true,
        runtimeConfig: RuntimeConfig? = nil,
        contentSecurityPolicy: String? = nil,
        contentSecurityPolicyExtras: String? = nil,
        theme: WebUITheme = .standard,
        rawStyles: [String] = [],
        stylesheetURL: String? = DesignSystemAssets.stylesheetURL,
        themeStylesheetURL: String? = nil,
        checkClasses: Bool = false
    ) {
        self.title = title
        self.body = body
        self.scripts = scripts
        self.head = head
        self.bodyAttributes = bodyAttributes
        self.clientMode = clientMode
        self.devMode = devMode
        self.lang = lang
        self.dir = dir
        self.includeRuntime = includeRuntime
        self.runtimeConfig = runtimeConfig
        self.contentSecurityPolicy = contentSecurityPolicy
        self.contentSecurityPolicyExtras = contentSecurityPolicyExtras
        self.theme = theme
        self.rawStyles = rawStyles
        self.stylesheetURL = stylesheetURL
        self.themeStylesheetURL = themeStylesheetURL
        self.checkClasses = checkClasses
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
        // a LINKED theme sheet wins over an inline one: it is content-addressed, so the
        // browser caches it and a second navigation transfers zero theme bytes. inlining is
        // what made the theme ride every page (the plan's B7).
        let linksThemeSheet = themeStylesheetURL != nil
        let themeCSS = linksThemeSheet ? "" : theme.stylesheet()
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
            dir: dir,
            includeRuntime: includeRuntime,
            runtimeConfig: runtimeConfig,
            contentSecurityPolicy: contentSecurityPolicy,
            contentSecurityPolicyExtras: contentSecurityPolicyExtras,
            preMinifiedStyles: true,
            stylesheetURL: stylesheetURL,
            themeStylesheetURL: themeStylesheetURL,
            // inline mode carries the sheet in rawStyles (see the rawStyles
            // block above) — the missing-sheet diagnostics must stay quiet
            inlinedComponentStyles: stylesheetURL == nil
        )
        let html = doc.render()
        if checkClasses {
            HTMLClassValidator.report(html: html)
        }
        return html
    }
}
