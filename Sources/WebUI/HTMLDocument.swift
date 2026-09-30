import Foundation
import Logging

// MARK: - HTMLDocument
public struct HTMLDocument: Sendable {
    public let title: String
    public let body: String
    public let styles: CSSStylesheet
    public let rawStyles: [String]
    public let scripts: String
    public let head: String
    public let bodyAttributes: String
    /// Attributes for the `<html>` element, verbatim — the mirror of ``bodyAttributes``.
    ///
    /// Exists for the pre-attribute case: a theme is scoped to `:root`, so a *server-rendered*
    /// default scheme has to land on `<html>` before the engine can override it from storage.
    /// Without it the only choices were to inline a script or to put the attribute somewhere the
    /// theme selectors do not look.
    public let htmlAttributes: String
    /// the client-mode boot: when set, the document emits the `webui-wasm`
    /// contract + external chamber/boot scripts and substitutes the client csp
    /// (`'wasm-unsafe-eval'`) for the default nonce policy; the inline server
    /// runtime is suppressed (the wasm chamber replaces it).
    public let clientMode: ClientBoot?
    public let devMode: Bool
    public let lang: String
    /// the document's base direction (`ltr` / `rtl`). nil omits the
    /// attribute entirely, so the default document stays byte-identical.
    public let dir: String?
    public let includeRuntime: Bool
    /// Emit a pre-paint theme prelude: a one-line inline script that applies the stored
    /// scheme and mode to `<html>` before the first paint.
    ///
    /// Without it a client with a stored choice sees the *default* palette flash, because
    /// the engine applies the stored theme when it boots — after the first paint. Inline is
    /// the only option: `defer`/`async` scripts run too late by definition, so the prelude
    /// carries the render nonce to satisfy the csp invariant (#1).
    ///
    /// Only emitted when a client runtime is present: the engine owns the same storage keys,
    /// and without it nothing would honour what the prelude sets.
    public let themePrelude: Bool
    /// A content-addressed theme catalog to LINK, after the base sheet.
    ///
    /// The theme is not inlined when this is set: the sheet is cacheable, so a second
    /// navigation transfers zero theme bytes.
    public let themeStylesheetURL: String?
    public let runtimeConfig: RuntimeConfig?
    /// The policy for this document.
    ///
    /// When set it is used verbatim — after `contentSecurityPolicyExtras`, if any, merges
    /// into it. A policy that names no `'nonce-…'` source also disables the pre-paint theme
    /// prelude (`render()` logs a warning when that happens). A host that only needs
    /// additional directives should leave this nil and pass ``contentSecurityPolicyExtras``
    /// instead, which extends the framework's nonce-aware default.
    public let contentSecurityPolicy: String?
    /// Directives merged per name into the effective policy — ``contentSecurityPolicy``
    /// when set, otherwise the framework's nonce-aware default.
    ///
    /// The seam for the common case: a host needs `img-src … https:`, a `font-src`, or a
    /// `form-action` on top of the default. Restating the whole policy to get one of those
    /// is what drops the render nonce — and with it the pre-paint theme prelude, which the
    /// browser then refuses as an unauthorised inline script.
    public let contentSecurityPolicyExtras: String?
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
    /// (next architecture, `NEXT_ARCHITECTURE.md`). capability islands are
    /// declared per page.
    public static let defaultBoot = ClientBoot()
    /// ` dir="rtl"` when a base direction is set. only `ltr`/`rtl` are ever
    /// emitted: anything else is dropped rather than written into the page.
    private var dirAttribute: String {
        guard let dir else { return "" }
        let value = dir.lowercased()
        guard value == "ltr" || value == "rtl" else { return "" }
        return " dir=\"\(value)\""
    }

