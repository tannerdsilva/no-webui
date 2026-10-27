import Foundation
import Testing

// MARK: - C7: the no-silent-degrade guard
//
// design C's thesis is that a degradation is a *value* — a status, a throw, a
// counter — never a branch that returns quietly. a behavioural test cannot see
// the failure mode this track exists to prevent: the damage is a branch that
// was DELETED, so the test that would catch it is the one nobody wrote. this
// suite is the alarm on that door. it reads the four files the track owns and
// fails, naming `file:line: text`, when a silent path comes back.
//
// every rule below names the silent path it defends (plan §7.1) and the reason
// it is a scan rather than an assertion about behaviour.
//
// the scan is deliberately narrow: a `close` is not banned, it is *accounted
// for* — the legacy opt-in, the responder's post-write close, the read-idle
// window, and the logged pipeline failure are the four accounted sites, and a
// fifth one fails this test.

@Suite("no silent degrade")
struct NoSilentDegradeGuardTests {

	// MARK: reading the tree

	/// repo root, derived from this file's own path so the scan follows the
	/// checkout: `<root>/Tests/WebUITests/NoSilentDegradeGuardTests.swift`
	private static let root = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	private static func lines(of relativePath: String) throws -> [String] {
		let url = root.appendingPathComponent(relativePath)
		let text = try String(contentsOf: url, encoding: .utf8)
		return text.components(separatedBy: .newlines)
	}

	private static let admission = "Sources/WebUIServer/Admission.swift"
	private static let events = "Sources/WebUICore/EventHandling.swift"
	private static let crypto = "Sources/WebUI/Crypto.swift"
	private static let gate = "Sources/WebUI/ConnectionGate.swift"

	/// `path:line: text` — the shape a failure names its offender with.
	private static func offender(_ path: String, _ number: Int, _ text: String) -> String {
		"\(path):\(number): \(text.trimmingCharacters(in: .whitespaces))"
	}

	/// the line numbers whose text contains `needle`.
	private static func lineNumbers(_ lines: [String], containing needle: String) -> [Int] {
		lines.enumerated().compactMap { $0.element.contains(needle) ? $0.offset : nil }
	}

	/// the nearest preceding line (inclusive of `index - lookback`) matching one
	/// of `anchors`, or nil.
	private static func anchor(
		_ lines: [String],
		before index: Int,
		lookback: Int,
		anyOf anchors: [String]
	) -> String? {
		let start = max(0, index - lookback)
		for candidate in stride(from: index, through: start, by: -1) where candidate < lines.count {
			let text = lines[candidate]
			if anchors.contains(where: { text.contains($0) }) { return text }
		}
		return nil
	}

	// MARK: the rules

