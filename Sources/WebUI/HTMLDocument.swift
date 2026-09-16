import Foundation

// MARK: - HTMLDocument
public struct HTMLDocument: Sendable {
    public let title: String
    public let body: String
    public let styles: CSSStylesheet
    public let rawStyles: [String]
    public let scripts: String
    public let head: String
    public let bodyAttributes: String
    /// the client-mode boot: when set, the document emits the `webui-wasm`
    /// contract + external chamber/boot scripts and substitutes the client csp
    /// (`'wasm-unsafe-eval'`) for the default nonce policy; the inline server
    /// runtime is suppressed (the wasm chamber replaces it).
    public let clientMode: ClientBoot?
    public let devMode: Bool
    public let lang: String
    public let includeRuntime: Bool
    public let runtimeConfig: RuntimeConfig?
    public let contentSecurityPolicy: String?
    public let nonce: String
    /// when `true`, the combined `styles` + `rawStyles` string is embedded
    /// verbatim instead of passed through `minifyCSS`. used by documents that
    /// pre-minify their (deterministic) stylesheet once at startup — hoisting
    /// the 300 kb design-system sheet out of every render removes the
    /// dominant per-request cost (measured ~10 ms in release).
    public let preMinifiedStyles: Bool
    private static func generateNonce() -> String {
        guard let bytes = SecureRandom.bytes(16) else {
            // fail loud: silently falling back to a weaker nonce source would
            // ship a page whose csp nonce is not fully random. entropy failure
            // is a fatal system condition, not a fallback case.
            preconditionFailure("SecureRandom.bytes failed — cannot mint a csp nonce")
        }
        return Base64.encodeURL(bytes)
    }
    private func effectiveCSP(nonce: String) -> String? {
        if let csp = contentSecurityPolicy {
            return csp.isEmpty ? nil : csp
        }
        if clientMode != nil {
            // client-mode pages must permit wasm compilation; still `'self'`,
            // still no `'unsafe-inline'` in script-src (trajectory w§3.7).
            return ClientBoot.defaultCSP
        }
        if devMode {
            return "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:;"
        }
        return "default-src 'self'; script-src 'nonce-\(nonce)'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:;"
    }
    public init(
        title: String = "WebUI UI",
        body: String,
        styles: CSSStylesheet = CSSStylesheet([]),
        rawStyles: [String] = [],
        scripts: String = "",
        head: String = "",
        bodyAttributes: String = "",
        clientMode: ClientBoot? = nil,
        devMode: Bool = false,
        lang: String = "en",
        includeRuntime: Bool = true,
        runtimeConfig: RuntimeConfig? = nil,
        contentSecurityPolicy: String? = nil,
        preMinifiedStyles: Bool = false
    ) {
        self.title = title
        self.body = body
        self.styles = styles
        self.rawStyles = rawStyles
        self.scripts = scripts
        self.head = head
        self.bodyAttributes = bodyAttributes
        self.clientMode = clientMode
        self.devMode = devMode
        self.lang = lang
        self.includeRuntime = includeRuntime
        self.runtimeConfig = runtimeConfig
        self.contentSecurityPolicy = contentSecurityPolicy
        self.preMinifiedStyles = preMinifiedStyles
        self.nonce = Self.generateNonce()
    }
    public func render() -> String {
        let styleTag: String
        let scriptTag: String
        let cspValue = effectiveCSP(nonce: nonce)
        // client-mode pages replace the inline server runtime with the wasm
        // chamber (the boot head is appended to the caller's head slot).
        let resolvedHead = head + (clientMode.map { "\n" + $0.headMarkup() } ?? "")

        if devMode {
            styleTag = "<link rel=\"stylesheet\" href=\"/ui/styles.css\">"
            let runtimeSrc = (includeRuntime && clientMode == nil) ? "<script src=\"/ui/scripts.js\"></script>" : ""
            let appSrc = scripts.isEmpty ? "" : "<script src=\"/ui/app.js\"></script>"
            scriptTag = [runtimeSrc, appSrc].filter { !$0.isEmpty }.joined(separator: "\n          ")
        } else {
            var cssParts: [String] = []
            let cssContent = styles.render()
            if !cssContent.isEmpty { cssParts.append(cssContent) }
            cssParts.append(contentsOf: rawStyles)
            let combinedCSS = cssParts.joined(separator: "\n\n")
            let allCSS = preMinifiedStyles ? combinedCSS : minifyCSS(combinedCSS)
            styleTag = allCSS.isEmpty ? "" : "<style>\n\(allCSS)\n</style>"

            var jsParts: [String] = []
            if includeRuntime, clientMode == nil {
                jsParts.append(WebUIRuntime.source)
                jsParts.append(WebUIRuntime.bootstrap(config: runtimeConfig))
            }
            if !scripts.isEmpty {
                jsParts.append(scripts)
            }
            let jsContent = jsParts.joined(separator: "\n\n")
            scriptTag = jsContent.isEmpty ? "" : "<script nonce=\"\(nonce)\">\n\(jsContent)\n</script>"
        }

        let bodyAttr = bodyAttributes.isEmpty ? "" : " \(bodyAttributes)"
        let cspTag: String
        if let csp = cspValue {
            cspTag = "\n          <meta http-equiv=\"Content-Security-Policy\" content=\"\(csp)\">"
        } else {
            cspTag = ""
        }

        return """
        <!DOCTYPE html>
        <html lang="\(lang)">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">\(cspTag)
          <title>\(htmlEscape(title))</title>
          \(resolvedHead)
          \(styleTag)
        </head>
        <body\(bodyAttr)>
          \(body)
          \(scriptTag)
        </body>
        </html>
        """
    }
}
