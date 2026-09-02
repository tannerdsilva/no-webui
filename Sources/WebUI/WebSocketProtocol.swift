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
public enum WSIncoming: Sendable {
    case event(component: String, event: String, data: [String: String])
    case ping
    case navigate(url: String)
}

extension WSIncoming: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, component, event, data, url
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "event":
            let component = try container.decode(String.self, forKey: .component)
            let event = try container.decode(String.self, forKey: .event)
            let data = try container.decodeIfPresent([String: String].self, forKey: .data) ?? [:]
            self = .event(component: component, event: event, data: data)
        case "ping":
            self = .ping
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
