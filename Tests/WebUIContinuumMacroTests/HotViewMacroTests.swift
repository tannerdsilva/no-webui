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

@_expose(wasm, "feed_encode")
func _continuumEncodeFeed() -> [UInt8] {
	Feed.FeedIsland._continuumEncode()
}

@_expose(wasm, "feed_decode")
func _continuumDecodeFeed() -> [HotEffect] {
	Feed.FeedIsland._continuumDecode()
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

		// t2.3 codec entry points (CONTINUUM_DX W2, lane D — d-docs codec design):
		// the runtime slice owns the retained state per wasm instance; the
		// generated adapter carries none, so an untethered surface reports the
		// drained batch. bodies delegate to the runtime slice's record codec on
		// the record-v1 plane — the exact HotOpCodec webui_take_ops serves
		// (IslandRuntime.swift); `IslandRuntime<<Type>Island>.encodedState()` /
		// `.decodePendingOps()` swap these bodies verbatim when lane C's accessors
		// land (d-to-c.md).
		static func _continuumEncode() -> [UInt8] {
			// the pending op batch, record-v1 — the drained batch is empty.
			(try? HotOpCodec.encodeBatch([])) ?? []
		}

		static func _continuumDecode() -> [HotEffect] {
			// the drained (empty) record stream decodes to no records — the
			// record-decode loop is exercised for real by the equivalence suite
			// on recorded record-v1 batches.
			guard let op = try? HotOpCodec.decode([]) else {
			    return []
			}
			return [.ops([op])]
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

@_expose(wasm, "feed_encode")
func _continuumEncodeFeed() -> [UInt8] {
	Feed.FeedIsland._continuumEncode()
}

@_expose(wasm, "feed_decode")
func _continuumDecodeFeed() -> [HotEffect] {
	Feed.FeedIsland._continuumDecode()
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

		// t2.3 codec entry points (CONTINUUM_DX W2, lane D — d-docs codec design):
		// the runtime slice owns the retained state per wasm instance; the
		// generated adapter carries none, so an untethered surface reports the
		// drained batch. bodies delegate to the runtime slice's record codec on
		// the record-v1 plane — the exact HotOpCodec webui_take_ops serves
		// (IslandRuntime.swift); `IslandRuntime<<Type>Island>.encodedState()` /
		// `.decodePendingOps()` swap these bodies verbatim when lane C's accessors
		// land (d-to-c.md).
		static func _continuumEncode() -> [UInt8] {
			// the pending op batch, record-v1 — the drained batch is empty.
			(try? HotOpCodec.encodeBatch([])) ?? []
		}

		static func _continuumDecode() -> [HotEffect] {
			// the drained (empty) record stream decodes to no records — the
			// record-decode loop is exercised for real by the equivalence suite
			// on recorded record-v1 batches.
			guard let op = try? HotOpCodec.decode([]) else {
			    return []
			}
			return [.ops([op])]
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

@_expose(wasm, "feed_encode")
func _continuumEncodeFeed() -> [UInt8] {
	Feed.FeedIsland._continuumEncode()
}

@_expose(wasm, "feed_decode")
func _continuumDecodeFeed() -> [HotEffect] {
	Feed.FeedIsland._continuumDecode()
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

		// t2.3 codec entry points (CONTINUUM_DX W2, lane D — d-docs codec design):
		// the runtime slice owns the retained state per wasm instance; the
		// generated adapter carries none, so an untethered surface reports the
		// drained batch. bodies delegate to the runtime slice's record codec on
		// the record-v1 plane — the exact HotOpCodec webui_take_ops serves
		// (IslandRuntime.swift); `IslandRuntime<<Type>Island>.encodedState()` /
		// `.decodePendingOps()` swap these bodies verbatim when lane C's accessors
		// land (d-to-c.md).
		public static func _continuumEncode() -> [UInt8] {
			// the pending op batch, record-v1 — the drained batch is empty.
			(try? HotOpCodec.encodeBatch([])) ?? []
		}

		public static func _continuumDecode() -> [HotEffect] {
			// the drained (empty) record stream decodes to no records — the
			// record-decode loop is exercised for real by the equivalence suite
			// on recorded record-v1 batches.
			guard let op = try? HotOpCodec.decode([]) else {
			    return []
			}
			return [.ops([op])]
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

	@Test("the expansion synthesizes no Codable — the embed gate (c-to-d.md)")
	func embedCodableGate() {
		let text = expandedText(of: completeFeedFixture)
		#expect(!text.contains("Codable"))
		#expect(!text.contains("JSONEncoder"))
		#expect(!text.contains("JSONDecoder"))
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

	@Test("imports: without a budget auto-defaults (the DX-3 measured pin) — the imports:→budget rule retires")
	func importsWithoutBudgetExpands() {
		let text = expandedText(of: """
		@HotView("feed", imports: [ClockCapability.self])
		struct Feed {
			typealias State = FeedState
			typealias Action = FeedAction
			@HotBuilder func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
			static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
		}
		""")
		#expect(text.contains("static let continuumDescriptor"))
		#expect(text.contains("grants: [ClockCapability.self]"))
		// the auto/unset marker: budget: is tightening-only, the measured
		// auto-pin applies (DX-3, lane B's islands[] row).
		#expect(text.contains("IslandBudget(maxBytes: 0, maxGzipBytes: nil)"))
	}

	@Test("a declared pin of 0 bytes is the auto spelling taken as a pin — refused with the fix")
	func budgetZeroThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed", imports: [ClockCapability.self], budget: IslandBudget(maxBytes: 0))
			struct ZeroPin {
				typealias State = FeedState
				typealias Action = FeedAction
				@HotBuilder func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
				static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
			}
			""",
			message: "@HotView: a declared maxBytes: of 0 is the auto/unset spelling, not a pin — omit budget: (the measured auto-pin applies); if you meant a ceiling, declare a positive maxBytes:"
		)
	}

	@Test("a non-literal budget is refused — budget: pins are literals, tightening-only")
	func budgetNonLiteralThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed", budget: IslandBudget(maxBytes: pin))
			struct Computed {
				typealias State = FeedState
				typealias Action = FeedAction
				@HotBuilder func render(state: State) -> HotTree { Hot.Text(id: "feed-status", "ready") }
				static func reduce(state: inout State, action: Action) -> [HotEffect] { [] }
				static let pin = 1024
			}
			""",
			message: "@HotView: budget: must be an IslandBudget pin with a positive integer maxBytes: — e.g. budget: IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096) (budget: is tightening-only; omit it to auto-pin from the measured row)"
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

	// MARK: registry markers final — the strict marker-form diagnostics

	@Test("a name with whitespace is refused — the strict marker form the scan consumes")
	func strictNameSpacesThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed feed")
			struct TwoWords {
			}
			""",
			message: "@HotView: the island name must be a single token of letters, digits, '-' and '_' (the strict marker form the registry scan consumes) — \"feed feed\" contains ' '; it becomes the wasm export suffix, the URL segment, and the manifest key"
		)
	}

	@Test("a name starting with a digit is refused")
	func strictNameDigitStartThrows() {
		assertExpansionThrows(
			"""
			@HotView("1feed")
			struct LeadingDigit {
			}
			""",
			message: "@HotView: the island name must be a single token starting with a letter or underscore, e.g. @HotView(\"feed\") — \"1feed\" does not; it becomes the wasm export suffix, the URL segment, and the manifest key"
		)
	}

	@Test("two @HotView attributes on one declaration are a duplicate registry marker")
	func duplicateAttributeThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed")
			@HotView("grid")
			struct TwoIslands {
			}
			""",
			message: "@HotView applied 2 times — one declaration registers exactly one island; remove the duplicate attribute (pick the one name)"
		)
	}

	@Test("an author-declared continuumDescriptor collides with the generated one — fix hint, not a redeclaration error")
	func collidingDescriptorThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed")
			struct HasDescriptor {
				static let continuumDescriptor = "mine"
			}
			""",
			message: "@HotView: your declared `static let continuumDescriptor` would collide with the generated one — @HotView emits it; remove yours (or drop @HotView and hand-write the ContinuumServerPath conformance)"
		)
	}

	@Test("an author-declared island adapter type collides with the generated one — fix hint naming the generated name")
	func collidingAdapterThrows() {
		assertExpansionThrows(
			"""
			@HotView("feed")
			struct HasAdapter {
				struct HasAdapterIsland {
				}
			}
			""",
			message: "@HotView: your declared `HasAdapterIsland` would collide with the generated island adapter — @HotView emits it; rename your member (the generated adapter is named `HasAdapterIsland`)"
		)
	}
}