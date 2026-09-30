import Foundation
import WebUICore

// MARK: - the emitter

// `emit` turns a payload into generated Swift: one `WebUIShippedAsset` conformance that the
// consumer's server feeds to `WebUIAsset(_:path:)`. the payload rides as base64 because
// generated source must not be able to change bytes: a `[UInt8]` literal is slow for the
// type checker at asset sizes, and an escaped string literal can be broken by sequences a
// payload legitimately contains (a `"""` in javascript, a stray backslash in a font).

/// the receipt for one emitted asset — what shipped, and how big.
public struct Emitted: Sendable {
	/// the emitted type's name.
	public let typeName: String
	/// the payload size in bytes.
	public let bytes: Int
	/// the compressed variant's size; `nil` when the build host had no `gzip`.
	public let gzipBytes: Int?
	/// the address the url carries: the first 12 hex of the sha256 of the payload. for a
	/// directory bag this is a build record — the digest of the sorted name+bytes stream —
	/// not a url address: a bag is not one servable asset.
	public let stamp: String
}

/// a build-side refusal. generation either produces code that compiles and ships, or names
/// what stopped it.
public enum WebUIBuildError: Error, CustomStringConvertible {
	/// the type name would not be a legal swift identifier in generated code.
	case invalidTypeName(String)
	/// the payload would ship comments to clients (see ``ProsePolicy``).
	case proseWouldShip(typeName: String, findings: [ProseFinding])
	/// the manifest is malformed — the message names the entry and the offending key.
	case malformedManifest(String)
	/// a manifest entry names a file that does not exist.
	case missingAsset(entry: String, path: String)
	/// a manifest entry is larger than the ceiling the manifest pins for it.
	case overCeiling(entry: String, measured: Int, ceiling: Int, isGzip: Bool)

	public var description: String {
		switch self {
		case .invalidTypeName(let name):
			return "'\(name)' is not a swift identifier — the generated code declares `enum \(name): WebUIShippedAsset`"
		case .proseWouldShip(let typeName, let findings):
			var lines = ["\(typeName) would ship \(findings.count) comment(s) to clients:"]
			for finding in findings.prefix(12) {
				lines.append("  line \(finding.line): \(finding.text)")
			}
			lines.append("  the shipped bytes are the client's — keep the note in Documentation/*.md,")
			lines.append("  or set `minify` for a sheet whose comments the minifier strips.")
			return lines.joined(separator: "\n")
		case .malformedManifest(let message):
			return "webui-assets.json: \(message)"
		case .missingAsset(let entry, let path):
			return "webui-assets.json: entry '\(entry)' names no file at \(path)"
		case .overCeiling(let entry, let measured, let ceiling, let isGzip):
			let unit = isGzip ? "gzip bytes" : "bytes"
			return "webui-assets.json: entry '\(entry)' is \(measured) \(unit), over its pinned ceiling of \(ceiling) — re-pin deliberately after measuring, or shrink the payload"
		}
	}
}

/// what the emitter does about comments in a payload.
public enum ProsePolicy: Sendable {
	/// ship what was given, comments included — the caller's decision, stated.
	case off
	/// refuse a payload whose comments would reach a client. the guard runs on the payload
	/// as it will ship, so a comment ``WebUIAssetBuilder/Options/minify`` strips is not a
	/// finding.
	case check
}

/// one comment a payload would have shipped. the guard's own finding type is package-level,
/// so this is its public re-exposure — the shape a consumer's tool can read.
public struct ProseFinding: Sendable {
	/// 1-based line number of the comment's opening delimiter.
	public let line: Int
	/// the comment's opening line, trimmed — enough to recognize the prose.
	public let text: String
}

/// the emitter a host's build tool calls: one payload in, one generated type out.
public enum WebUIAssetBuilder {