    private func effectiveCSP(nonce: String, clientMode: ClientBoot?) -> String? {
        if let csp = contentSecurityPolicy {
            guard !csp.isEmpty else { return nil }
            return ClientBoot.merging(policy: csp, extras: contentSecurityPolicyExtras)
        }
        guard clientMode != nil else {
            // a document with no client runtime needs no wasm-unsafe-eval and
            // no ws connect-src: scripts are external same-origin only
            // (default-src 'self'), inline styles stay permitted for the
            // page-scoped sheet.
            return ClientBoot.merging(
                policy: "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;",
                extras: contentSecurityPolicyExtras
            )
        }
        // the client runtime needs wasm-unsafe-eval (the chamber compiles the
        // module) and the render's nonce: the pre-paint prelude is an inline script,
        // and a policy that names no nonce source blocks it outright.
        return ClientBoot.csp(nonce: nonce, extras: contentSecurityPolicyExtras)
    }
    public init(
        title: String = "WebUI",
        body: String,
        styles: CSSStylesheet = CSSStylesheet([]),
        rawStyles: [String] = [],
        scripts: String = "",
        head: String = "",
        bodyAttributes: String = "",
        htmlAttributes: String = "",
        clientMode: ClientBoot? = nil,
        devMode: Bool = false,
        lang: String = "en",
        dir: String? = nil,
        includeRuntime: Bool = true,
        themePrelude: Bool = true,
        runtimeConfig: RuntimeConfig? = nil,
        contentSecurityPolicy: String? = nil,
        contentSecurityPolicyExtras: String? = nil,
        icon: String = Self.defaultIcon,
        preMinifiedStyles: Bool = false,
        stylesheetURL: String? = nil,
        themeStylesheetURL: String? = nil
    ) {
        self.title = title
        self.body = body
        self.styles = styles
        self.rawStyles = rawStyles
        self.scripts = scripts
        self.head = head
        self.bodyAttributes = bodyAttributes
        self.htmlAttributes = htmlAttributes
        self.clientMode = clientMode
        self.devMode = devMode
        self.lang = lang
        self.dir = dir
        self.includeRuntime = includeRuntime
        self.themePrelude = themePrelude
        self.runtimeConfig = runtimeConfig
        self.contentSecurityPolicy = contentSecurityPolicy
        self.contentSecurityPolicyExtras = contentSecurityPolicyExtras
        self.icon = icon
        self.preMinifiedStyles = preMinifiedStyles
        self.themeStylesheetURL = themeStylesheetURL
        self.stylesheetURL = stylesheetURL
        self.nonce = Self.generateNonce()
    }
    private static let documentLogger = Logger(label: "webui.document")

    /// The pre-paint prelude, verbatim.
    ///
    /// One line, no comments: this is bytes the client parses before it can paint anything
    /// (the first law applies to every shipped web asset, and this one is on the critical
    /// path). The storage keys and attribute names are the **engine's**; `ThemePreludeTests`
    /// reads the engine asset and asserts they still agree, so the two cannot drift apart
    /// without a test failing.
    static let themePreludeScript =
        "(function(){try{var r=document.documentElement,"
        + "m=localStorage.getItem('webui-theme'),s=localStorage.getItem('webui-scheme');"
        + "if(m)r.setAttribute('data-theme',m);if(s)r.setAttribute('data-scheme',s);}"
        + "catch(e){}})();"

    public func render() -> String {
        let boot: ClientBoot?
        if let clientMode {
            // an explicit client-mode wins regardless of includeRuntime (its
            // contract meta + scripts are pinned by the client-surface tests).
            boot = clientMode
        } else if includeRuntime {
            let base = Self.defaultBoot
            if let cfg = runtimeConfig, !cfg.isEmpty {
                boot = ClientBoot(config: cfg)
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
        let preludeTag: String
        // an inline script only runs when the effective policy names its nonce (a
        // nil policy allows it). suppressing the prelude beats emitting a script the
        // browser refuses: the failure is otherwise a console error plus a silent
        // theme flash, which is exactly how this went unnoticed.
        let inlineScriptsAllowed = cspValue.map { $0.contains("'nonce-") } ?? true
        if themePrelude, boot != nil, inlineScriptsAllowed {
            preludeTag = "<script nonce=\"\(htmlEscape(nonce))\">\(Self.themePreludeScript)</script>"
        } else {
            if themePrelude, boot != nil {
                Self.documentLogger.warning(
                    "theme prelude suppressed: the effective Content-Security-Policy names no nonce source, so inline scripts cannot run — a stored theme choice will flash on first paint. add `'nonce-…'` to script-src (see ClientBoot.csp(nonce:)), extend the default policy with `contentSecurityPolicyExtras:` instead of restating it, or pass themePrelude: false"
                )
            }
            preludeTag = ""
        }
        let stylesheetTag: String
        if let url = stylesheetURL {
            stylesheetTag = "  <link rel=\"stylesheet\" href=\"\(htmlEscape(url))\">\n"
        } else {
            stylesheetTag = ""
        }
        // the theme sheet links AFTER the base one: same specificity, later source order, so
        // its `:root` tokens win the cascade. emitted here rather than through `head` for
        // exactly that reason — `head` renders before the base sheet.
        let themeStylesheetTag: String
        if let url = themeStylesheetURL {
            themeStylesheetTag = "  <link rel=\"stylesheet\" href=\"\(htmlEscape(url))\">\n"
        } else {
            themeStylesheetTag = ""
        }

        return """
        <!DOCTYPE html>
        <html lang="\(lang)"\(htmlAttributes.isEmpty ? "" : " " + htmlAttributes)\(dirAttribute)>
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">\(cspTag)\(iconTag)
          <title>\(htmlEscape(title))</title>
          \(resolvedHead)\(preludeTag.isEmpty ? "" : "\n          " + preludeTag)
          \(stylesheetTag)\(themeStylesheetTag)\(styleTag)
        </head>
        <body\(bodyAttr)>
          \(body)
          \(scriptTag)
        </body>
        </html>
        """
    }
}
