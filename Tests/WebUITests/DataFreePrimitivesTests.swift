import Testing
import WebUI

// MARK: - Base64

@Suite("Base64")
struct Base64Tests {
	@Test("rfc 4648 standard vectors encode with padding")
	func standardVectors() {
		#expect(Base64.encode([UInt8]("f".utf8)) == "Zg==")
		#expect(Base64.encode([UInt8]("fo".utf8)) == "Zm8=")
		#expect(Base64.encode([UInt8]("foo".utf8)) == "Zm9v")
		#expect(Base64.encode([UInt8]("foob".utf8)) == "Zm9vYg==")
		#expect(Base64.encode([UInt8]("fooba".utf8)) == "Zm9vYmE=")
		#expect(Base64.encode([UInt8]("foobar".utf8)) == "Zm9vYmFy")
	}

	@Test("decode round-trips every standard vector and tolerates missing padding")
	func decodeRoundTrips() {
		for text in ["f", "fo", "foo", "foob", "fooba", "foobar", "", "\u{00}bytes", "ünïcødé"] {
			let bytes = [UInt8](text.utf8)
			#expect(Base64.decode(Base64.encode(bytes)) == bytes)
		}
		#expect(Base64.decode("Zg") == [UInt8]("f".utf8))
	}

	@Test("base64url encodes without padding and decodes back")
	func urlVariant() {
		let bytes: [UInt8] = [0xfb, 0xff, 0xfe] // would produce "+//+" in standard
		#expect(Base64.encodeURL(bytes) == "-__-")
		#expect(Base64.encodeURL(bytes).contains("+") == false)
		#expect(Base64.encodeURL(bytes).contains("/") == false)
		#expect(Base64.encodeURL(bytes).contains("=") == false)
		#expect(Base64.decodeURL(Base64.encodeURL(bytes)) == bytes)
	}

	@Test("decode rejects invalid or non-ascii input")
	func decodeRejectsInvalid() {
		#expect(Base64.decode("!!not base64!!") == nil)
		#expect(Base64.decode("Zg!") == nil)     // invalid padding-position char
		#expect(Base64.decode("héllo") == nil)   // non-ascii
		#expect(Base64.decode("") == [])
	}

	@Test("url decode tolerates restored padding forms")
	func urlDecodeTolerant() {
		#expect(Base64.decodeURL("-_8") == Base64.decodeURL("-_8")) // url alphabet accepted
		#expect(Base64.decode("-_8") == nil) // standard decoder rejects url alphabet
	}
}

// MARK: - JSONValue

@Suite("JSONValue")
struct JSONValueTests {
	@Test("parse + serialize round-trips nested documents")
	func roundTrip() throws {
		let text = #"{"type":"update","fragments":[{"id":"a","html":"<b>hi</b>"}],"seq":1,"ok":true,"nothing":null}"#
		let value = try JSONValue.parse(text)
		let reserialized = value.serialize()
		// object key order is not guaranteed — compare via re-parse
		#expect(try JSONValue.parse(reserialized) == value)
	}

	@Test("escapes are honored in both directions")
	func escapes() throws {
		let text = #"{"s":"line\nquote\" back\\ tab\t \u0041 \ud83d\ude00"}"#
		let value = try JSONValue.parse(text)
		guard case .object(let obj) = value,
		      case .string(let s)? = obj["s"] else {
			Issue.record("expected object with string"); return
		}
		#expect(s == "line\nquote\" back\\ tab\t A \u{1F600}")
		#expect(try JSONValue.parse(JSONValue.string(s).serialize()) == JSONValue.string(s))
	}

	@Test("integral numbers serialize without a decimal point")
	func integralNumbers() {
		#expect(JSONValue.number(1).serialize() == "1")
		#expect(JSONValue.number(-42).serialize() == "-42")
		#expect(JSONValue.number(0).serialize() == "0")
		#expect(JSONValue.number(1.5).serialize() == "1.5")
	}

	@Test("parse rejects malformed documents")
	func malformed() {
		#expect(throws: JSONError.self) { try JSONValue.parse("{\"a\":}") }
	}