	/// what an emission does with the payload on the way in.
	public struct Options: Sendable {
		/// run the css minifier over the payload before emitting — the same minifier the
		/// framework's own sheet goes through, so a working sheet's designer notes never
		/// reach a client.
		public var minify: Bool
		/// refuse (or not) a payload whose comments would ship.
		public var prose: ProsePolicy
		/// the `Content-Type` the served asset carries; it also decides which comment
		/// grammar the prose guard reads.
		public var contentType: String

		public init(minify: Bool = false, prose: ProsePolicy = .off, contentType: String) {
			self.minify = minify
			self.prose = prose
			self.contentType = contentType
		}
	}

	/// emit `text` as a `WebUIShippedAsset` conformance named `typeName` into `url`,
	/// returning the build's receipt.
	@discardableResult
	public static func emit(
		shipped text: String,
		typeName: String,
		options: Options,
		to url: URL
	) throws -> Emitted {
		// minify first, then judge: the guard's question is "would a client receive prose",
		// and a comment the minifier strips never reaches one.
		let payload = options.minify ? minifyCSS(text) : text
		try check(
			payload: payload,
			typeName: typeName,
			language: proseLanguage(for: options.contentType),
			policy: options.prose
		)
		return try emit(bytes: Array(payload.utf8), typeName: typeName, options: options, to: url)
	}

	/// the byte-level core: every other front door funnels here so there is one place that
	/// computes the stamp, produces the variant and writes the source.
	@discardableResult
	static func emit(
		bytes: [UInt8],
		typeName: String,
		options: Options,
		to url: URL
	) throws -> Emitted {
		try validate(typeName: typeName)
		let stamp = String(sha256Hex(bytes).prefix(12))
		let variant = gzip(Data(bytes))
		let source = sourceText(
			typeName: typeName,
			contentType: options.contentType,
			stamp: stamp,
			body: bytes,
			variant: variant
		)
		try source.write(to: url, atomically: true, encoding: .utf8)
		return Emitted(
			typeName: typeName,
			bytes: bytes.count,
			gzipBytes: variant?.count,
			stamp: stamp
		)
	}

	// MARK: internals

	/// the prose gate, over the payload as it will ship.
	static func check(payload: String, typeName: String, language: ProseGuard.Language?, policy: ProsePolicy) throws {
		guard policy == .check, let language else { return }
		let findings = ProseGuard.findings(in: payload, language: language)
		guard findings.isEmpty else {
			throw WebUIBuildError.proseWouldShip(
				typeName: typeName,
				findings: findings.map { ProseFinding(line: $0.line, text: $0.text) }
			)
		}
	}

	/// which comment grammar a content type speaks, or `nil` where comments do not apply (a
	/// font, an image): the guard is a comment grammar, and nothing else has one.
	static func proseLanguage(for contentType: String) -> ProseGuard.Language? {
		let lowered = contentType.lowercased()
		if lowered.contains("javascript") || lowered.contains("ecmascript") { return .javaScript }
		if lowered.contains("css") { return .css }
		return nil
	}

	/// a generated declaration is `enum <name>: …` — a name that is not an identifier would
	/// surface as a swift compile error in the consumer's own build, far from this tool.
	static func validate(typeName: String) throws {
		guard isValidIdentifier(typeName) else {
			throw WebUIBuildError.invalidTypeName(typeName)
		}
	}

	static func isValidIdentifier(_ name: String) -> Bool {
		guard let first = name.first, first.isLetter || first == "_" else { return false }
		return name.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
	}

	/// an escaped swift string literal — the only interpolation that could otherwise break
	/// generated code (type names are validated, stamps are hex, payloads are base64).
	static func literal(_ text: String) -> String {
		let escaped = text
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
		return "\"\(escaped)\""
	}

	/// one emitted file: a header, the import, the blocks, and the shared gzip decoder.
	static func assemble(header: [String], blocks: [[String]]) -> String {
		var lines = header
		lines.append("")
		lines.append("import WebUICore")
		for block in blocks {
			lines.append("")
			lines.append(contentsOf: block)
		}
		lines.append("")
		lines.append(contentsOf: gzipDecoderBlock)
		return lines.joined(separator: "\n") + "\n"
	}

