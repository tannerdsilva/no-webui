// DO NOT EDIT BY HAND — this file is GENERATED from the real expander's output.
//
// the expected expansions below are the byte-exact text the in-process
// expander (the assertMacroExpansion-exact call) produced at capture time;
// the dump harness wrote them to disk and this file spliced them verbatim.
// re-freeze when the generated shape changes: re-run the dump harness, never
// hand-edit these strings.
import SwiftSyntaxMacros

struct FrozenFixture {
	let name: String
	let source: String
	let expanded: String
}

/// the frozen live-data expansions, captured from the real expander.
let frozenFixtures: [FrozenFixture] = [
	FrozenFixture(
		name: "group",
		source: 	#"""
	@LiveRegions
	struct DemoRegions {
		@LiveRegion(id: "g-region-b")
		struct Tick {
			@RegionState let box: LiveBox<Int>
			func render() async -> String? { "<div id=\"g-region-b\">\(box.value)</div>" }
		}
		@LiveState
		actor Feed {
			private var value = 0
			func bump() { value += 1; notify() }
			func snapshot() -> Int { value }
		}
		var tick = Tick(box: LiveBox(0))
		var feed = Feed()
		var clock = ClosureLiveRegion(id: "g-region-a") { () async -> String? in "<div id=\"g-region-a\">…</div>" }
		var countBox = LiveBox(0)
		var count = StateLiveRegion(id: "g-region-c", state: countBox) { box in box.value }
	}
	"""#,
		expanded: 	#"""
	struct DemoRegions {
		struct Tick {
			let box: LiveBox<Int>
			func render() async -> String? { "<div id=\"g-region-b\">\(box.value)</div>" }

		    var id: String {
		        "g-region-b"
		    }

		    var cadence: Duration? {
		        nil
		    }

		    var source: (any LiveState)? {
		        box
		    }
		}
		actor Feed {
			private var value = 0
			func bump() { value += 1; notify() }
			func snapshot() -> Int { value }

		    private let liveNotifier = LiveNotifier()

		    nonisolated func subscribe(_ onChange: @escaping @Sendable () -> Void) -> LiveSubscription {
		    	liveNotifier.add(onChange)
		    }

		    func notify() {
		    	liveNotifier.notify()
		    }
		}
		var tick = Tick(box: LiveBox(0))
		var feed = Feed()
		var clock = ClosureLiveRegion(id: "g-region-a") { () async -> String? in "<div id=\"g-region-a\">…</div>" }
		var countBox = LiveBox(0)
		var count = StateLiveRegion(id: "g-region-c", state: countBox) { box in box.value }

	    var registry: WebUILiveRegions {
	        WebUILiveRegions([tick, clock, count])
	    }
	}

	extension DemoRegions.Tick: LiveRegion {
	}

	extension DemoRegions.Feed: LiveState {
	}
	"""#,
	),
	FrozenFixture(
		name: "publicRegion",
		source: 	#"""
	@LiveRegion(id: "g-region-d")
	public struct PublicRegion {
		@RegionState let box: LiveBox<Int>
		public func render() async -> String? { "<div id=\"g-region-d\">\(box.value)</div>" }
	}
	"""#,
		expanded: 	#"""
	public struct PublicRegion {
		let box: LiveBox<Int>
		public func render() async -> String? { "<div id=\"g-region-d\">\(box.value)</div>" }

	    public var id: String {
	        "g-region-d"
	    }

	    public var cadence: Duration? {
	        nil
	    }

	    public var source: (any LiveState)? {
	        box
	    }
	}

	extension PublicRegion: LiveRegion {
	}
	"""#,
	),
	FrozenFixture(
		name: "regionCadence",
		source: 	#"""
	@LiveRegion(id: "g-region-c", cadence: .seconds(2))
	struct Periodic {
		@RegionState let box: LiveBox<Int>
		func render() async -> String? { "<div id=\"g-region-c\">\(box.value)</div>" }
	}
	"""#,
		expanded: 	#"""
	struct Periodic {
		let box: LiveBox<Int>
		func render() async -> String? { "<div id=\"g-region-c\">\(box.value)</div>" }

	    var id: String {
	        "g-region-c"
	    }

	    var cadence: Duration? {
	        .seconds(2)
	    }

	    var source: (any LiveState)? {
	        box
	    }
	}

	extension Periodic: LiveRegion {
	}
	"""#,
	),
	FrozenFixture(
		name: "regionNoSource",
		source: 	#"""
	@LiveRegion(id: "g-region-a")
	struct Driven {
		func render() async -> String? { "<div id=\"g-region-a\">tick</div>" }
	}
	"""#,
		expanded: 	#"""
	struct Driven {
		func render() async -> String? { "<div id=\"g-region-a\">tick</div>" }

	    var id: String {
	        "g-region-a"
	    }

	    var cadence: Duration? {
	        nil
	    }

	    var source: (any LiveState)? {
	        nil
	    }
	}

	extension Driven: LiveRegion {
	}
	"""#,
	),
	FrozenFixture(
		name: "regionSource",
		source: 	#"""
	@LiveRegion(id: "g-region-b")
	struct Tick {
		@RegionState let box: LiveBox<Int>
		func render() async -> String? { "<div id=\"g-region-b\">\(box.value)</div>" }
	}
	"""#,
		expanded: 	#"""
	struct Tick {
		let box: LiveBox<Int>
		func render() async -> String? { "<div id=\"g-region-b\">\(box.value)</div>" }

	    var id: String {
	        "g-region-b"
	    }

	    var cadence: Duration? {
	        nil
	    }

	    var source: (any LiveState)? {
	        box
	    }
	}

	extension Tick: LiveRegion {
	}
	"""#,
	),
	FrozenFixture(
		name: "stateActor",
		source: 	#"""
	@LiveState
	actor Feed {
		private var value = 0
		func bump() { value += 1; notify() }
		func snapshot() -> Int { value }
	}
	"""#,
		expanded: 	#"""
	actor Feed {
		private var value = 0
		func bump() { value += 1; notify() }
		func snapshot() -> Int { value }

	    private let liveNotifier = LiveNotifier()

	    nonisolated func subscribe(_ onChange: @escaping @Sendable () -> Void) -> LiveSubscription {
	    	liveNotifier.add(onChange)
	    }

	    func notify() {
	    	liveNotifier.notify()
	    }
	}

	extension Feed: LiveState {
	}
	"""#,
	)
]
