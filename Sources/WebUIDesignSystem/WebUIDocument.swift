import Foundation
import WebUI

// MARK: - WebUIDocument
public struct WebUIDocument: View {
	public let title: String
	public let body: String
	public let scripts: String
	/// Raw `<head>` markup, verbatim — the escape hatch; prefer ``headContent``.
	public let head: String
	/// typed head content (metas, open-graph, JSON-LD, links, scripts) — carried
	/// to `HTMLDocument`, which renders it with the render nonce.
	public let headContent: HeadContent?
	public let bodyAttributes: String
	public let devMode: Bool
	public let lang: String
	/// the document's locale (BCP-47), feeding `<html lang>`; wins over ``lang``
	/// when both are set (W4.5).
	public let locale: String?
	/// the page's string catalog (W4.5). nil keeps every component's English
	/// default; set it (with ``locale`` and ``direction``) and the render pass
	/// resolves `RenderContext.currentStrings` to this catalog.
	public let strings: WebUIStrings?
	/// the document's base direction (`ltr` / `rtl`); nil omits the attribute.
	public let dir: String?
	/// the typed base direction; wins over ``dir`` when both are set.
	public let direction: Directionality?
	public let includeRuntime: Bool
	public let runtimeConfig: RuntimeConfig?
	public let contentSecurityPolicy: String?
	/// Directives merged per name into the effective policy (the framework's nonce-aware
	/// default, or ``contentSecurityPolicy`` when set) — see `HTMLDocument`.
	public let contentSecurityPolicyExtras: String?
	public let theme: WebUITheme
	public let clientMode: ClientBoot?
	public let rawStyles: [String]
	/// Host-defined ``StyleSheet``s, forwarded to the document — emitted after
	/// the framework sheet and the theme, so a host component wins the cascade
	/// by origin. a page without any is byte-identical to one that never heard
	/// of the type.
	public let styleSheets: [StyleSheet]
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
		headContent: HeadContent? = nil,
		bodyAttributes: String = "",
		clientMode: ClientBoot? = nil,
		devMode: Bool = false,
		lang: String = "en",
		locale: String? = nil,
		strings: WebUIStrings? = nil,
		dir: String? = nil,
		direction: Directionality? = nil,
		includeRuntime: Bool = true,
		runtimeConfig: RuntimeConfig? = nil,
		contentSecurityPolicy: String? = nil,
		contentSecurityPolicyExtras: String? = nil,
		theme: WebUITheme = .standard,
		rawStyles: [String] = [],
		styleSheets: [StyleSheet] = [],
		stylesheetURL: String? = DesignSystemAssets.stylesheetURL,
		themeStylesheetURL: String? = nil,
		checkClasses: Bool = false
	) {
		self.title = title
		self.body = body
		self.scripts = scripts
		self.head = head
		self.headContent = headContent
		self.bodyAttributes = bodyAttributes
		self.clientMode = clientMode
		self.devMode = devMode
		self.lang = lang
		self.locale = locale
		self.strings = strings
		self.dir = dir
		self.direction = direction
		self.includeRuntime = includeRuntime
		self.runtimeConfig = runtimeConfig
		self.contentSecurityPolicy = contentSecurityPolicy
		self.contentSecurityPolicyExtras = contentSecurityPolicyExtras
		self.theme = theme
		self.rawStyles = rawStyles
		self.styleSheets = styleSheets
		self.stylesheetURL = stylesheetURL
		self.themeStylesheetURL = themeStylesheetURL
		self.checkClasses = checkClasses
	}

	/// the design-system sheet (layout rules + embedded css), minified once —
	/// the same bytes the servers serve on `/__assets/css` (see
	/// `DesignSystemAssets.minifiedCss`), so a page that links instead of
	/// inlining is byte-equivalent.
	public static let minifiedDesignStyles: String = DesignSystemAssets.minifiedCss

	public func render(into buffer: inout HTMLBuffer) {
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
		// the island wiring: every `data-webui-island="..."` region in the
		// body — typed `IslandRegion` or hand-rolled raw markup alike —
		// declares a capability, and declaring it is the whole grant. fold
		// the collected names into whichever config the page emits, so the
		// engine's lazy fetch mounts the region with no manual `capabilities`
		// entry. an empty body stays byte-identical: no declared islands, no
		// config touched.
		let declared = Self.declaredIslandNames(in: body)
		let effectiveRuntimeConfig: RuntimeConfig?
		let effectiveClientMode: ClientBoot?
		if declared.isEmpty {
			effectiveRuntimeConfig = runtimeConfig
			effectiveClientMode = clientMode
		} else {
			effectiveRuntimeConfig = runtimeConfig?.addingCapabilities(declared)
			if let clientMode {
				effectiveClientMode = ClientBoot(
					config: (clientMode.config ?? RuntimeConfig()).addingCapabilities(declared)
				)
			} else if runtimeConfig == nil {
				// a bare declaration with no config at all still grants: the
				// engine boots with a capabilities-only config.
				effectiveClientMode = ClientBoot(config: RuntimeConfig(capabilities: declared))
			} else {
				effectiveClientMode = nil
			}
		}

		let doc = HTMLDocument(
			title: title,
			body: body,
			styles: CSSStylesheet([]),
			rawStyles: rawStyles,
			styleSheets: styleSheets,
			scripts: scripts,
			head: head,
			headContent: headContent,
			bodyAttributes: bodyAttributes,
			clientMode: effectiveClientMode,
			devMode: devMode,
			lang: locale ?? lang,
			dir: dir,
			direction: direction,
			includeRuntime: includeRuntime,
			runtimeConfig: effectiveRuntimeConfig,
			contentSecurityPolicy: contentSecurityPolicy,
			contentSecurityPolicyExtras: contentSecurityPolicyExtras,
			preMinifiedStyles: true,
			stylesheetURL: stylesheetURL,
			themeStylesheetURL: themeStylesheetURL,
			// inline mode carries the sheet in rawStyles (see the rawStyles
			// block above) — the missing-sheet diagnostics must stay quiet
			inlinedComponentStyles: stylesheetURL == nil
		)
		let html = doc.renderedString()
		if checkClasses {
			HTMLClassValidator.report(html: html)
		}
		buffer.append(html)
	}



	/// render this document and hand it out as the body of a typed response —
	/// the bridge a page render uses now that renders answer with
	/// ``HTTPResponse``. a page that must set a cookie (or a status, or a
	/// header) on GET builds its document and enriches the response here, so
	/// the cookie rides the same response as the page itself.
	///
	/// the parameter is spelled `WebUISharedCore.HTTPCookie` because this file
	/// imports Foundation, which would make the bare name ambiguous with
	/// `NSHTTPCookie`.
	public func renderedResponse(
		status: HTTPStatus = .ok,
		headers: [String: String] = [:],
		cookies: [WebUISharedCore.HTTPCookie] = []
	) -> HTTPResponse {
		HTTPResponse(
			status: status,
			headers: headers,
			cookies: cookies,
			body: .html(renderThroughBuffer())
		)
	}

	/// every island capability declared by a body: the `data-webui-island`
	/// mount-point names, in first-seen order, deduplicated. typed
	/// `IslandRegion` regions and hand-rolled raw mount points both count —
	/// declaring a region is what grants its capability, and this scan is the
	/// collector `render(into:)` folds into the emitted config.
	///
	/// names are framework-controlled identifiers; the scan still skips empty
	/// captures and treats the attribute as double-quoted, so a stray
	/// single-quoted copy in prose cannot silently grant a capability.
	package static func declaredIslandNames(in body: String) -> [String] {
		let pattern = /data-webui-island="([^"]*)"/
		var seen = Set<String>()
		var names: [String] = []
		for match in body.matches(of: pattern) {
			let name = String(match.1)
			if !name.isEmpty, seen.insert(name).inserted {
				names.append(name)
			}
		}
		return names
	}
}
