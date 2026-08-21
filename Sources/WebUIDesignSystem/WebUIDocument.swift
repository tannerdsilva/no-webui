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
        self.contentSecurityPolicy = contentSecurityPolicy
    }

    public func render() -> String {
        let doc = HTMLDocument(
            title: title,
            body: body,
            styles: CSSStylesheet(WebUITheme.all + LayoutStyles.complete),
            rawStyles: [WebUIAssets.css],
            scripts: scripts,
            head: head,
            bodyAttributes: bodyAttributes,
            devMode: devMode,
            lang: lang,
            includeRuntime: includeRuntime,
            contentSecurityPolicy: contentSecurityPolicy
        )
        return doc.render()
    }
}
