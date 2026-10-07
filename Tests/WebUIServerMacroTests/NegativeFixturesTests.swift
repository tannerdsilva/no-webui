import Testing

// the live-data macro suite — the negative fixtures.
//
// every misuse in §3.1's diagnostic lists must produce a diagnostic. the
// assertions compare `context.diagnostics` MESSAGES (never positions, which
// shift across swift-syntax generations), through the raw expander — the
// same mechanism a real compiler run uses, so a diagnostic that stops firing
// fails this suite.

@Suite("the live-data macros — every misuse diagnoses (negative fixtures)")
struct NegativeFixturesTests {
	// MARK: feature A — @LiveRegion / @RegionState

	@Test("a non-type cannot carry @LiveRegion")
	func liveRegionOnEnum() {
		assertExpansionDiagnoses(
			#"@LiveRegion(id: "x") enum E { func render() async -> String? { nil } }"#,
			message: "@LiveRegion can only be applied to a struct, class or actor")
	}

	@Test("a protocol cannot carry @LiveRegion")
	func liveRegionOnProtocol() {
		assertExpansionDiagnoses(
			#"@LiveRegion(id: "x") protocol P { func render() async -> String?" }"#,
			message: "@LiveRegion can only be applied to a struct, class or actor")
	}

	@Test("@LiveRegion without an id is diagnosed")
	func liveRegionWithoutID() {
		assertExpansionDiagnoses(
			#"""
			@LiveRegion
			struct S {
				func render() async -> String? { nil }
			}
			"""#,
			message: "@LiveRegion requires an id: argument")
	}

	@Test("a non-literal id is diagnosed — the id is stated once, as a literal")
	func liveRegionNonLiteralID() {
		assertExpansionDiagnoses(
			#"""
			@LiveRegion(id: someConstant)
			struct S {
				func render() async -> String? { nil }
			}
			"""#,
			message: "@LiveRegion(id:) must be a string literal — the id is the DOM id and the pushed fragment id, stated once")
	}

	@Test("a missing render() is diagnosed")
	func liveRegionMissingRender() {
		assertExpansionDiagnoses(
			#"""
			@LiveRegion(id: "x")
			struct S {
				let box: LiveBox<Int>
			}
			"""#,
			message: "@LiveRegion requires the type to declare 'func render() async -> String?' in its body (a member added in an extension is invisible to this macro)")
	}

	@Test("a user-declared id colliding with the generated one is diagnosed")
	func liveRegionHandWrittenID() {
		assertExpansionDiagnoses(
			#"""
			@LiveRegion(id: "x")
			struct S {
				var id: String { "hand" }
				func render() async -> String? { nil }
			}
			"""#,
			message: "@LiveRegion generates 'id' — a hand-written 'id' on the same type is ambiguous; remove it")
	}

	@Test("a user-declared cadence colliding with the generated one is diagnosed")
	func liveRegionHandWrittenCadence() {
		assertExpansionDiagnoses(
			#"""
			@LiveRegion(id: "x")
			struct S {
				var cadence: Duration? { nil }
				func render() async -> String? { nil }
			}
			"""#,
			message: "@LiveRegion generates 'cadence' — a hand-written 'cadence' on the same type is ambiguous; remove it")
	}

	@Test("a user-declared source colliding with the generated one is diagnosed")
	func liveRegionHandWrittenSource() {
		assertExpansionDiagnoses(
			#"""
			@LiveRegion(id: "x")
			struct S {
				var source: (any LiveState)? { nil }
				func render() async -> String? { nil }
			}
			"""#,
			message: "@LiveRegion generates 'source' — a hand-written 'source' on the same type is ambiguous; remove it")
	}

	@Test("two @RegionState markers are diagnosed, naming both")
	func regionStateTwoMarkers() {
		assertExpansionDiagnoses(
			#"""
			@LiveRegion(id: "x")
			struct S {
				@RegionState let a: LiveBox<Int>
				@RegionState let b: LiveBox<Int>
				func render() async -> String? { nil }
			}
			"""#,
			message: "@RegionState marks 2 properties (a, b) — exactly one, or none, is allowed")
	}

	// MARK: feature B — @LiveRegions

	@Test("a non-struct/class cannot carry @LiveRegions")
	func liveRegionsOnActor() {
		assertExpansionDiagnoses(
			#"""
			@LiveRegions
			actor A {}
			"""#,
			message: "@LiveRegions can only be applied to a struct or class")
	}

	@Test("a group with zero region properties is diagnosed — an empty registry is a silent mistake")
	func liveRegionsEmpty() {
		assertExpansionDiagnoses(
			#"""
			@LiveRegions
			struct G {
				var countBox = LiveBox(0)
				var notifier = LiveNotifier()
			}
			"""#,
			message: "@LiveRegions found zero region properties — an empty registry is a silent mistake")
	}

	@Test("a member the macro cannot classify is diagnosed — never silently dropped")
	func liveRegionsUnknownExplicitType() {
		assertExpansionDiagnoses(
			#"""
			@LiveRegions
			struct G {
				var mystery: Widget
			}
			"""#,
			message: "@LiveRegions cannot tell whether 'mystery' ('Widget') is a live region — a region type carries @LiveRegion, a state type carries @LiveState; anything else does not belong in the group")
	}

	@Test("a member with neither a written type nor an initializer is diagnosed")
	func liveRegionsUnknownNoType() {
		assertExpansionDiagnoses(
			#"""
			@LiveRegions
			struct G {
				var mystery
			}
			"""#,
			message: "@LiveRegions cannot tell whether 'mystery' is a live region — give it an explicit type (`let mystery: SomeRegionType = …`), or move it out of the group")
	}

	@Test("duplicate live-region ids warn (with the earlier id's holder)")
	func liveRegionsDuplicateIDWarns() {
		assertExpansionWarns(
			#"""
			@LiveRegions
			struct G {
				@LiveRegion(id: "same")
				struct A {
					@RegionState let box: LiveBox<Int>
					func render() async -> String? { nil }
				}
				@LiveRegion(id: "same")
				struct B {
					@RegionState let box: LiveBox<Int>
					func render() async -> String? { nil }
				}
				var a = A(box: LiveBox(0))
				var b = B(box: LiveBox(0))
			}
			"""#,
			message: "duplicate live-region id 'same' — already used by an earlier member; the registry keeps the last definition")
	}

	@Test("an id the macro cannot compare says so (a warning, not silence)")
	func liveRegionsNonLiteralIDWarns() {
		assertExpansionWarns(
			#"""
			@LiveRegions
			struct G {
				var clock = ClosureLiveRegion(id: someVariable) {
					() async -> String? in nil
				}
			}
			"""#,
			message: "@LiveRegions cannot compare 'clock''s id — it is not a string literal, so a duplicate would go unnoticed")
	}

	// MARK: feature C — @LiveState

	@Test("a non-actor cannot carry @LiveState")
	func liveStateOnStruct() {
		assertExpansionDiagnoses(
			#"""
			@LiveState
			struct S {}
			"""#,
			message: "@LiveState can only be applied to an actor")
	}

	@Test("an actor that already declares subscribe is diagnosed")
	func liveStateExistingSubscribe() {
		assertExpansionDiagnoses(
			#"""
			@LiveState
			actor A {
				func subscribe(_ onChange: @escaping @Sendable () -> Void) -> LiveSubscription { LiveSubscription {} }
			}
			"""#,
			message: "@LiveState generates 'subscribe' — a hand-written 'subscribe' on the same actor is ambiguous; remove it")
	}

	@Test("an actor that already declares notify is diagnosed")
	func liveStateExistingNotify() {
		assertExpansionDiagnoses(
			#"""
			@LiveState
			actor A {
				func notify() {}
			}
			"""#,
			message: "@LiveState generates 'notify' — a hand-written 'notify' on the same actor is ambiguous; remove it")
	}

	@Test("an actor that already declares liveNotifier is diagnosed")
	func liveStateExistingLiveNotifier() {
		assertExpansionDiagnoses(
			#"""
			@LiveState
			actor A {
				var liveNotifier = LiveNotifier()
			}
			"""#,
			message: "@LiveState generates 'liveNotifier' — a hand-written 'liveNotifier' on the same actor is ambiguous; remove it")
	}
}
