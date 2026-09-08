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
    public init(
        title: String = "WebUI UI",
        body: String,
        scripts: String = "",
        head: String = "",
        bodyAttributes: String = "",
        devMode: Bool = false,
        lang: String = "en",
        includeRuntime: Bool = true,
        runtimeConfig: RuntimeConfig? = nil,
        contentSecurityPolicy: String? = nil
    ) {
        self.title = title
        self.body = body
        self.scripts = scripts
        self.head = head
        self.bodyAttributes = bodyAttributes
        self.devMode = devMode
        self.lang = lang
        self.includeRuntime = includeRuntime
        self.runtimeConfig = runtimeConfig
        self.contentSecurityPolicy = contentSecurityPolicy
    }

    /// the design-system sheet (layout rules + embedded css), minified once
    /// and embedded verbatim on every render. previously every page build
    /// re-minified the full ~300 kb asset (~10 ms in release, per request).
    public static let minifiedDesignStyles: String = {
        let combined = CSSStylesheet(LayoutStyles.complete).render() + "\n\n" + WebUIAssets.css
        return minifyCSS(combined)
    }()

    public func render() -> String {
        let doc = HTMLDocument(
            title: title,
            body: body,
            styles: CSSStylesheet([]),
            rawStyles: [Self.minifiedDesignStyles],
            scripts: scripts,
            head: head,
            bodyAttributes: bodyAttributes,
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
