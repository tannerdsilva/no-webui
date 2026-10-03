import Testing
@testable import WebUIContinuumMacros

// MARK: - expansion fixtures
//
// wave-2 signature: name + `imports:` (HostCapability types) + `budget:`
// (IslandBudget; required when imports are declared). generated members are
// asserted by name here; the compiled end-to-end fixture and the
// hand-written-equivalent rule live in the sibling files of this target.

private let completeFeedFixture = """
@HotView("feed")
struct Feed {
	typealias State = FeedState
	typealias Action = FeedAction
	@HotBuilder func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
	static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
}
"""

@Suite("@HotView macro expansion")
struct HotViewMacroExpansionTests {

	@Test("name-only: descriptor, island adapter, expose shims, server path")
	func nameOnly() {
		assertExpansion(
			completeFeedFixture,
			expanded: """
struct Feed {
	typealias State = FeedState
	typealias Action = FeedAction
	@HotBuilder func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
	static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
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
		    IslandBudget(maxBytes: 0, maxGzipBytes: nil)
		}

		static func reduce(state: inout State, action: Action) -> [HotEffect] {
			Feed.reduce(state: &state, action: action)
		}

		// island exports. the @_expose names are the t2.3 ABI contract;
		// bodies land with the island runtime slice (the frame-buffer op loop).
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

	@Test("imports: + budget: flow into the descriptor and the island adapter")
	func importsAndBudget() {
		assertExpansion(
			"""
			@HotView("feed", imports: [ClockCapability.self, LogCapability.self], budget: IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096))
			struct Feed {
				typealias State = FeedState
				typealias Action = FeedAction
				@HotBuilder func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
				static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
			}
			""",
			expanded: """
struct Feed {
	typealias State = FeedState
	typealias Action = FeedAction
	@HotBuilder func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
	static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
}

extension Feed: ContinuumServerPath {
	static let continuumDescriptor = ContinuumDescriptor(
		name: "feed",
		grants: [ClockCapability.self, LogCapability.self],
		budget: IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096),
		className: ""
	)

	struct FeedIsland: ContinuumIsland {
		typealias State = Feed.State
		typealias Action = Feed.Action
		static var name: String {
		    "feed"
		}
		static var imports: [any HostCapability.Type] {
		    [ClockCapability.self, LogCapability.self]
		}
		static var budget: IslandBudget {
		    IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096)
		}

		static func reduce(state: inout State, action: Action) -> [HotEffect] {
			Feed.reduce(state: &state, action: action)
		}

		// island exports. the @_expose names are the t2.3 ABI contract;
		// bodies land with the island runtime slice (the frame-buffer op loop).
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

	@Test("a public struct gets public generated members; a sibling @HotClass feeds className")
	func publicWithClasses() {
		assertExpansion(
			"""
			@HotView("feed", imports: [ClockCapability.self], budget: IslandBudget(maxBytes: 4_096))
			@HotClass("feed-item", "feed-item__meta")
			public struct Feed {
				public typealias State = FeedState
				public typealias Action = FeedAction
				@HotBuilder public func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
				public static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
			}
			""",
			expanded: """
public struct Feed {
	public typealias State = FeedState
	public typealias Action = FeedAction
	@HotBuilder public func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
	public static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }

    public static let continuumClasses: [String] = ["feed-item", "feed-item__meta"]
}

extension Feed: ContinuumServerPath {
	public static let continuumDescriptor = ContinuumDescriptor(
		name: "feed",
		grants: [ClockCapability.self],
		budget: IslandBudget(maxBytes: 4_096),
		className: "feed-item feed-item__meta"
	)

	public struct FeedIsland: ContinuumIsland {
		public typealias State = Feed.State
		public typealias Action = Feed.Action
		public static var name: String {
		    "feed"
		}
		public static var imports: [any HostCapability.Type] {
		    [ClockCapability.self]
		}
		public static var budget: IslandBudget {
		    IslandBudget(maxBytes: 4_096)
		}

		public static func reduce(state: inout State, action: Action) -> [HotEffect] {
			Feed.reduce(state: &state, action: action)
		}

		// island exports. the @_expose names are the t2.3 ABI contract;
		// bodies land with the island runtime slice (the frame-buffer op loop).
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
		let text = expandedText(of: """
		@HotView("feed", imports: [ClockCapability.self], budget: IslandBudget(maxBytes: 16_384))
		struct Feed {
			typealias State = FeedState
			typealias Action = FeedAction
			@HotBuilder func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
			static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
		}
		""")
		for expected in [
			"continuumDescriptor", "FeedIsland", "ContinuumIsland", "ContinuumServerPath",
			"_continuumEncode", "_continuumDecode", "@_expose(wasm",
			"name: \"feed\"", "grants: [ClockCapability.self]",
			"budget: IslandBudget(maxBytes: 16_384)",
			"imports: [any HostCapability.Type]", "[ClockCapability.self]",
		] {
			#expect(text.contains(expected), "missing \(expected) in expansion")
		}
		#expect(!text.contains("continuumClasses")) // no @HotClass sibling → no inventory
		#expect(text.contains("Feed.reduce(state: &state, action: action)"))
	}

	@Test("name-only stays additive: the declaration is untouched")
	func additive() {
		let text = expandedText(of: completeFeedFixture)
		#expect(text.contains("struct Feed {"))
		#expect(text.contains("extension Feed: ContinuumServerPath"))
		#expect(text.contains("static let continuumDescriptor"))
		// the name-only sentinel: no imports, the "unset" budget.
		#expect(text.contains("grants: []"))
		#expect(text.contains("IslandBudget(maxBytes: 0, maxGzipBytes: nil)"))
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

	@Test("a second unlabeled argument throws — imports:/budget: are labeled")
	func extraArgumentThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed", "grid")
			struct TwoNames {
			}
			""",
			message: "@HotView takes exactly one island name — the first, unlabeled argument; capabilities go in imports: and the pin in budget:"
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

	@Test("an unknown labeled argument is refused with the accepted spelling")
	func unknownArgumentThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed", provider: SomethingElse.self)
			struct Stray {
			}
			""",
			message: "unknown @HotView argument `provider:` — the accepted spelling is @HotView(\"feed\") or @HotView(\"feed\", imports: [ClockCapability.self], budget: IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096))"
		)
	}

	@Test("duplicate imports: throws")
	func duplicateImportsThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed", imports: [ClockCapability.self], imports: [LogCapability.self])
			struct Twice {
			}
			""",
			message: "@HotView takes at most one imports: argument"
		)
	}

	@Test("wire-string imports are refused with the fix")
	func wireStringImportsThrow() {
		assertExpansionThrows(
			"""
			@HotView("feed", imports: ["clock"])
			struct Stringy {
			}
			""",
			message: "imports: takes HostCapability types, not wire strings or values — write imports: [ClockCapability.self]; a capability's wireName is its wire spelling"
		)
	}

	@Test("imports: without a budget is refused — a sized island pins one")
	func missingBudgetThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed", imports: [ClockCapability.self])
			struct Unpinned {
				typealias State = FeedState
				typealias Action = FeedAction
				@HotBuilder func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
				static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
			}
			""",
			message: "@HotView: missing budget: — a declaration that names host imports is a sized island; add budget: IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096) (the budget plugin pins it before ship)"
		)
	}

	@Test("missing State/Action throws, naming both")
	func missingStateActionThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed")
			struct Bare {
			}
			""",
			message: "@HotView requires `State` and `Action` — declare `typealias State = …` (a HotState) / `typealias Action = …` (a HotAction); the generated island adapter forwards them"
		)
	}

	@Test("a missing Action alone is named alone")
	func missingActionAloneThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed")
			struct HalfBare {
				typealias State = FeedState
			}
			""",
			message: "@HotView requires `Action` — declare `typealias State = …` (a HotState) / `typealias Action = …` (a HotAction); the generated island adapter forwards them"
		)
	}

	@Test("a missing hot body is refused with the declaration to write")
	func missingRenderThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed")
			struct Bodyless {
				typealias State = FeedState
				typealias Action = FeedAction
				static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
			}
			""",
			message: "@HotView requires the hot body — declare `@HotBuilder func render(state: State) -> HotTree { … }`"
		)
	}

	@Test("a render without @HotBuilder is refused")
	func renderNotHotBuilderThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed")
			struct Unbuilt {
				typealias State = FeedState
				typealias Action = FeedAction
				func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
				static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
			}
			""",
			message: "@HotView: render(state:) must be @HotBuilder — annotate it so the body is type-checked against the hot vocabulary (Hot.Text, Hot.Container, Hot.Spacer)"
		)
	}

	@Test("an explicitly empty imports: does not require a budget (equivalent to absent)")
	func emptyImportsNoBudgetExpands() {
		let text = expandedText(of: """
		@HotView("feed", imports: [])
		struct Feed {
			typealias State = FeedState
			typealias Action = FeedAction
			@HotBuilder func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
			static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
		}
		""")
		#expect(text.contains("static let continuumDescriptor"))
		#expect(text.contains("IslandBudget(maxBytes: 0, maxGzipBytes: nil)"))
	}
}