// MARK: - Epoch
//
// the package-wide date convention: whole seconds since the unix epoch, as an
// unsigned 64-bit integer (big-endian in storage). `HTTPCookie` carries
// `Expires` as `Epoch` so the cookie path stays foundation-free — a cookie in
// the shared leaf cannot depend on `Date` or `DateFormatter`.
public typealias Epoch = UInt64

// MARK: - HTTPCookie

/// a minimal, pure-swift cookie model: request-side parsing of a `Cookie`
/// header, response-side building of a `Set-Cookie` header with the full flag
/// surface, and `__Host-` prefix enforcement.
///
/// foundation-free by construction — this is the shared leaf, so dates are
/// `Epoch` seconds and the rfc 1123 formatter is a civil-days algorithm
/// instead of `DateFormatter` (see `HTTPDate` below).
public struct HTTPCookie: Sendable, Equatable {

	public enum SameSite: String, Sendable, Equatable {
		case lax = "Lax"
		case strict = "Strict"
		case none = "None"
	}

	public struct Attributes: Sendable, Equatable {
		/// the expiry as unix-epoch seconds (`Epoch`), never a `Date`: this
		/// is the leaf's only legal date shape.
		public var expires: Epoch?
		public var maxAge: Int?
		public var domain: String?
		public var path: String?
		public var secure: Bool
		public var httpOnly: Bool
		public var sameSite: SameSite?

