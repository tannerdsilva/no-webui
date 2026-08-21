import Foundation
import CommonCrypto

// MARK: - HTML Escaping
public func htmlEscape(_ string: String) -> String {
    guard string.unicodeScalars.contains(where: { c in
        c == "&" || c == "<" || c == ">" || c == "\"" || c == "'"
    }) else { return string }

    var result = ""
    result.reserveCapacity(string.utf8.count + 8)
    for c in string.unicodeScalars {
        switch c {
        case "&":  result += "&amp;"
        case "<":  result += "&lt;"
        case ">":  result += "&gt;"
        case "\"": result += "&quot;"
        case "'":  result += "&#39;"
        default:   result.unicodeScalars.append(c)
        }
    }
    return result
}

// MARK: - Attribute Injection
public func injectAttributes(into html: String, _ attributes: String) -> String {
    guard let firstLessThan = html.firstIndex(of: "<") else {
        return "<span \(attributes)>\(html)</span>"
    }

    let afterLT = html.index(after: firstLessThan)
    guard afterLT < html.endIndex else {
        return "<span \(attributes)>\(html)</span>"
    }

    let peek = html[afterLT]
    guard peek != "/" && peek != "!" && peek != "?" else {
        return html
    }

    var inQuote = false
    var quoteChar: Character = "\""
    var tagEnd: String.Index?

    var i = html.index(after: firstLessThan)
    while i < html.endIndex {
        let c = html[i]
        if inQuote {
            if c == quoteChar {
                inQuote = false
            }
        } else if c == "\"" || c == "'" {
            inQuote = true
            quoteChar = c
        } else if c == ">" {
            tagEnd = i
            break
        }
        i = html.index(after: i)
    }

    guard let end = tagEnd else {
        return "<span \(attributes)>\(html)</span>"
    }

    let beforeEnd = html.index(before: end)
    if html[beforeEnd] == "/" {
        return String(html[..<beforeEnd]) + " " + attributes + String(html[beforeEnd...])
    } else {
        return String(html[..<end]) + " " + attributes + String(html[end...])
    }
}

// MARK: - Markdown Rendering (Stub)
public func markdownToHTML(_ markdown: String) -> String {
    "<p>\(htmlEscape(markdown))</p>"
}

// MARK: - Syntax Highlighting (Stub)
public func highlightCode(_ code: String, language: String) -> String {
    htmlEscape(code)
}

// MARK: - SVG Inline Helpers
public func inlineSVG(viewBox: String = "0 0 24 24", width: Int = 24, height: Int = 24, _ content: String) -> String {
    """
    <svg viewBox="\(viewBox)" width="\(width)" height="\(height)" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    \(content)
    </svg>
    """
}

// MARK: - URL Sanitization
private let unsafeURLProtocols: Set<String> = ["javascript", "data", "vbscript"]
public func sanitizeURL(_ url: String) -> String? {
    guard let colonIndex = url.firstIndex(of: ":") else { return url }
    let scheme = String(url[url.startIndex..<colonIndex]).lowercased()
    guard unsafeURLProtocols.contains(scheme) else { return url }
    return nil
}

// MARK: - CSRF Protection
public enum CSRFProtection {
    public static let defaultMaxAge: TimeInterval = 1800
    public static func generateSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
    public static func token(for formID: String, secret: String, maxAge: TimeInterval = defaultMaxAge) -> String {
        let expires = Date().timeIntervalSince1970 + maxAge
        let payload = "\(formID):\(Int(expires))"
        let signature = hmacSHA256(key: secret, message: payload)
        let tokenData = "\(payload):\(signature)".data(using: .utf8)!
        return tokenData.base64EncodedString()
    }
    public static func validate(_ token: String, for formID: String, secret: String) -> Bool {
        guard let tokenData = Data(base64Encoded: token),
              let tokenStr = String(data: tokenData, encoding: .utf8) else {
            return false
        }
        let parts = tokenStr.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        let payloadFormID = String(parts[0])
        let expiresStr = String(parts[1])
        let signature = String(parts[2])

        guard payloadFormID == formID,
              let expires = TimeInterval(expiresStr),
              Date().timeIntervalSince1970 < expires else {
            return false
        }

        let expectedSignature = hmacSHA256(key: secret, message: "\(formID):\(expiresStr)")
        return signature == expectedSignature
    }
    private static func hmacSHA256(key: String, message: String) -> String {
        guard let keyData = key.data(using: .utf8),
              let messageData = message.data(using: .utf8) else {
            return ""
        }
        var mac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyPtr in
            messageData.withUnsafeBytes { msgPtr in
                mac.withUnsafeMutableBytes { macPtr in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                           keyPtr.baseAddress, keyData.count,
                           msgPtr.baseAddress, messageData.count,
                           macPtr.baseAddress)
                }
            }
        }
        return mac.map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - Conditional Attribute Helper
public func attrIf(_ name: String, _ value: String, _ condition: Bool) -> String {
    condition ? " \(name)=\"\(value)\"" : ""
}
public func classIf(_ className: String, _ condition: Bool) -> String {
    condition ? " \(className)" : ""
}