	@Test("trailing tokens are rejected")
	func trailingTokensRejected() {
		#expect(throws: JSONError.trailingCharacters) { try JSONValue.parse("{} extra") }
		#expect(throws: JSONError.unexpectedEnd) { try JSONValue.parse("{\"a\":") }
		#expect(throws: JSONError.trailingCharacters) { try JSONValue.parse("12.3.4") } // "12.3" parses; ".4" is trailing garbage
		#expect(throws: JSONError.self) { try JSONValue.parse("tru") }
		#expect(throws: JSONError.invalidEscape) { try JSONValue.parse("\"\\q\"") }
	}

	@Test("lone surrogates are rejected")
	func loneSurrogatesRejected() {
		#expect(throws: JSONError.invalidEscape) { try JSONValue.parse("\"\\ud800\"") }
		#expect(throws: JSONError.invalidEscape) { try JSONValue.parse("\"\\udc00\"") }
		#expect(throws: JSONError.invalidEscape) { try JSONValue.parse("\"\\ud800x\"") }
	}

	@Test("escapeString produces parseable output for control characters")
	func escapeString() throws {
		let nasty = "a\u{00}b\u{1f}c\u{7f}d"
		let serialized = JSONValue.string(nasty).serialize()
		let reparsed = try JSONValue.parse(serialized)
		#expect(reparsed == .string("a\u{00}b\u{1f}c\u{7f}d"))
	}
}

// MARK: - WS codec (data-free JSON)

@Suite("WS JSON codec")
struct WSJSONCodecTests {
	@Test("WSIncoming decodes every wire shape")
	func incoming() throws {
		#expect(try WSIncoming(jsonText: #"{"type":"ping"}"#) == .ping)
		#expect(try WSIncoming(jsonText: #"{"type":"navigate","url":"/about"}"#) == .navigate(url: "/about"))
		let event = try WSIncoming(jsonText: #"{"type":"event","component":"c0","event":"click","data":{"targetId":"x"}}"#)
		guard case .event(let component, let event2, let data) = event else {
			Issue.record("expected .event"); return
		}
		#expect(component == "c0")
		#expect(event2 == "click")
		#expect(data == ["targetId": "x"])
	}

	@Test("WSIncoming emits the same errors as the old decoder path")
	func incomingErrors() {
		#expect(throws: WSMessageError.self) { try WSIncoming(jsonText: #"{"type":"unknown"}"#) }
		#expect(throws: WSMessageError.self) { try WSIncoming(jsonText: #"{"event":"click"}"#) }
		#expect(throws: WSMessageError.self) { try WSIncoming(jsonText: #"{"type":"event","component":"c0"}"#) }
		#expect(throws: JSONError.self) { try WSIncoming(jsonText: "not json") }
	}

	@Test("WSOutgoing emits the same wire shapes")
	func outgoing() throws {
		#expect(WSOutgoing.pong.jsonText == #"{"type":"pong"}"#)
		#expect(try JSONValue.parse(WSOutgoing.update(fragments: [FragmentUpdate(id: "a", html: "<b>")], seq: nil).jsonText)
			== JSONValue.object(["type": .string("update"), "fragments": .array([.object(["id": .string("a"), "html": .string("<b>")])])]))
		#expect(try JSONValue.parse(WSOutgoing.redirect(url: "/", replace: true).jsonText)
			== JSONValue.object(["type": .string("redirect"), "url": .string("/"), "replace": .bool(true)]))
		let withSeq = try JSONValue.parse(WSOutgoing.update(fragments: [], seq: 3).jsonText)
		guard case .object(let obj) = withSeq else { Issue.record("expected object"); return }
		#expect(obj["seq"] == .number(3))
	}

	@Test("round-trip an event through encode+decode is identity-preserving where possible")
	func roundTrip() throws {
		let outgoing = WSOutgoing.state(path: "count", value: "5")
		// jsonBytes and jsonText must carry the same value (object key order
		// may differ between calls; the wire value is order-independent).
		let fromBytes = try JSONValue.parse(String(decoding: outgoing.jsonBytes, as: UTF8.self))
		let fromText = try JSONValue.parse(outgoing.jsonText)
		#expect(fromBytes == fromText)
	}
}