	/// §7.1 path 1: admission at the connection cap.
	///
	/// `close(promise: nil)` is not banned — a refused connection must be
	/// closed eventually. it is banned *unaccounted for*: a close that is not in
	/// one of the four branches below is a refusal with no status, no log and no
	/// counter, which is exactly what C2 removes.
	@Test("every close on the admission path is accounted for")
	func admissionClosesAreAccounted() throws {
		let lines = try Self.lines(of: Self.admission)
		// the four accounted sites, each named by the branch it sits in.
		let accounted = [
			"case .close:",              // the explicit 1.x opt-in
			"catch {",                   // the logged pipeline-install failure
			"context.writeAndFlush",     // the responder's close, after the 503 is written
			"IdleStateEvent",            // the read-idle window: a connect that sent nothing
		]
		var offenders: [String] = []
		for number in Self.lineNumbers(lines, containing: "close(promise: nil)") {
			if Self.anchor(lines, before: number, lookback: 8, anyOf: accounted) == nil {
				offenders.append(Self.offender(Self.admission, number + 1, lines[number]))
			}
		}
		#expect(
			offenders.isEmpty,
			"an unaccounted close is a capacity refusal nobody can see — a status, a log and a counter are the minimum (plan §7.1 path 1)"
		)
		for offender in offenders { Issue.record("unaccounted close: \(offender)") }
	}

	/// §7.2 rule 1: the decision itself is counted before it is returned.
	@Test("the capacity decision records before it refuses")
	func decisionRecordsBeforeRefusing() throws {
		let lines = try Self.lines(of: Self.admission)
		let decide = try #require(
			Self.lineNumbers(lines, containing: "func decide()").first,
			"Admission.swift no longer has a decide(): the decision moved somewhere this guard cannot see"
		)
		let window = Array(lines[decide..<min(lines.count, decide + 20)])
		let record = window.firstIndex(where: { $0.contains("record(refusal)") })
		let refuse = window.firstIndex(where: { $0.contains("return .refuse(") })
		#expect(record != nil, "decide() must record the refusal: file: \(Self.admission), from line \(decide + 1)")
		if let record, let refuse {
			#expect(record < refuse, "the refusal must be counted and logged before it is returned")
		}
		// one decision point, so no second path can acquire without counting
		let acquisitions = Self.lineNumbers(lines, containing: "gate.tryAcquire()")
		#expect(
			acquisitions.count == 1,
			"the admission path must decide in exactly one place; found \(acquisitions.count)"
		)
	}

	/// §7.2 rule 1: the default disposition must stay loud.
	@Test("the refused-connection default answers rather than closing")
	func defaultDispositionAnswers() throws {
		let lines = try Self.lines(of: Self.admission)
		#expect(
			Self.lineNumbers(lines, containing: "disposition: AdmissionDisposition = .answer").count == 1,
			"the default disposition must remain `.answer`: `.close` is an explicit 1.x opt-in, never a default"
		)
		#expect(
			Self.lineNumbers(lines, containing: "disposition: AdmissionDisposition = .close").isEmpty,
			"a `.close` default would restore the silent refusal C2 removes"
		)
	}

	/// §7.1 path 2: `EventRouter`'s handler cap.
	///
	/// the old shape was `logger.warning(...)` then `return`. the new shape must
	/// record a `WebUIFailure` at the cap and hand it to a policy switch — a
	/// `guard ... else { return }` that returns without switching is the silent
	/// path again, wearing the new vocabulary.
	@Test("the handler cap records a failure instead of returning quietly")
	func handlerCapRecords() throws {
		let lines = try Self.lines(of: Self.events)
		#expect(
			Self.lineNumbers(lines, containing: "WebUIFailure.handlerCapReached(").isEmpty == false,
			"the cap must produce the vocabulary's value"
		)
		#expect(
			Self.lineNumbers(lines, containing: "state.recordFailure(refusal, in: session)").isEmpty == false,
			"the cap must record the refusal on the session, or nothing can raise it"
		)

		let guardLine = try #require(
			Self.lineNumbers(lines, containing: "guard registration == .capReached else { return }").first,
			"the cap check moved: this guard can no longer see it"
		)
		let following = Array(lines[(guardLine + 1)..<min(lines.count, guardLine + 4)])
		#expect(
			following.contains(where: { $0.contains("switch policy") }),
			"a `.capReached` that is not followed by the policy switch is the silent return again: \(Self.offender(Self.events, guardLine + 1, lines[guardLine]))"
		)

		// the warning is now the DEGRADE branch only, never the strict default
		for number in Self.lineNumbers(lines, containing: "handler cap reached") {
			guard lines[number].contains("logger.warning") else { continue }
			let degrade = Self.anchor(lines, before: number, lookback: 4, anyOf: ["case .degrade:"])
			if degrade == nil {
				Issue.record(
					"a warning outside `.degrade` is a silent cap: \(Self.offender(Self.events, number + 1, lines[number]))"
				)
			}
		}
	}

	/// §7.2 rule 3: a cap refuses a newcomer, so the strict door must throw.
	@Test("the strict session door throws")
	func beginStrictThrows() throws {
		let lines = try Self.lines(of: Self.events)
		let index = try #require(
			Self.lineNumbers(lines, containing: "public func beginStrict(").first,
			"beginStrict is the only door that refuses a newcomer; it is gone"
		)
		let signature = Array(lines[index..<min(lines.count, index + 4)]).joined(separator: " ")
		#expect(
			signature.contains("throws"),
			"beginStrict must throw `atCapacity(.sessions)` rather than evict a live page: \(Self.offender(Self.events, index + 1, lines[index]))"
		)
		// and the session cap's value must be the vocabulary's, not a message
		#expect(
			Self.lineNumbers(lines, containing: "WebUIFailure.atCapacity(kind: .sessions").isEmpty == false,
			"the session cap must refuse with `atCapacity(.sessions)`"
		)
	}

	/// §7.2 rule 4: entropy failure fails the render, so the strict door throws
	/// and there is no empty-token fallback on the path.
	@Test("the entropy door throws instead of substituting a token")
	func entropyDoorThrows() throws {
		let lines = try Self.lines(of: Self.crypto)
		#expect(
			Self.lineNumbers(lines, containing: "throw WebUIFailure.entropyUnavailable").isEmpty == false,
			"the strict entropy door must throw `entropyUnavailable`"
		)
		for number in Self.lineNumbers(lines, containing: "requireBytes") {
			#expect(
				lines[number].contains("?? []") == false,
				"an empty-token fallback is a tokenless page: \(Self.offender(Self.crypto, number + 1, lines[number]))"
			)
		}
		// the gate itself is a counter: it must not learn to close a socket
		#expect(
			Self.lineNumbers(try Self.lines(of: Self.gate), containing: "close(").isEmpty,
			"ConnectionGate counts slots; the refusal decision belongs to Admission, where it is logged and answered"
		)
	}
}