		public init(
			expires: Epoch? = nil,
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

	/// `__Host-`-prefix rules (rfc 6265bis): the cookie must be `Secure`, must
	/// not carry a `Domain`, and must use `Path=/`. anything else is rejected.
	public static func validate(_ name: String, _ attributes: Attributes) throws {
		guard !name.isEmpty else { throw BuildError.invalidName }
		let forbidden: [Unicode.Scalar] = [" ", "\t", ";", ",", "\""]
		guard !name.unicodeScalars.contains(where: { forbidden.contains($0) }) else {
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
		let escapedValue = Self.escapeValue(value)
		var parts = ["\(name)=\(escapedValue)"]
		if let maxAge = attributes.maxAge {
			parts.append("Max-Age=\(maxAge)")
		}
		if let expires = attributes.expires {
			parts.append("Expires=\(HTTPDate.format(expires))")
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

	/// backslash is escaped, `;` is percent-encoded — a value can never
	/// terminate the pair early (`%3B` decodes to `;` on the receiving side).
	private static func escapeValue(_ value: String) -> String {
		guard value.unicodeScalars.contains(where: { $0 == "\\" || $0 == ";" }) else {
			return value
		}
		var out = ""
		for scalar in value.unicodeScalars {
			switch scalar {
			case "\\": out += "\\\\"
			case ";": out += "%3B"
			default: out.unicodeScalars.append(scalar)
			}
		}
		return out
	}
}

// MARK: - HTTPDate
//
// the rfc 1123 http-date ("Wed, 09 Jun 2021 10:18:14 GMT") in both
// directions, without `DateFormatter`/`Calendar`. the civil-date math is
// howard hinnant's days-from-civil / civil-from-days pair — branch-light,
// overflow-exact for the ranges a 64-bit second count can express, and
// small enough that an embedded (wasm) consumer links it for free.

/// a struct with only statics so the two cookie surfaces share one date
/// implementation. `format` renders epoch seconds; `parse` reads an
/// rfc 1123 date back, returning nil for anything unparseable — a garbage
/// `Expires` value is dropped, never a crash.
fileprivate enum HTTPDate {
	static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

	static func format(_ epoch: Epoch) -> String {
		let seconds = Int64(epoch)
		let days = seconds / 86400
		let timeOfDay = seconds % 86400
		let civil = civilFromDays(days)
		// 1970-01-01 was a thursday; the weekday of a day count is that plus
		// the day, mod 7 (0 = sunday).
		let weekday = Int((days % 7 + 4) % 7)
		let hour = Int(timeOfDay / 3600)
		let minute = Int((timeOfDay % 3600) / 60)
		let second = Int(timeOfDay % 60)
		return "\(weekdayNames[weekday]), \(two(civil.day)) \(monthNames[civil.month - 1]) "
			+ "\(four(civil.year)) \(two(hour)):\(two(minute)):\(two(second)) GMT"
	}

	static func parse(_ text: String) -> Epoch? {
		var tokens: [String] = []
		var current = ""
		for scalar in text.unicodeScalars {
			switch scalar {
			case ",", " ", "\t":
				if !current.isEmpty {
					tokens.append(current)
					current = ""
				}
			default:
				current.unicodeScalars.append(scalar)
			}
		}
		if !current.isEmpty { tokens.append(current) }
		// "Wed" "09" "Jun" "2021" "10:18:14" "GMT" (rfc 1123); the rfc 850
		// weekday-less form ("09 Jun 2021 ...") is tolerated as well.
		let offset = tokens.count == 6 ? 1 : 0
		guard offset + 4 < tokens.count,
			let day = Int(tokens[offset]),
			let month = monthNumber(tokens[offset + 1]),
			let year = Int(tokens[offset + 2]) else { return nil }
		let time = tokens[offset + 3].split(separator: ":")
		guard time.count == 3,
			let hour = Int(time[0]),
			let minute = Int(time[1]),
			let second = Int(time[2]) else { return nil }
		// sanity bounds keep an adversarial header from wrapping the math;
		// `second <= 60` admits a leap second as the top of the range.
		guard day >= 1, day <= 31,
			month >= 1, month <= 12,
			year >= 1970, year <= 9999,
			hour <= 23, minute <= 59, second <= 60 else { return nil }
		let days = daysFromCivil(year, month, day)
		let seconds = days * 86400 + Int64(hour) * 3600 + Int64(minute) * 60 + Int64(second)
		guard seconds >= 0 else { return nil }
		return UInt64(seconds)
	}

	private static func monthNumber(_ text: String) -> Int? {
		let normalized = text.prefix(1).uppercased() + text.dropFirst().lowercased()
		switch normalized {
		case "Jan": return 1
		case "Feb": return 2
		case "Mar": return 3
		case "Apr": return 4
		case "May": return 5
		case "Jun": return 6
		case "Jul": return 7
		case "Aug": return 8
		case "Sep": return 9
		case "Oct": return 10
		case "Nov": return 11
		case "Dec": return 12
		default: return nil
		}
	}

	private static func two(_ value: Int) -> String {
		value < 10 ? "0\(value)" : "\(value)"
	}

	private static func four(_ value: Int) -> String {
		var out = "\(value)"
		while out.count < 4 { out = "0" + out }
		return out
	}

	/// days since 1970-01-01 → civil (year, month, day).
	private static func civilFromDays(_ days: Int64) -> (year: Int, month: Int, day: Int) {
		let z = days + 719468
		let era = (z >= 0 ? z : z - 146096) / 146097
		let doe = z - era * 146097                                // day of era
		let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
		let y = yoe + era * 400
		let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)         // day of year
		let mp = (5 * doy + 2) / 153
		let d = doy - (153 * mp + 2) / 5 + 1
		let m = mp < 10 ? mp + 3 : mp - 9
		return (Int(y) + (m <= 2 ? 1 : 0), Int(m), Int(d))
	}

	/// civil (year, month, day) → days since 1970-01-01.
	private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int64 {
		let y = month <= 2 ? year - 1 : year
		let era = (y >= 0 ? y : y - 399) / 400
		let yoe = y - era * 400
		let mp = month > 2 ? month - 3 : month + 9
		let doy = (153 * mp + 2) / 5 + day - 1
		let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
		return Int64(era) * 146097 + Int64(doe) - 719468
	}
}

// MARK: - CookieParser

/// request-side parsing of a `Cookie` header, and response-side parsing of a
/// `Set-Cookie` header back into a ``HTTPCookie``. `$`-prefixed attributes
/// (e.g. `$Path`, `$Domain`) are ignored on the request side; values are
/// trimmed and unquoted. splitting is quote-aware so a quoted value
/// containing a semicolon is not split at the semicolon.
public enum CookieParser {
	/// parse a `Cookie` request header into name → value pairs.
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
			let rawName = trim(segment[..<at])
			guard !rawName.isEmpty, !rawName.hasPrefix("$") else { continue }
			var rawValue = String(trim(segment[segment.index(after: at)...]))
			if rawValue.count >= 2, rawValue.first == "\"", rawValue.last == "\"" {
				rawValue = String(rawValue.dropFirst().dropLast())
			}
			result[String(rawName)] = rawValue
		}
		return result
	}

	/// parse one `Set-Cookie` header value back into a ``HTTPCookie``. `nil`
	/// only when the first segment carries no `name=value` pair; attribute
	/// values that do not parse — an invalid `Expires` among them — are
	/// dropped individually, never a crash: a garbage expiry leaves
	/// `attributes.expires` nil.
	public static func setCookie(_ headerValue: String) -> HTTPCookie? {
		let segments = headerValue.split(separator: ";", omittingEmptySubsequences: false)
		guard let first = segments.first else { return nil }
		let firstParts = first.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
		guard firstParts.count == 2 else { return nil }
		let name = String(trim(firstParts[0]))
		guard !name.isEmpty else { return nil }
		let value = unquote(String(trim(firstParts[1])))

		var attributes = HTTPCookie.Attributes()
		for segment in segments.dropFirst() {
			let parts = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
			let key = String(trim(parts[0])).lowercased()
			guard !key.isEmpty else { continue }
			let raw = parts.count == 2 ? unquote(String(trim(parts[1]))) : ""
			switch key {
			case "expires":
				attributes.expires = HTTPDate.parse(raw)
			case "max-age":
				attributes.maxAge = Int(raw)
			case "domain":
				attributes.domain = raw
			case "path":
				attributes.path = raw
			case "secure":
				attributes.secure = true
			case "httponly":
				attributes.httpOnly = true
			case "samesite":
				attributes.sameSite = parseSameSite(raw)
			default:
				break
			}
		}
		return HTTPCookie(name: name, value: value, attributes: attributes)
	}

	private static func parseSameSite(_ text: String) -> HTTPCookie.SameSite? {
		guard !text.isEmpty else { return nil }
		let normalized = String(text.prefix(1).uppercased()) + text.dropFirst().lowercased()
		return HTTPCookie.SameSite(rawValue: normalized)
	}

	/// strip surrounding double quotes.
	private static func unquote(_ value: String) -> String {
		guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
		return String(value.dropFirst().dropLast())
	}

	/// strip leading/trailing spaces and tabs — the leaf has no
	/// `CharacterSet.whitespaces`.
	private static func trim(_ text: Substring) -> Substring {
		var start = text.startIndex
		var end = text.endIndex
		while start < end {
			let c = text[start]
			if c == " " || c == "\t" { start = text.index(after: start) } else { break }
		}
		while end > start {
			let i = text.index(before: end)
			let c = text[i]
			if c == " " || c == "\t" { end = i } else { break }
		}
		return text[start..<end]
	}
}
