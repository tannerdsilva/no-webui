import NIOHTTP1
import WebUISharedCore

// MARK: - FormValues
//
// the decoded urlencoded/multipart field set: a repeated key keeps its first
// value for the dictionary-style getters and all of them for `all(_:)`. typed
// getters coerce the form spellings a browser actually sends.

/// the text fields of a parsed request body, keyed by field name.
public struct FormValues: Sendable {
	private let storage: [String: [String]]

	init(_ storage: [String: [String]]) {
		self.storage = storage
	}

	/// the first value for `name`, or nil.
	public subscript(_ name: String) -> String? {
		storage[name]?.first
	}

	/// the first value for `name`, or nil.
	public func string(_ name: String) -> String? {
		storage[name]?.first
	}

	/// the first value for `name` parsed as an integer, or nil.
	public func int(_ name: String) -> Int? {
		storage[name]?.first.flatMap(Int.init)
	}

	/// the first value for `name` parsed as a boolean, or nil. recognized
	/// spellings are the ones a browser sends for checkboxes and switches.
	public func bool(_ name: String) -> Bool? {
		guard let raw = storage[name]?.first else { return nil }
		switch raw.lowercased() {
		case "true", "1", "on", "yes": return true
		case "false", "0", "off", "no": return false
		default: return nil
		}
	}

	/// every value for a repeated `name`, in submission order.
	public func all(_ name: String) -> [String] {
		storage[name] ?? []
	}

	/// whether the body carried no fields at all.
	public var isEmpty: Bool {
		storage.isEmpty
	}
}

// MARK: - UploadedFile

/// one file part of a multipart body: the field it was uploaded under, the
/// client-supplied filename, the part's content type, and the exact bytes.
public struct UploadedFile: Sendable {
	public let field: String
	public let filename: String
	public let contentType: String
	public let bytes: [UInt8]

	/// the uploaded byte count — the value the size cap actually measures.
	public var size: Int { bytes.count }
}

// MARK: - MultipartForm

/// a parsed multipart/form-data body: its text fields plus its file parts.
public struct MultipartForm: Sendable {
	public let values: FormValues
	public let files: [UploadedFile]

	/// the first file uploaded under `field`, or nil.
	public func file(_ field: String) -> UploadedFile? {
		files.first { $0.field == field }
	}

	/// every file uploaded under `field`, in submission order (a
	/// `multiple` file input sends several).
	public func files(_ field: String) -> [UploadedFile] {
		files.filter { $0.field == field }
	}
}

// MARK: - BodyParseError

/// why the server refused a request body. every case carries the numbers
/// that explain it, so the caller can name the exact limit that was hit.
public enum BodyParseError: Error, Sendable, Equatable {
	/// the body exceeded ``BodyReader/maxBodyBytes`` — either a declared
	/// `Content-Length` over the cap (refused before buffering) or a body
	/// that grew past it while being read.
	case tooLarge(limit: Int, actual: Int)
	/// the multipart body exceeded ``BodyReader/maxMultipartParts`` parts.
	case tooManyParts(limit: Int, actual: Int)
	/// the declared `Content-Length` does not match the received byte count —
	/// a request-smuggling red flag, never something to parse.
	case lengthMismatch(declared: Int, actual: Int)
	/// the body is not a well-formed multipart body under the declared
	/// boundary (missing boundary, broken delimiter, truncated part). the
	/// string is for the log, never the wire.
	case malformedMultipart(String)
}

// MARK: - BodyReader

/// the bounded request-body parser. `maxBodyBytes` and `maxMultipartParts`
/// are MANDATORY: a caller that wants an unbounded upload endpoint must say
/// so explicitly and supplies its own numbers — the defaults are the caps an
/// upload endpoint without one would otherwise skip (plan w3.3, the DoS
/// rule). the socket read path validates a declared `Content-Length` against
/// the byte cap BEFORE buffering a single body byte, then accumulates up to
/// the cap and refuses the rest — the same bounded-parsing discipline the
/// nested-json cap established, applied to request bodies.
public struct BodyReader: Sendable {
	/// the hard cap on one request body, in bytes. default 1 MiB.
	public let maxBodyBytes: Int
	/// the hard cap on one multipart body's parts. default 64.
	public let maxMultipartParts: Int