	static func sourceText(
		typeName: String,
		contentType: String,
		stamp: String,
		body: [UInt8],
		variant: Data?
	) -> String {
		let header = [
			"// generated by WebUIBuild — do not edit.",
			"//",
			"// the payload, its content-addressed url and its pre-compressed variant. hand the",
			"// server `WebUIAsset(\(typeName).self, path: \"/ui/…\")`: the url a document links and",
			"// the registration the server answers with derive from that one value.",
		]
		return assemble(
			header: header,
			blocks: [
				shippedTypeBlock(
					typeName: typeName, contentType: contentType, stamp: stamp,
					body: body, variant: variant, includeText: true
				)
			]
		)
	}

	/// one `WebUIShippedAsset` conformance, as source lines.
	static func shippedTypeBlock(
		typeName: String,
		contentType: String,
		stamp: String,
		body: [UInt8],
		variant: Data?,
		includeText: Bool
	) -> [String] {
		var lines: [String] = []
		lines.append("public enum \(typeName): WebUIShippedAsset {")
		lines.append("\tpublic static let contentType = \(literal(contentType))")
		lines.append("\t/// the first 12 hex of the sha256 of `body` — the address the url carries.")
		lines.append("\tpublic static let stamp = \(literal(stamp))")
		lines.append("\t/// the payload, base64: a byte literal is slow to type-check, and an escaped string")
		lines.append("\t/// literal can be broken by sequences a payload legitimately contains.")
		lines.append("\tprivate static let bodyBase64 = \(literal(Data(body).base64EncodedString()))")
		lines.append("\tpublic static let body: [UInt8] = Base64.decode(bodyBase64) ?? []")
		lines.append("\t/// the pre-compressed variant; absent when the build host had no `gzip`.")
		lines.append("\tprivate static let gzipBase64 = \(literal(variant?.base64EncodedString() ?? ""))")
		lines.append("\tpublic static let gzip: [UInt8]? = decodeShippedGzip(gzipBase64)")
		if includeText {
			lines.append("\t/// the payload as text, for a host that wants it inline.")
			lines.append("\tpublic static var text: String { String(decoding: body, as: UTF8.self) }")
		}
		lines.append("}")
		return lines
	}

	/// one directory bag, files keyed by name and sorted so two builds agree byte for byte.
	/// deliberately NOT a `WebUIShippedAsset`: a bag is not one servable asset, so it has no
	/// single address, and pretending otherwise would make the stamp a lie.
	static func directoryBlock(
		typeName: String,
		contentType: String,
		files: [(name: String, bytes: [UInt8])]
	) -> [String] {
		var lines: [String] = []
		lines.append("/// a directory of files, keyed by name — decode each with `Base64.decode` and")
		lines.append("/// register it at its own path.")
		lines.append("public enum \(typeName) {")
		lines.append("\tpublic static let contentType = \(literal(contentType))")
		lines.append("\t/// one base64 payload per file, named as on disk.")
		lines.append("\tpublic static let filesBase64: [String: String] = [")
		for file in files.sorted(by: { $0.name < $1.name }) {
			lines.append("\t\t\(literal(file.name)): \(literal(Data(file.bytes).base64EncodedString())),")
		}
		lines.append("\t]")
		lines.append("}")
		return lines
	}

	static let gzipDecoderBlock: [String] = [
		"/// decode a base64 gzip variant; `nil` when empty (no build-host `gzip`, no variant).",
		"private func decodeShippedGzip(_ text: String) -> [UInt8]? {",
		"\tguard !text.isEmpty, let bytes = Base64.decode(text), !bytes.isEmpty else { return nil }",
		"\treturn bytes",
		"}",
	]
}