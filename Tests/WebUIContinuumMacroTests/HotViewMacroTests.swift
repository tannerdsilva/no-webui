import Testing
@testable import WebUIContinuumMacros

// MARK: - expansion fixtures
//
// wave-1 signature is name-only: @HotView("feed"). the imports:/budget: parameters
// and the view-side runtime protocols join in wave 2; the generated members
// reference the seam vocabulary (ContinuumDescriptor, ContinuumIsland,
// HostCapability, IslandBudget, HotEffect, ContinuumServerPath) by name only and
// are never compiled here — lane C's vocabulary is unmerged until integration.

@Suite("@HotView macro expansion")
struct HotViewMacroExpansionTests {

	@Test("name-only: descriptor, island adapter, expose shims, server path")
	func nameOnly() {
		assertExpansion(
			"""
@HotView("feed")
struct Feed {
}
""",
			expanded: """
struct Feed {
}

extension Feed: ContinuumServerPath {
	static let continuumDescriptor = ContinuumDescriptor(
		name: "feed",
		grants: [],
		budget: IslandBudget(maxBytes: 0, maxGzipBytes: nil),
		className: ""
	)

	struct FeedIsland: ContinuumIsland {
		typealias State = Feed.State
		typealias Action = Feed.Action
		static var name: String {
		    "feed"
		}
		static var imports: [any HostCapability.Type] {
		    []
		}
		static var budget: IslandBudget {
		    Feed.continuumDescriptor.budget
		}

		static func reduce(state: inout State, action: Action) -> [HotEffect] {
			Feed.reduce(state: &state, action: action)
		}

				// island exports. the @_expose names are the t2.3 ABI contract;
		// bodies land with the codec once lane C's record table is in.
				@_expose(wasm, "feed_encode")
				static func _continuumEncode() -> [UInt8] {
		    []
		}

		@_expose(wasm, "feed_decode")
		static func _continuumDecode() -> [HotEffect] {
		    []
		}
	}
}
"""
		)
}

	@Test("a public struct gets public generated members")
	func publicStruct() {
		assertExpansion(
			"""
@HotView("feed")
public struct PublicFeed {
}
""",
			expanded: """
public struct PublicFeed {
}

extension PublicFeed: ContinuumServerPath {
	public static let continuumDescriptor = ContinuumDescriptor(
		name: "feed",
		grants: [],
		budget: IslandBudget(maxBytes: 0, maxGzipBytes: nil),
		className: ""
	)

	public struct PublicFeedIsland: ContinuumIsland {
		public typealias State = PublicFeed.State
		public typealias Action = PublicFeed.Action
		public static var name: String {
		    "feed"
		}
		public static var imports: [any HostCapability.Type] {
		    []
		}
		public static var budget: IslandBudget {
		    PublicFeed.continuumDescriptor.budget
		}

		public static func reduce(state: inout State, action: Action) -> [HotEffect] {
			PublicFeed.reduce(state: &state, action: action)
		}

				// island exports. the @_expose names are the t2.3 ABI contract;
		// bodies land with the codec once lane C's record table is in.
				@_expose(wasm, "feed_encode")
				public static func _continuumEncode() -> [UInt8] {
		    []
		}

		@_expose(wasm, "feed_decode")
		public static func _continuumDecode() -> [HotEffect] {
		    []
		}
	}
}
"""
		)
}

	@Test("a sibling @HotClass feeds the descriptor's class vocabulary")
	func withSiblingHotClass() {
		assertExpansion(
			"""
@HotView("feed")
@HotClass("feed-item", "feed-item__meta")
public struct Feed {
}
""",
			expanded: """
public struct Feed {

    public static let continuumClasses: [String] = ["feed-item", "feed-item__meta"]
}

extension Feed: ContinuumServerPath {
	public static let continuumDescriptor = ContinuumDescriptor(
		name: "feed",
		grants: [],
		budget: IslandBudget(maxBytes: 0, maxGzipBytes: nil),
		className: "feed-item feed-item__meta"
	)

	public struct FeedIsland: ContinuumIsland {
		public typealias State = Feed.State
		public typealias Action = Feed.Action
		public static var name: String {
		    "feed"
		}
		public static var imports: [any HostCapability.Type] {
		    []
		}
		public static var budget: IslandBudget {
		    Feed.continuumDescriptor.budget
		}

		public static func reduce(state: inout State, action: Action) -> [HotEffect] {
			Feed.reduce(state: &state, action: action)
		}

				// island exports. the @_expose names are the t2.3 ABI contract;
		// bodies land with the codec once lane C's record table is in.
				@_expose(wasm, "feed_encode")
				public static func _continuumEncode() -> [UInt8] {
		    []
		}

		@_expose(wasm, "feed_decode")
		public static func _continuumDecode() -> [HotEffect] {
		    []
		}
	}
}
"""
		)
}

	@Test("every planned generated member is present by name")
	func memberNames() {
		let text = expandedText(of: "@HotView(\"feed\")\nstruct Feed {\n}")
		for expected in ["continuumDescriptor", "FeedIsland", "ContinuumIsland",
			"ContinuumServerPath", "_continuumEncode", "_continuumDecode",
			"@_expose(wasm", "name: \"feed\"", "grants: []"] {
			#expect(text.contains(expected), "missing \(expected) in expansion")
		}
		#expect(!text.contains("continuumClasses")) // no @HotClass sibling → no inventory
		#expect(text.contains("Feed.reduce(state: &state, action: action)"))
}

	@Test("name-only stays additive: the original declaration is untouched")
	func additive() {
		let text = expandedText(of: "@HotView(\"feed\")\nstruct Feed {\n}")
		#expect(text.contains("struct Feed {"))
		#expect(text.contains("extension Feed: ContinuumServerPath"))
		#expect(text.contains("static let continuumDescriptor"))
}
}

// MARK: - negative cases

@Suite("@HotView macro misuse")
struct HotViewMacroNegativeTests {

	@Test("non-struct targets throw")
	func nonStructThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed")
			class NotAView {
			}
			""",
			message: "@HotView can only be applied to a struct (the hot view); move the attribute onto the view type"
		)
}

	@Test("more than one argument throws (imports:/budget: arrive in wave 2)")
	func extraArgumentThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed", "grid")
			struct TwoNames {
			}
			""",
			message: "@HotView takes exactly one argument — the island name, as @HotView(\"feed\")"
		)
}

	@Test("an empty name throws")
	func emptyNameThrows() {
		assertExpansionThrows(
			"""
			@HotView("")
			struct Unnamed {
			}
			""",
			message: "@HotView requires a non-empty island name — as @HotView(\"feed\")"
		)
}

	@Test("a non-literal name throws")
	func nonLiteralNameThrows() {
		assertExpansionThrows(
			"""
			@HotView(feed)
			struct Referenced {
			}
			""",
			message: "continuum macros take string literals only, e.g. @HotView(\"feed\") or @HotClass(\"feed-item\")"
		)
}
}
