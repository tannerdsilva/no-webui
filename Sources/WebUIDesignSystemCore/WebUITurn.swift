import Foundation
import WebUICore

// MARK: - Turn transparency components
//
// The per-turn transparency region of an agent chat: a collapsible
// reasoning transcript, one block per tool the agent executed, and a muted
// one-line turn summary. The CSS lives in `design-system.css`
// (`.turn-reasoning`, `.turn-tool`, `.turn-summary` — token-only) and these
// components are the Swift surface for it. Any no-webui agent host that
// surfaces live turns composes these instead of hand-writing markup.

/// a collapsible transcript of the model's reasoning (CoT) for one turn.
/// wraps a `<details>`/`<summary>` disclosure, styled by the design system.
public struct WebUIReasoningBlock: View {
    public let reasoning: String

    public init(_ reasoning: String) {
        self.reasoning = reasoning
    }

    public func render() -> String {
        "<details class=\"turn-reasoning\"><summary>Reasoning</summary><pre>"
            + htmlEscape(reasoning)
            + "</pre></details>"
    }
}

/// one tool the agent executed during a turn: name (+ optional duration
/// meta), the arguments it received, and the (optionally truncated) result.
/// `isError` switches the block to the error variant styling.
public struct WebUIToolStep: View {
    public let name: String
    public let arguments: String
    public let result: String
    public let isError: Bool
    /// rendered inline after the name, e.g. " · 120ms".
    public let meta: String?

    public init(
        name: String,
        arguments: String = "",
        result: String = "",
        isError: Bool = false,
        meta: String? = nil
    ) {
        self.name = name
        self.arguments = arguments
        self.result = result
        self.isError = isError
        self.meta = meta
    }

    public func render() -> String {
        var classes = "turn-tool"
        if isError { classes += " turn-tool--error" }

        var html = "<div class=\"\(classes)\"><span class=\"turn-tool__name\">"
        html += htmlEscape(name)
        if let meta {
            html += htmlEscape(meta)
        }
        html += "</span>"
        html += "<pre class=\"turn-tool__args\">" + htmlEscape(arguments) + "</pre>"
        html += "<pre class=\"turn-tool__result\">" + htmlEscape(result) + "</pre>"
        html += "</div>"
        return html
    }
}

/// a compact muted summary line for one turn
/// (e.g. "3 tools · 1.2k tokens · 4 iterations").
public struct WebUITurnSummary: View {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public func render() -> String {
        "<div class=\"turn-summary\">" + htmlEscape(text) + "</div>"
    }
}
