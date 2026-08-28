import Foundation

// MARK: - HTTPCookie

/// a minimal, pure-Swift cookie model: request-side parsing of a `Cookie`
/// header, response-side building of a `Set-Cookie` header with the full flag
/// surface, and `__Host-` prefix enforcement.
public struct HTTPCookie: Sendable, Equatable {

	public enum SameSite: String, Sendable, Equatable {
		case lax = "Lax"
		case strict = "Strict"
		case none = "None"
	}

	public struct Attributes: Sendable, Equatable {
		public var expires: Date?
		public var maxAge: Int?
		public var domain: String?
		public var path: String?
		public var secure: Bool
		public var httpOnly: Bool
		public var sameSite: SameSite?

		public init(
			expires: Date? = nil,
			maxAge: Int? = nil,
			domain: String? = nil,
			path: String? = nil,
			secure: Bool = false,
			httpOnly: Bool = false,
			sameSite: SameSite? = nil
		) {
			self.expires = expires
			self.maxAge = maxAge
			self.domain = domain
			self.path = path
			self.secure = secure
			self.httpOnly = httpOnly
			self.sameSite = sameSite
		}
	}

	public enum BuildError: Error, Equatable, Sendable {
		case invalidName
		case invalidValue
		case hostPrefixWithoutSecure
		case hostPrefixWithDomain
		case hostPrefixWithNonRootPath
	}

	public var name: String
	public var value: String
	public var attributes: Attributes

	public init(name: String, value: String, attributes: Attributes = Attributes()) {
		self.name = name
		self.value = value
		self.attributes = attributes
	}

	/// `__Host-`-prefix rules (RFC 6265bis): the cookie must be `Secure`, must
	/// not carry a `Domain`, and must use `Path=/`. anything else is rejected.
	public static func validate(_ name: String, _ attributes: Attributes) throws {
		guard !name.isEmpty else { throw BuildError.invalidName }
		let forbidden = CharacterSet(charactersIn: " \t;,\"")
		guard name.rangeOfCharacter(from: forbidden) == nil else {
			throw BuildError.invalidName
		}
		if name.hasPrefix("__Host-") {
			guard attributes.secure else { throw BuildError.hostPrefixWithoutSecure }
			guard attributes.domain == nil else { throw BuildError.hostPrefixWithDomain }
			guard attributes.path == "/" else { throw BuildError.hostPrefixWithNonRootPath }
		}
	}

	/// the value of a `Set-Cookie` header for this cookie, validating all
	/// attribute rules first.
	public func setCookieHeaderValue() throws -> String {
		try Self.validate(name, attributes)
		let escapedValue = value.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: ";", with: "%3B")
		var parts = ["\(name)=\(escapedValue)"]
		if let maxAge = attributes.maxAge {
			parts.append("Max-Age=\(maxAge)")
		}
		if let expires = attributes.expires {
			parts.append("Expires=\(Self.httpDate(expires))")
		}
		if let domain = attributes.domain {
			parts.append("Domain=\(domain)")
		}
		if let path = attributes.path {
			parts.append("Path=\(path)")
		}
		if attributes.secure {
			parts.append("Secure")
		}
		if attributes.httpOnly {
			parts.append("HttpOnly")
		}
		if let sameSite = attributes.sameSite {
			parts.append("SameSite=\(sameSite.rawValue)")
		}
		return parts.joined(separator: "; ")
	}

	// RFC 1123 HTTP date, e.g. "Wed, 09 Jun 2021 10:18:14 GMT".
	private static func httpDate(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "GMT")
		formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
		return formatter.string(from: date)
	}
}

// MARK: - CookieParser

/// request-side parsing of a `Cookie` header. `$`-prefixed attributes (e.g.
/// `$Path`, `$Domain`) are ignored; values are trimmed and unquoted.
/// splitting is quote-aware so a quoted value containing a semicolon is not
/// split at the semicolon.
public enum CookieParser {
	public static func requestCookies(_ headerValue: String) -> [String: String] {
		var segments: [String] = []
		var inQuote = false
		var current = ""
		for ch in headerValue {
			if ch == "\"" {
				inQuote.toggle()
				current.append(ch)
			} else if ch == ";" && !inQuote {
				segments.append(current)
				current = ""
			} else {
				current.append(ch)
			}
		}
		segments.append(current)

		var result: [String: String] = [:]
		for segment in segments {
			var inQuote = false
			var splitAt: String.Index?
			var index = segment.startIndex
			while index < segment.endIndex {
				let ch = segment[index]
				if ch == "\"" {
					inQuote.toggle()
				} else if ch == "=" && !inQuote {
					splitAt = index
					break
				}
				index = segment.index(after: index)
			}
			guard let at = splitAt else { continue }
			let rawName = segment[..<at].trimmingCharacters(in: .whitespaces)
			guard !rawName.isEmpty, !rawName.hasPrefix("$") else { continue }
			var rawValue = segment[segment.index(after: at)...].trimmingCharacters(in: .whitespaces)
			if rawValue.count >= 2, rawValue.first == "\"", rawValue.last == "\"" {
				rawValue = String(rawValue.dropFirst().dropLast())
			}
			result[String(rawName)] = rawValue
		}
		return result
	}
}
