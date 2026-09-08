import Foundation

// MARK: - WebSocket Protocol Types
public struct FragmentUpdate: Sendable, Codable, Equatable, Hashable {
    public let id: String
    public let html: String
    public init(id: String, html: String) {
        self.id = id
        self.html = html
    }
}

// MARK: - Incoming Messages (Client → Server)
public enum WSIncoming: Sendable, Equatable {
    case event(component: String, event: String, data: [String: String], token: String?)
    case ping(token: String?)
    case navigate(url: String)
}

extension WSIncoming: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, component, event, data, url, token
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "event":
            let component = try container.decode(String.self, forKey: .component)
            let event = try container.decode(String.self, forKey: .event)
            let data = try container.decodeIfPresent([String: String].self, forKey: .data) ?? [:]
            let token = try container.decodeIfPresent(String.self, forKey: .token)
            self = .event(component: component, event: event, data: data, token: token)
        case "ping":
            let token = try container.decodeIfPresent(String.self, forKey: .token)
            self = .ping(token: token)
        case "navigate":
            let url = try container.decode(String.self, forKey: .url)
            self = .navigate(url: url)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown WSIncoming type: \(type)"
            )
        }
    }
}

// MARK: - Outgoing Messages (Server → Client)
public enum WSOutgoing: Sendable {
    case update(fragments: [FragmentUpdate], seq: Int? = nil)
    case redirect(url: String, replace: Bool)
    case state(path: String, value: String)
    case reload
    case error(code: String, message: String)
    case pong
}

extension WSOutgoing: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type, fragments, seq, url, replace, path, value, code, message
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .update(let fragments, let seq):
            try container.encode("update", forKey: .type)
            try container.encode(fragments, forKey: .fragments)
            try container.encodeIfPresent(seq, forKey: .seq)
        case .redirect(let url, let replace):
            try container.encode("redirect", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(replace, forKey: .replace)
        case .state(let path, let value):
            try container.encode("state", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(value, forKey: .value)
        case .reload:
            try container.encode("reload", forKey: .type)
        case .error(let code, let message):
            try container.encode("error", forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
        case .pong:
            try container.encode("pong", forKey: .type)
        }
    }
}

// MARK: - Data-free JSON codec

/// structural errors from the hand-rolled `WSIncoming`/`WSOutgoing` json codec
/// (the `[UInt8]`-based replacement for `Data`-backed JSONDecoder/JSONEncoder).
public enum WSMessageError: Error, Equatable, Sendable {
    case malformed(String)
}

extension WSIncoming {
    /// decode from utf-8 bytes without creating `Data`.
    public init(jsonBytes: [UInt8]) throws {
        try self.init(jsonText: String(decoding: jsonBytes, as: UTF8.self))
    }

    /// decode a `{"type": ...}` message.
    public init(jsonText: String) throws {
        guard case .object(let object) = try JSONValue.parse(jsonText) else {
            throw WSMessageError.malformed("expected a json object")
        }
        guard case .string(let type) = object["type"] else {
            throw WSMessageError.malformed("missing 'type' string")
        }
        switch type {
        case "event":
            guard case .string(let component) = object["component"],
                  case .string(let event) = object["event"] else {
                throw WSMessageError.malformed("event requires 'component' and 'event' strings")
            }
            var data: [String: String] = [:]
            if let rawData = object["data"] {
                guard case .object(let dataObject) = rawData else {
                    throw WSMessageError.malformed("event 'data' must be an object")
                }
                for (key, value) in dataObject {
                    guard case .string(let stringValue) = value else {
                        throw WSMessageError.malformed("event data values must be strings")
                    }
                    data[key] = stringValue
                }
            }
            let token: String?
            if let rawToken = object["token"] {
                guard case .string(let tokenValue) = rawToken else {
                    throw WSMessageError.malformed("event 'token' must be a string")
                }
                token = tokenValue
            } else {
                token = nil
            }
            self = .event(component: component, event: event, data: data, token: token)
        case "ping":
            let token: String?
            if let rawToken = object["token"] {
                guard case .string(let tokenValue) = rawToken else {
                    throw WSMessageError.malformed("ping 'token' must be a string")
                }
                token = tokenValue
            } else {
                token = nil
            }
            self = .ping(token: token)
        case "navigate":
            guard case .string(let url) = object["url"] else {
                throw WSMessageError.malformed("navigate requires a 'url' string")
            }
            self = .navigate(url: url)
        default:
            throw WSMessageError.malformed("unknown WSIncoming type: \(type)")
        }
    }
}

extension WSOutgoing {
    /// compact single-line json emission (data-free).
    public var jsonText: String {
        var object: [String: JSONValue] = ["type": .string(wireType)]
        switch self {
        case .update(let fragments, let seq):
            object["fragments"] = .array(fragments.map { fragment in
                .object(["id": .string(fragment.id), "html": .string(fragment.html)])
            })
            if let seq {
                object["seq"] = .number(Double(seq))
            }
        case .redirect(let url, let replace):
            object["url"] = .string(url)
            object["replace"] = .bool(replace)
        case .state(let path, let value):
            object["path"] = .string(path)
            object["value"] = .string(value)
        case .reload:
            break
        case .error(let code, let message):
            object["code"] = .string(code)
            object["message"] = .string(message)
        case .pong:
            break
        }
        return JSONValue.object(object).serialize()
    }

    /// utf-8 bytes of `jsonText`, for direct `ByteBuffer` writes.
    public var jsonBytes: [UInt8] {
        [UInt8](jsonText.utf8)
    }

    private var wireType: String {
        switch self {
        case .update: return "update"
        case .redirect: return "redirect"
        case .state: return "state"
        case .reload: return "reload"
        case .error: return "error"
        case .pong: return "pong"
        }
    }
}
