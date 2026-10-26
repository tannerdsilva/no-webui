import Foundation
import Testing

// the modifier contract has one path, pinned structurally.
//
// `ModifierDecorateTests` proves the two doors agree for every modifier that
// exists today — a behavioural test of the current set. this suite pins the set
// itself. a modifier added later cannot inherit a string round-trip implicitly,
// because the two places that turn generic content into a string are named
// here, and a third one fails this suite instead of quietly landing on the slow
// path the old default `decorate` used to select for it.
//
// this is a source scan, and a source scan is a weak gate: it cannot prove a new
// modifier is correct, only that the list of round-trips did not grow without
// someone editing this file on purpose. that is exactly the shape of the
// mistake it guards — the previous default made the round-trip invisible, so
// nothing in the tree recorded how many modifiers were paying for it.

@Suite("the modifier contract has one path (source pin)")
struct ModifierContractPinTests {
	enum PinError: Error {
		/// the scan found no sources, or a source it could not read. a pin test
		/// that skips when it cannot see the tree is a pin test that cannot fail.
		case unreadable(String)
	}

	/// every Swift file under `Sources/`, as (package-relative path, text).
	static func sources() throws -> [(path: String, text: String)] {
		let root = packageRootURL().appendingPathComponent("Sources")
		guard let walker = FileManager.default.enumerator(atPath: root.path) else {
			throw PinError.unreadable(root.path)
		}
		var files: [(path: String, text: String)] = []
		for case let relative as String in walker where relative.hasSuffix(".swift") {
			let url = root.appendingPathComponent(relative)
			guard let text = try? String(contentsOf: url, encoding: .utf8) else {
				throw PinError.unreadable(url.path)
			}
			files.append(("Sources/" + relative, text))
		}
		guard !files.isEmpty else { throw PinError.unreadable(root.path) }
		return files.sorted { $0.path < $1.path }
	}

	@Test("apply(to:) is declared once, as the derived door in ModifiedView")
	func applyIsDerivedOnly() throws {
		let declarations = try Self.sources()
			.filter { $0.text.contains("func apply(to html: String)") }
			.map(\.path)
		// a second declaration is a conformer that kept the 1.x requirement. the
		// derived door is the only legitimate one: it runs `decorate`, so both
		// doors are one behaviour.
		#expect(declarations == ["Sources/WebUICore/ModifiedView.swift"])
	}

	@Test("the ViewModifier protocol requires decorate and nothing else")
	func protocolRequiresOnlyDecorate() throws {
		let files = try Self.sources()
		let file = try #require(files.first { $0.path == "Sources/WebUICore/View.swift" })
		let body = try #require(Self.protocolBody(named: "ViewModifier", in: file.text))
		#expect(body.contains("func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer)"))
		#expect(!body.contains("func apply("))

		// one requirement, counted off the declaration lines rather than asserted
		// in a comment: a second `func` in this body is a second thing every
		// modifier must implement.
		let requirements = body.split(separator: "\n").filter { line in
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			return trimmed.hasPrefix("func ") || trimmed.hasPrefix("public func ")
		}
		#expect(requirements.count == 1)
	}

	@Test("only the type eraser renders generic content through markup.html")
	func onlyEraserUsesContentMarkup() throws {
		let roundTrips = try Self.sources()
			.filter { $0.text.contains("content.markup.html") }
			.map(\.path)
		#expect(roundTrips == ["Sources/WebUICore/ModifiedView.swift"])
	}

	@Test("only the icon size modifier re-renders its content into a scratch buffer")
	func onlyIconRewritesRenderedBytes() throws {
		let roundTrips = try Self.sources()
			.filter { $0.text.contains("content.render(into: &rendered)") }
			.map(\.path)
		#expect(roundTrips == ["Sources/WebUICore/Icon.swift"])
	}

	/// the text between `protocol <name>` and its closing brace, brace-counted so
	/// an unrelated `}` inside the body cannot truncate it early.
	static func protocolBody(named name: String, in text: String) -> String? {
		guard let start = text.range(of: "protocol \(name)") else { return nil }
		var depth = 0
		var began = false
		var end = start.upperBound
		for index in text[start.upperBound...].indices {
			switch text[index] {
			case "{":
				depth += 1
				began = true
			case "}":
				depth -= 1
				if began && depth == 0 {
					end = index
					return String(text[start.upperBound..<end])
				}
			default:
				continue
			}
		}
		return began ? String(text[start.upperBound..<end]) : nil
	}
}
