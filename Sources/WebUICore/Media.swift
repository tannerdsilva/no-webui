// MARK: - Track Kind
public enum TrackKind: String, Sendable {
	case subtitles = "subtitles"
	case captions = "captions"
	case descriptions = "descriptions"
	case chapters = "chapters"
	case metadata = "metadata"
}

// MARK: - Loading Strategy
public enum LoadingStrategy: String, Sendable {
	case eager = "eager"
	case lazy = "lazy"
}

// MARK: - Iframe Sandbox
/// one token of the html `sandbox` attribute. the raw value is the token
/// spelled in the attribute; the set a frame is built with is rendered joined
/// by spaces.
public enum IframeSandbox: String, CaseIterable, Sendable {
	case allowDownloads = "allow-downloads"
	case allowForms = "allow-forms"
	case allowModals = "allow-modals"
	case allowOrientationLock = "allow-orientation-lock"
	case allowPointerLock = "allow-pointer-lock"
	case allowPopups = "allow-popups"
	case allowPopupsToEscapeSandbox = "allow-popups-to-escape-sandbox"
	case allowPresentation = "allow-presentation"
	case allowSameOrigin = "allow-same-origin"
	case allowScripts = "allow-scripts"
	case allowTopNavigation = "allow-top-navigation"
	case allowTopNavigationByUserActivation = "allow-top-navigation-by-user-activation"
	case allowTopNavigationToCustomProtocols = "allow-top-navigation-to-custom-protocols"

}

extension Set where Element == IframeSandbox {
	/// the default sandbox set: empty — no permissions at all. `allow-scripts`
	/// is deliberately absent, so an embed cannot run script unless an author
	/// widens the set. emitted as `sandbox=""`, the strictest form the
	/// attribute has. living on `Set` (not the element type) so the
	/// `Set<IframeSandbox> = .strict` default resolves.
	public static let strict: Set<IframeSandbox> = []
}

// MARK: - Source
/// a media candidate for `Video`, `Audio`, or `Picture`: the browser picks
/// the first candidate it can play, so a host lists sources from most to
/// least preferred. the `src` runs `sanitizeURL` exactly as `Image` and
/// `Link` do — a `javascript:`/`data:` source is dropped from the document
/// entirely, never emitted.
public struct Source: View {
	public let src: String
	public let type: String
	public let media: String?

	public init(src: String, type: String, media: String? = nil) {
		self.src = src
		self.type = type
		self.media = media
	}

	public func render(into buffer: inout HTMLBuffer) {
		guard let safeSrc = sanitizeURL(src) else { return }
		var attributes = " src=\"\(htmlEscape(safeSrc))\" type=\"\(htmlEscape(type))\""
		if let media { attributes += " media=\"\(htmlEscape(media))\"" }
		buffer.voidElement("source", attributes)
	}
}

// MARK: - Track
/// a text track (captions, subtitles, chapters, ...) for `Video` or `Audio`.
/// `srclang` is required by the spec when the kind is `subtitles` or
/// `captions`, and the primitive enforces the pair by making it a plain
/// parameter rather than an optional. the `src` runs `sanitizeURL`; a hostile
/// one drops the track.
public struct Track: View {
	public let src: String
	public let kind: TrackKind
	public let srclang: String
	public let label: String
	public let `default`: Bool

	public init(src: String, kind: TrackKind, srclang: String, label: String, default: Bool = false) {
		self.src = src
		self.kind = kind
		self.srclang = srclang
		self.label = label
		self.default = `default`
	}

	public func render(into buffer: inout HTMLBuffer) {
		guard let safeSrc = sanitizeURL(src) else { return }
		var attributes = " src=\"\(htmlEscape(safeSrc))\" kind=\"\(kind.rawValue)\" srclang=\"\(htmlEscape(srclang))\" label=\"\(htmlEscape(label))\""
		if `default` { attributes += " default" }
		buffer.voidElement("track", attributes)
	}
}

// MARK: - Video
/// an html5 video with an optional set of `Track`/`Source` children.
///
/// both `src` and `poster` run `sanitizeURL`: a hostile `src` drops the whole
/// element, a hostile `poster` is omitted while the video still renders. the
/// boolean flags map to the bare `controls`/`autoplay`/`muted`/`loop`/
/// `playsinline` attributes (unspecified means absent).
///
/// csp note: the served default policy has no `media-src` directive, so media
/// falls back to `default-src 'self'` and the browser blocks a `data:` or
/// `blob:` source with `MEDIA_ERR_SRC_NOT_SUPPORTED` (error code 4). a host
/// that wants inline media adds `media-src` itself — e.g. through
/// `HTMLDocument`'s `contentSecurityPolicyExtras: "media-src 'self' data: blob:"`
/// (the wave-4.1 event-deck fixture does exactly this). the framework's
/// default csp is intentionally left untouched.
public struct Video: View {
	public let src: String
	public let poster: String?
	public let controls: Bool
	public let autoplay: Bool
	public let muted: Bool
	public let loop: Bool
	public let playsInline: Bool
	public let tracks: [any View]

	public init(
		src: String,
		poster: String? = nil,
		controls: Bool = true,
		autoplay: Bool = false,
		muted: Bool = false,
		loop: Bool = false,
		playsInline: Bool = false,
		@ViewBuilder tracks: () -> [any View]
	) {
		self.src = src
		self.poster = poster
		self.controls = controls
		self.autoplay = autoplay
		self.muted = muted
		self.loop = loop
		self.playsInline = playsInline
		self.tracks = tracks()
	}

