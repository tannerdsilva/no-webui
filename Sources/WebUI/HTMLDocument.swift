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
    /// the tab icon: a data-uri (2×-supersampled 32 px png of the accent
    /// rounded tile with the window glyph) so every host gets a branded tab
    /// without a `/favicon.ico` route — no http request, no 404, and the
    /// framework csp already permits `img-src data:`. pass an empty string to
    /// suppress it, or a full `<link ...>` element to override.
    public let icon: String
    public let nonce: String
    /// when `true`, the combined `styles` + `rawStyles` string is embedded
    /// verbatim instead of passed through `minifyCSS`. used by documents that
    /// pre-minify their (deterministic) stylesheet once at startup — hoisting
    /// the 300 kb design-system sheet out of every render removes the
    /// dominant per-request cost (measured ~10 ms in release).
    public let preMinifiedStyles: Bool
    /// when set, emitted as a cacheable `<link rel="stylesheet">` before the
    /// inline `<style>` (which keeps custom/page-scoped styles only).
    public let stylesheetURL: String?
    private static func generateNonce() -> String {
        guard let bytes = SecureRandom.bytes(16) else {
            // fail loud: silently falling back to a weaker nonce source would
            // ship a page whose csp nonce is not fully random. entropy failure
            // is a fatal system condition, not a fallback case.
            preconditionFailure("SecureRandom.bytes failed — cannot mint a csp nonce")
        }
        return Base64.encodeURL(bytes)
    }
    /// the default branded tab icon: a 2×-supersampled 32 px png of the accent
    /// rounded tile with the window glyph, inlined as a data-uri. inlined (not
    /// a route) so a bare host gets a branded tab with no `/favicon.ico` to
    /// serve — the browser never issues the request that would otherwise 404,
    /// and every framework csp already permits `img-src data:`.
    public static let defaultIcon = "<link rel=\"icon\" type=\"image/png\" href=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAApklEQVR4nO2XwQ2AIAxF2ahDeWQZb07idkINCQejECgpfDSS/BvQ118C1JhZB1lmsuyVxNLAjiwfynJFkBhcO/BdaYhBwfMQnWzPlgOZ/dOFeFJHA/h3AWy7TKoAzG1SAQjZhM2Wtd7eMDesKTghA5DW+HsA0kOoDtCib5XgB4ADwC4iQl/FVydgj1EnzQWA/ZIZ9KcU4AK0N6jqjjCtWQJkfHM6epyUsxUEgyvS4gAAAABJRU5ErkJggg==\">"
    /// the default client boot emitted when the caller omits `clientMode`.
    /// the engine is the default client runtime for server-rendered pages
    /// (next architecture, `NEXT_ARCHITECTURE.md`); the wasm client remains
    /// available via an explicit `ClientBoot(flavor: .wasm, …)` for applet
    /// and client-mode pages.
    public static let defaultBoot: ClientBoot = ClientBoot(
        flavor: .engine
    )
    private func effectiveCSP(nonce: String, clientMode: ClientBoot?) -> String? {
        if let csp = contentSecurityPolicy {
            return csp.isEmpty ? nil : csp
        }
        guard clientMode != nil else {
            // a document with no client runtime needs no wasm-unsafe-eval and
            // no ws connect-src: scripts are external same-origin only
            // (default-src 'self'), inline styles stay permitted for the
            // page-scoped sheet.
            return "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;"
        }
        // the client runtime needs wasm-unsafe-eval (the chamber compiles the
        // module); still `'self'`, still no `'unsafe-inline'` in script-src.
        return ClientBoot.defaultCSP
    }
    public init(
        title: String = "WebUI",
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
        icon: String = Self.defaultIcon,
        preMinifiedStyles: Bool = false,
        stylesheetURL: String? = nil
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
        self.icon = icon
        self.preMinifiedStyles = preMinifiedStyles
        self.stylesheetURL = stylesheetURL
        self.nonce = Self.generateNonce()
    }
    public func render() -> String {
        let boot: ClientBoot?
        if let clientMode {
            // an explicit client-mode wins regardless of includeRuntime (its
            // contract meta + scripts are pinned by the client-surface tests).
            boot = clientMode
        } else if includeRuntime {
            let base = Self.defaultBoot
            if let cfg = runtimeConfig, !cfg.isEmpty {
                boot = ClientBoot(wasmURL: base.wasmURL, mode: base.mode, config: cfg, scriptURLs: base.scriptURLs, flavor: base.flavor)
            } else {
                boot = base
            }
        } else {
            // includeRuntime: false = no client at all — no webui-config meta,
            // no engine/chamber script tag, no wasm permissive csp. this is
            // the parameter's documented meaning; it is what a static or
            // third-party-driven document asks for.
            boot = nil
        }
        let styleTag: String
        let scriptTag: String
        let cspValue = effectiveCSP(nonce: nonce, clientMode: boot)
        // the boot head (webui-config meta + engine/chamber scripts) is
        // appended to the caller's head slot when a runtime is present.
        let resolvedHead = head + (boot.map { "\n" + $0.headMarkup() } ?? "")

        if devMode {
            styleTag = "<link rel=\"stylesheet\" href=\"/ui/styles.css\">"
            let appSrc = scripts.isEmpty ? "" : "<script src=\"/ui/app.js\"></script>"
            scriptTag = appSrc
        } else {
            var cssParts: [String] = []
            let cssContent = styles.render()
            if !cssContent.isEmpty { cssParts.append(cssContent) }
            cssParts.append(contentsOf: rawStyles)
            let combinedCSS = cssParts.joined(separator: "\n\n")
            let allCSS = preMinifiedStyles ? combinedCSS : minifyCSS(combinedCSS)
            styleTag = allCSS.isEmpty ? "" : "<style>\n\(allCSS)\n</style>"

            // wasm-only client runtime: no inline server runtime is emitted
            // (the wasm chamber owns client behavior; caller raw `scripts` do
            // not run under the client csp).
            scriptTag = ""
        }

        let bodyAttr = bodyAttributes.isEmpty ? "" : " \(bodyAttributes)"
        let cspTag: String
        if let csp = cspValue {
            cspTag = "\n          <meta http-equiv=\"Content-Security-Policy\" content=\"\(csp)\">"
        } else {
            cspTag = ""
        }
        // the tab icon: a caller-supplied `<link>` wins (override); the
        // default brand mark lands otherwise; an empty string suppresses it.
        let iconTag = icon.isEmpty ? "" : "  \(icon)"
        let stylesheetTag: String
        if let url = stylesheetURL {
            stylesheetTag = "  <link rel=\"stylesheet\" href=\"\(htmlEscape(url))\">\n"
        } else {
            stylesheetTag = ""
        }

        return """
        <!DOCTYPE html>
        <html lang="\(lang)">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">\(cspTag)\(iconTag)
          <title>\(htmlEscape(title))</title>
          \(resolvedHead)
          \(stylesheetTag)\(styleTag)
        </head>
        <body\(bodyAttr)>
          \(body)
          \(scriptTag)
        </body>
        </html>
        """
    }
}