	public init(maxBodyBytes: Int = 1 << 20, maxMultipartParts: Int = 64) {
		self.maxBodyBytes = maxBodyBytes
		self.maxMultipartParts = maxMultipartParts
	}

	// MARK: length discipline

	/// parse the `Content-Length` header; nil when absent or unparseable
	/// (a chunked body has no declared length).
	public static func contentLength(_ headers: HTTPHeaders) -> Int? {
		guard let raw = headers.first(name: "Content-Length") else { return nil }
		return Int(raw.trimmingCharacters(in: .whitespaces))
	}

	/// refuse a declared content length over the cap — the check the read
	/// path performs before it buffers a single body byte.
	public func validateContentLength(_ declared: Int) throws {
		guard declared <= maxBodyBytes else {
			throw BodyParseError.tooLarge(limit: maxBodyBytes, actual: declared)
		}
	}

	/// refuse a received body whose byte count contradicts the declared
	/// content length. a mismatch between the two is how a smuggling request
	/// is woven; it is refused rather than parsed.
	public func validateLength(declared: Int?, actual: Int) throws {
		guard let declared, declared != actual else { return }
		throw BodyParseError.lengthMismatch(declared: declared, actual: actual)
	}

	// MARK: decoding

	/// decode an `application/x-www-form-urlencoded` body. `+` decodes to a
	/// space and `%XX` to its byte; a malformed escape passes through rather
	/// than vanishing. urlencoded bodies have no failure mode — any byte
	/// sequence decodes.
	public func urlencoded(_ bytes: [UInt8]) -> FormValues {
		let text = String(decoding: bytes, as: UTF8.self)
		var out: [String: [String]] = [:]
		for pair in text.split(separator: "&", omittingEmptySubsequences: true) {
			let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
			let name = percentDecode(parts[0])
			guard !name.isEmpty else { continue }
			out[name, default: []].append(parts.count == 2 ? percentDecode(parts[1]) : "")
		}
		return FormValues(out)
	}

	/// parse a `multipart/form-data` body under the boundary its content type
	/// declares. supports text fields and binary file parts; part content is
	/// kept verbatim, so CRLF-bearing and non-utf8 bytes round-trip exactly.
	public func multipart(_ bytes: [UInt8], contentType: String) throws -> MultipartForm {
		guard bytes.count <= maxBodyBytes else {
			throw BodyParseError.tooLarge(limit: maxBodyBytes, actual: bytes.count)
		}
		guard let boundary = Self.boundary(from: contentType) else {
			throw BodyParseError.malformedMultipart("no boundary parameter in content type")
		}
		let marker = Array("--".utf8) + Array(boundary.utf8)
		// a body may carry a preamble before its first boundary; the first
		// `--boundary` is where the parts start.
		guard let first = Self.indexOf(marker, in: bytes, from: 0) else {
			throw BodyParseError.malformedMultipart("no boundary marker in body")
		}

		var values: [String: [String]] = [:]
		var files: [UploadedFile] = []
		var parts = 0
		var cursor = first

		while true {
			let afterMarker = cursor + marker.count
			guard afterMarker <= bytes.count else {
				throw BodyParseError.malformedMultipart("truncated boundary marker")
			}
			if bytes[afterMarker...].starts(with: [0x2D, 0x2D]) {
				break // the closing `--boundary--`; transport padding is ignored
			}
			guard bytes[afterMarker...].starts(with: [0x0D, 0x0A]) else {
				throw BodyParseError.malformedMultipart("boundary not followed by CRLF or --")
			}
			cursor = afterMarker + 2

			guard let headerEnd = Self.indexOf([0x0D, 0x0A, 0x0D, 0x0A], in: bytes, from: cursor) else {
				throw BodyParseError.malformedMultipart("part headers unterminated")
			}
			let (name, filename, partContentType) = Self.partMetadata(bytes[cursor..<headerEnd])

			let contentStart = headerEnd + 4
			let delimiter = [0x0D, 0x0A] + marker
			guard let contentEnd = Self.indexOf(delimiter, in: bytes, from: contentStart) else {
				throw BodyParseError.malformedMultipart("part content unterminated")
			}

			parts += 1
			guard parts <= maxMultipartParts else {
				throw BodyParseError.tooManyParts(limit: maxMultipartParts, actual: parts)
			}
			let content = [UInt8](bytes[contentStart..<contentEnd])
			if let filename, !filename.isEmpty {
				files.append(UploadedFile(
					field: name, filename: filename, contentType: partContentType, bytes: content
				))
			} else {
				values[name, default: []].append(String(decoding: content, as: UTF8.self))
			}
			// resume AT the next marker (the one that followed this part's
			// CRLF) so the next iteration's `afterMarker` lands past it.
			cursor = contentEnd + 2
		}

		return MultipartForm(values: FormValues(values), files: files)
	}