	public func render(into buffer: inout HTMLBuffer) {
		guard let safeSrc = sanitizeURL(src) else { return }
		var attributes = " src=\"\(htmlEscape(safeSrc))\""
		if let poster, let safePoster = sanitizeURL(poster) {
			attributes += " poster=\"\(htmlEscape(safePoster))\""
		}
		if controls { attributes += " controls" }
		if autoplay { attributes += " autoplay" }
		if muted { attributes += " muted" }
		if loop { attributes += " loop" }
		if playsInline { attributes += " playsinline" }
		buffer.beginElement("video", attributes)
		buffer.endOpenTag()
		for track in tracks {
			track.render(into: &buffer)
		}
		buffer.endElement()
	}
}

// MARK: - Audio
/// an html5 audio element with an optional set of `Track`/`Source` children.
///
/// `src` runs `sanitizeURL`: a hostile source drops the whole element.
///
/// csp note: same as `Video` — the served default policy has no `media-src`
/// directive, so a `data:` or `blob:` source is blocked by the browser
/// (`MEDIA_ERR_SRC_NOT_SUPPORTED`, error code 4). a host adds `media-src`
/// itself through `HTMLDocument`'s `contentSecurityPolicyExtras`; the
/// framework default csp is not changed here.
public struct Audio: View {
	public let src: String
	public let controls: Bool
	public let autoplay: Bool
	public let muted: Bool
	public let loop: Bool
	public let tracks: [any View]

	public init(
		src: String,
		controls: Bool = true,
		autoplay: Bool = false,
		muted: Bool = false,
		loop: Bool = false,
		@ViewBuilder tracks: () -> [any View]
	) {
		self.src = src
		self.controls = controls
		self.autoplay = autoplay
		self.muted = muted
		self.loop = loop
		self.tracks = tracks()
	}

	public func render(into buffer: inout HTMLBuffer) {
		guard let safeSrc = sanitizeURL(src) else { return }
		var attributes = " src=\"\(htmlEscape(safeSrc))\""
		if controls { attributes += " controls" }
		if autoplay { attributes += " autoplay" }
		if muted { attributes += " muted" }
		if loop { attributes += " loop" }
		buffer.beginElement("audio", attributes)
		buffer.endOpenTag()
		for track in tracks {
			track.render(into: &buffer)
		}
		buffer.endElement()
	}
}

// MARK: - Picture
/// an html5 `<picture>`: a set of `Source` candidates (with `media`/`type`
/// constraints, in preference order) followed by the `Image` fallback the
/// browser shows when none match. every child carries `sanitizeURL` itself,
/// so a `javascript:`/`data:` candidate never reaches the document.
public struct Picture: View {
	public let tracks: [any View]

	public init(@ViewBuilder tracks: () -> [any View]) {
		self.tracks = tracks()
	}

	public func render(into buffer: inout HTMLBuffer) {
		buffer.beginElement("picture", "")
		buffer.endOpenTag()
		for track in tracks {
			track.render(into: &buffer)
		}
		buffer.endElement()
	}
}

// MARK: - Iframe
/// an embedded browsing context.
///
/// the `sandbox` attribute is ALWAYS emitted, defaulting to `.strict` — an
/// empty permission set rendered as `sandbox=""`, the strictest form the
/// attribute has. `allow-scripts` is absent by default, so a scripted embed
/// stays inert unless the author widens the set deliberately. the attribute
/// never disappears: an iframe without a `sandbox` attribute is
/// unrestricted, and that state is not reachable through this initializer by
/// accident.
///
/// `src` runs `sanitizeURL` exactly as `Image`/`Link` do — a `javascript:` or
/// `data:` source drops the whole frame. `allow` holds permissions-policy
/// tokens (`"camera"`, `"microphone"`, ...), rendered in sorted order so the
/// attribute is deterministic.
public struct Iframe: View {
	public let src: String
	public let title: String
	public let sandbox: Set<IframeSandbox>
	public let allow: Set<String>
	public let loading: LoadingStrategy

	public init(
		src: String,
		title: String,
		sandbox: Set<IframeSandbox> = .strict,
		allow: Set<String> = [],
		loading: LoadingStrategy = .lazy
	) {
		self.src = src
		self.title = title
		self.sandbox = sandbox
		self.allow = allow
		self.loading = loading
	}

	public func render(into buffer: inout HTMLBuffer) {
		guard let safeSrc = sanitizeURL(src) else { return }
		var attributes = " src=\"\(htmlEscape(safeSrc))\" title=\"\(htmlEscape(title))\""
		let tokens = sandbox.map(\.rawValue).sorted()
		attributes += " sandbox=\"\(htmlEscape(tokens.joined(separator: " ")))\""
		if !allow.isEmpty {
			let policies = allow.sorted().joined(separator: "; ")
			attributes += " allow=\"\(htmlEscape(policies))\""
		}
		attributes += " loading=\"\(loading.rawValue)\""
		buffer.voidElement("iframe", attributes)
	}
}

// MARK: - Canvas
/// a drawing surface. the `id` is what an `IslandRegion` pairs with — this
/// primitive only emits the element; painting behaviour comes from the island
/// that targets it. dimensions are declared (css can still scale the box).
public struct Canvas: View {
	public let id: String
	public let width: Int
	public let height: Int

	public init(id: String, width: Int, height: Int) {
		self.id = id
		self.width = width
		self.height = height
	}

	public func render(into buffer: inout HTMLBuffer) {
		buffer.voidElement("canvas", " id=\"\(htmlEscape(id))\" width=\"\(width)\" height=\"\(height)\"")
	}
}
