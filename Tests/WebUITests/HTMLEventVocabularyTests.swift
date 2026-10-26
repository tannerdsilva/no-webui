import Foundation
import Synchronization
import Testing
import WebUI
import WebUICore

// `HTMLEvent` is the framework's one event vocabulary — the modifiers' declared
// type and the inbound frame's type. it is open by construction (`.custom`), so
// an event from a newer client still decodes and routes; that openness is also
// why the named cases can drift from the runtime silently, since nothing in the
// compiler knows `designer/assets/webui-runtime.js` exists. this suite is the
// pin: it parses the runtime's own `EVENT_TYPES` array and requires the enum to
// cover it name for name, and it pins the inverse mapping `init(rawValue:)`.

/// one parsed view of the runtime's vocabulary, or a recorded failure.
enum RuntimeEventVocabulary {
	/// the runtime file, located from the package root the way the other
	/// designer-asset tests do (`DeploymentIntegrityTests.packageRootURL`).
	static var assetURL: URL {
		packageRootURL().appendingPathComponent("designer/assets/webui-runtime.js")
	}

	/// every entry of `var EVENT_TYPES = [...]`, in source order.
	///
	/// fails loudly when the file is missing or the array cannot be found: a
	/// pin test that skips is a pin test that cannot fail.
	static func entries() throws -> [String] {
		let url = assetURL
		guard FileManager.default.fileExists(atPath: url.path) else {
			throw VocabularyError.unreadable(url.path)
		}
		let source: String
		do {
			source = try String(contentsOf: url, encoding: .utf8)
		} catch {
			throw VocabularyError.unreadable("\(url.path): \(error)")
		}

		guard let declaration = source.range(of: "EVENT_TYPES") else {
			throw VocabularyError.noDeclaration(url.path)
		}
		let tail = source[declaration.upperBound...]
		guard let open = tail.firstIndex(of: "["), let close = tail[open...].firstIndex(of: "]") else {
			throw VocabularyError.noDeclaration(url.path)
		}
		let body = tail[tail.index(after: open)..<close]

		// the array is a flat list of quoted strings; take each quoted run.
		var names: [String] = []
		var quote: Character?
		var current = ""
		for character in body {
			if let openQuote = quote {
				if character == openQuote {
					names.append(current)
					current = ""
					quote = nil
				} else {
					current.append(character)
				}
			} else if character == "'" || character == "\"" {
				quote = character
			}
		}
		guard !names.isEmpty else { throw VocabularyError.noDeclaration(url.path) }
		return names
	}

	enum VocabularyError: Error, CustomStringConvertible {
		case unreadable(String)
		case noDeclaration(String)

		var description: String {
			switch self {
			case .unreadable(let path):
				return "HTMLEvent pin: cannot read the runtime at \(path) — the vocabulary cannot be verified"
			case .noDeclaration(let path):
				return "HTMLEvent pin: no `EVENT_TYPES = [...]` array found in \(path) — the pin would silently pass"
			}
		}
	}
}

@Suite("HTMLEvent vocabulary")
struct HTMLEventVocabularyTests {

	/// the cases the runtime delegates for, referenced by name: renaming or
	/// removing one is a compile error here rather than a silent gap.
	private static let runtimeCases: [HTMLEvent] = [
		.click, .input, .change, .submit,
		.keydown, .keyup, .keypress,
		.focus, .blur, .focusin, .focusout,
		.mouseover, .mouseout, .mousedown, .mouseup,
	]

	@Test("every runtime EVENT_TYPES entry is a named HTMLEvent case")
	func runtimeVocabularyIsPinned() throws {
		let runtime = try RuntimeEventVocabulary.entries()

		// 1. every event the engine delegates for resolves to a NAMED case —
		//    falling through to `.custom` would still "work", which is exactly
		//    the silent drift this pin exists to catch.
		for name in runtime {
			#expect(
				HTMLEvent.named.contains(where: { $0.rawValue == name }),
				"HTMLEvent has no named case for the runtime event '\(name)' (designer/assets/webui-runtime.js EVENT_TYPES)"
			)
			#expect(HTMLEvent(rawValue: name).rawValue == name, "HTMLEvent round-trip changed '\(name)'")
		}

		// 2. and the cases do not outrun the runtime: a case the engine never
		//    dispatches is a lie about what the wire can carry.
		for event in Self.runtimeCases {
			#expect(
				runtime.contains(event.rawValue),
				"HTMLEvent.\(event.rawValue) has no entry in the runtime's EVENT_TYPES (designer/assets/webui-runtime.js)"
			)
		}

		#expect(Set(Self.runtimeCases.map(\.rawValue)) == Set(runtime))
		#expect(Self.runtimeCases.count == runtime.count)
	}

	@Test("init(rawValue:) is the inverse of rawValue for every named case")
	func namedCasesRoundTrip() {
		#expect(!HTMLEvent.named.isEmpty)
		for event in HTMLEvent.named {
			#expect(
				HTMLEvent(rawValue: event.rawValue) == event,
				"HTMLEvent(rawValue: \"\(event.rawValue)\") did not return its own case — a case is missing from `named`"
			)
		}
		// every named raw value is distinct, or the inverse is ambiguous.
		#expect(Set(HTMLEvent.named.map(\.rawValue)).count == HTMLEvent.named.count)
	}

	@Test("the vocabulary is open: an unknown event decodes and routes")
	func unknownEventStillRoutes() async throws {
		// an event this build has never heard of arrives from a newer client.
		let msg = try WSIncoming(
			jsonText: #"{"type":"event","component":"c0","event":"futuristicgesture","data":{},"token":"t"}"#
		)
		guard case .event(let component, let event, _, let token) = msg else {
			Issue.record("expected an event message")
			return
		}
		#expect(component == "c0")
		#expect(HTMLEvent(rawValue: event) == .custom("futuristicgesture"))
		#expect(token == "t")

		// a registered handler still receives it — the enum does not filter.
		let router = EventRouter()
		let session = RenderSessionID.default
		router.begin(session)
		let seen = Mutex<HTMLEvent?>(nil)
		router.register({ data in
			seen.withLock { $0 = data.event }
			return []
		}, for: ComponentID("c0"), in: session)

		_ = await router.handle(
			EventData(component: "c0", event: HTMLEvent(rawValue: event)), in: session
		)
		#expect(seen.withLock { $0 } == .custom("futuristicgesture"))

		// and an unregistered component misses quietly (empty outcome, debug log).
		let missed = await router.handle(
			EventData(component: "nobody", event: HTMLEvent(rawValue: event)), in: session
		)
		#expect(missed.isEmpty)
	}

	@Test("the wire still carries a bare event string")
	func wireFormatUnchanged() throws {
		let encoded = try JSONEncoder().encode(
			EventData(component: ComponentID("c0"), event: .click, data: ["value": .string("x")])
		)
		let object = try #require(
			try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
		)
		#expect(object["event"] as? String == "click")

		// and the same bytes decode back into the enum — the change is a
		// Swift-side type, not a wire shape.
		let round = try JSONDecoder().decode(EventData.self, from: encoded)
		#expect(round.event == .click)
		#expect(round.component == ComponentID("c0"))

		// string literals keep the modifier-facing spelling: `event: "click"`.
		let literal: EventData = EventData(component: "c0", event: "click")
		#expect(literal.event == .click)
		#expect(literal.event.rawValue == "click")
	}
}