	/// extract the boundary parameter of a multipart content type, unquoting
	/// it when the value was quoted. nil when absent or empty.
	static func boundary(from contentType: String) -> String? {
		for piece in contentType.split(separator: ";") {
			let trimmed = piece.trimmingCharacters(in: .whitespaces)
			guard trimmed.lowercased().hasPrefix("boundary=") else { continue }
			var value = String(trimmed.dropFirst("boundary=".count)).trimmingCharacters(in: .whitespaces)
			if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
				value = String(value.dropFirst().dropLast())
			}
			return value.isEmpty ? nil : value
		}
		return nil
	}

	/// the field name, filename, and content type of one part's header block.
	private static func partMetadata(
		_ block: ArraySlice<UInt8>
	) -> (name: String, filename: String?, contentType: String) {
		var name = ""
		var filename: String?
		var contentType = "application/octet-stream"
		for rawLine in block.split(separator: 0x0A) {
			var line = Array(rawLine)
			if line.last == 0x0D { line.removeLast() }
			guard let colon = line.firstIndex(of: 0x3A) else { continue }
			let headerName = String(decoding: line[..<colon], as: UTF8.self)
				.lowercased()
				.trimmingCharacters(in: .whitespaces)
			let value = String(decoding: line[(colon + 1)...], as: UTF8.self)
				.trimmingCharacters(in: .whitespaces)
			switch headerName {
			case "content-disposition":
				if let parameter = Self.dispositionParameter(value, "name") { name = parameter }
				filename = Self.dispositionParameter(value, "filename")
			case "content-type":
				if !value.isEmpty { contentType = value }
			default:
				break
			}
		}
		return (name, filename, contentType)
	}

	/// one `key=value` parameter of a disposition header, quoted or bare.
	private static func dispositionParameter(_ text: String, _ key: String) -> String? {
		let prefix = key + "="
		for piece in text.split(separator: ";") {
			var trimmed = piece.trimmingCharacters(in: .whitespaces)
			guard trimmed.lowercased().hasPrefix(prefix) else { continue }
			trimmed = String(trimmed.dropFirst(prefix.count))
			if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
				return String(trimmed.dropFirst().dropLast())
			}
			return trimmed
		}
		return nil
	}

	/// the first index of `needle` in `haystack` at or after `from`.
	private static func indexOf(
		_ needle: [UInt8],
		in haystack: [UInt8],
		from start: Int
	) -> Int? {
		guard !needle.isEmpty, start <= haystack.count else { return nil }
		let limit = haystack.count - needle.count
		guard start <= limit else { return nil }
		for i in start...limit {
			if haystack[i ..< (i + needle.count)].elementsEqual(needle) {
				return i
			}
		}
		return nil
	}
}
