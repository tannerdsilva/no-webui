// MARK: - WebSocket Protocol Types

/// How a fragment update is applied by the client:
/// - `.replace` (the default): `html` replaces the element with this id wholesale.
/// - `.append`: `html` is inserted as a child of the id (before the `before` child
///   when named) — one inserted subtree, no sibling parsing. The inserted child's
///   own id makes the append idempotent (a repeat is skipped).
/// - `.text`: `text` becomes the id's text content — the token-append primitive.
///   The target must be a text-only element.
public enum FragmentOp: String, Sendable, Codable, Equatable, Hashable {
    case replace
    case append
    case text
}

public struct FragmentUpdate: Sendable, Codable, Equatable, Hashable {
    public let id: String
    public let html: String
    /// `false` opts this update out of the client's view-transition animation;
    /// `nil` (the default) leaves the client's transition policy in charge
    /// (see the engine's `data-webui-transition="off"` region opt-out).
    public let transition: Bool?
    /// `nil` means `.replace`; `.replace` emits no `op` on the wire.
    public let op: FragmentOp?
    /// `.text` payload.
    public let text: String?
    /// `.append` anchor: insert before this child id (default: at the end).
    public let before: String?
    public init(
        id: String,
        html: String,
        transition: Bool? = nil,
        op: FragmentOp? = nil,
        text: String? = nil,
        before: String? = nil
    ) {
        self.id = id
        self.html = html
        self.transition = transition
        self.op = op
        self.text = text
        self.before = before
    }

    /// Insert `html` as a child of `#id` (before the named child when given)
    /// instead of replacing the container.
    public static func append(id: String, html: String, before: String? = nil, transition: Bool? = nil) -> FragmentUpdate {
        FragmentUpdate(id: id, html: html, transition: transition, op: .append, before: before)
    }

    /// Write `value` into `#id`'s text content.
    public static func text(id: String, value: String, transition: Bool? = nil) -> FragmentUpdate {
        FragmentUpdate(id: id, html: "", transition: transition, op: .text, text: value)
    }
}

// MARK: - Incoming Messages (Client → Server)
public enum WSIncoming: Sendable, Equatable {
    case event(component: String, event: String, data: [String: JSONValue], token: String?)
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
            let data = try container.decodeIfPresent([String: JSONValue].self, forKey: .data) ?? [:]
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
    case token(String)
}

extension WSOutgoing: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type, fragments, seq, url, replace, path, value, code, message, token
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
        case .token(let token):
            try container.encode("token", forKey: .type)
            try container.encode(token, forKey: .token)
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
            var data: [String: JSONValue] = [:]
            if let rawData = object["data"] {
                guard case .object(let dataObject) = rawData else {
                    throw WSMessageError.malformed("event 'data' must be an object")
                }
                // widened (p3): values ride through as typed JSONValue —
                // strings, numbers, booleans, nested structures.
                data = dataObject
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
                var encoded: [String: JSONValue] = ["id": .string(fragment.id), "html": .string(fragment.html)]
                if let transition = fragment.transition {
                    encoded["transition"] = .bool(transition)
                }
                if let op = fragment.op, op != .replace {
                    encoded["op"] = .string(op.rawValue)
                }
                if let text = fragment.text {
                    encoded["text"] = .string(text)
                }
                if let before = fragment.before {
                    encoded["before"] = .string(before)
                }
                return .object(encoded)
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
        case .token(let token):
            object["token"] = .string(token)
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
        case .token: return "token"
        }
    }
}
