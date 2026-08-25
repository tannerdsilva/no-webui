import Foundation

// MARK: - RuntimeConfig

public struct RuntimeConfig: Sendable, Encodable {
	public var wsUrl: String?
	public var wsReconnect: Bool?
	public var wsMaxReconnectDelayMs: Int?
	public var wsPingIntervalMs: Int?
	public var wsPongTimeoutMs: Int?
	public var maxQueueSize: Int?
	public var debounceInputMs: Int?
	public var debounceMaxWaitMs: Int?
	public var optimisticSettleMs: Int?
	public var logLevel: String?

	public init(
		wsUrl: String? = nil,
		wsReconnect: Bool? = nil,
		wsMaxReconnectDelayMs: Int? = nil,
		wsPingIntervalMs: Int? = nil,
		wsPongTimeoutMs: Int? = nil,
		maxQueueSize: Int? = nil,
		debounceInputMs: Int? = nil,
		debounceMaxWaitMs: Int? = nil,
		optimisticSettleMs: Int? = nil,
		logLevel: String? = nil
	) {
		self.wsUrl = wsUrl
		self.wsReconnect = wsReconnect
		self.wsMaxReconnectDelayMs = wsMaxReconnectDelayMs
		self.wsPingIntervalMs = wsPingIntervalMs
		self.wsPongTimeoutMs = wsPongTimeoutMs
		self.maxQueueSize = maxQueueSize
		self.debounceInputMs = debounceInputMs
		self.debounceMaxWaitMs = debounceMaxWaitMs
		self.optimisticSettleMs = optimisticSettleMs
		self.logLevel = logLevel
	}

	public var isEmpty: Bool {
		wsUrl == nil && wsReconnect == nil && wsMaxReconnectDelayMs == nil
			&& wsPingIntervalMs == nil && wsPongTimeoutMs == nil && maxQueueSize == nil
			&& debounceInputMs == nil && debounceMaxWaitMs == nil
			&& optimisticSettleMs == nil && logLevel == nil
	}

	public func encodedJSON() -> String {
		var entries: [String] = []
		if let v = wsUrl { entries.append("\"wsUrl\":\(jsonStringLiteral(v))") }
		if let v = wsReconnect { entries.append("\"wsReconnect\":\(v)") }
		if let v = wsMaxReconnectDelayMs { entries.append("\"wsMaxReconnectDelay\":\(v)") }
		if let v = wsPingIntervalMs { entries.append("\"wsPingInterval\":\(v)") }
		if let v = wsPongTimeoutMs { entries.append("\"wsPongTimeout\":\(v)") }
		if let v = maxQueueSize { entries.append("\"maxQueueSize\":\(v)") }
		if let v = debounceInputMs { entries.append("\"debounceInputMs\":\(v)") }
		if let v = debounceMaxWaitMs { entries.append("\"debounceMaxWaitMs\":\(v)") }
		if let v = optimisticSettleMs { entries.append("\"optimisticSettleMs\":\(v)") }
		if let v = logLevel { entries.append("\"logLevel\":\(jsonStringLiteral(v))") }
		return "{\(entries.joined(separator: ","))}"
	}

	private func jsonStringLiteral(_ string: String) -> String {
		var result = "\""
		for scalar in string.unicodeScalars {
			switch scalar {
			case "\\": result += "\\\\"
			case "\"": result += "\\\""
			case "\n": result += "\\n"
			case "\r": result += "\\r"
			case "\t": result += "\\t"
			case "\0": result += "\\u0000"
			default:
				if scalar.value < 0x20 {
					result += String(format: "\\u%04x", scalar.value)
				} else {
					result.unicodeScalars.append(scalar)
				}
			}
		}
		result += "\""
		return result
	}
}
