# Agent-chat turn transparency + live streaming (arc-agent / no-webui)

The arc-agent chat (the flagship no-webui consumer) surfaces what the model
did per turn. Two features were built this way (verified end-to-end):
**turn transparency** (reasoning + tool blocks in the thread) and **live
streaming** (they appear progressively, not at turn end). The pattern is
reusable for any no-webui agent chat.

## Core idea: a structured per-turn envelope, not a bare string

The gateway's session response stream is `AsyncStream<String>` (shared by the
web UI, REST `/v1/chat`, and Telegram). The agent now yields a JSON **envelope**
per event instead of one final string. A plain string still decodes to a bare
`finalResponse`, so legacy producers/consumers keep working.

```swift
// AgentTurn.swift
public struct AgentToolStep: Codable { name, arguments, result, isError, durationMs? }
public struct AgentTurn: Codable {
    finalResponse: String        // the answer ("" on interim envelopes)
    reasoning: String            // accumulated CoT
    toolSteps: [AgentToolStep]
    iterations: Int
    promptTokens/completionTokens/totalTokens: Int
    done: Bool                   // terminal envelope for this turn
    func encoded() -> String { JSONEncoder().encode(self) ... }
    static func decodeEnvelope(_ raw: String) -> AgentTurn { ... fallback bare finalResponse }
}
```

Consumers call `AgentTurn.decodeEnvelope(response)`. `finalResponse.isEmpty`
means an interim (live progress) envelope; `done == true` is the terminal one.

## Live streaming turn loop

The non-streaming `runTurnLoop` returns one `AgentTurn` at the end (fine for
CLI). For live streaming, add a streaming method that yields progressively
updated envelopes: reasoning grows, each tool step lands, then the answer.

```swift
nonisolated func runConversationTurnEvents(message: String)
    -> AsyncThrowingStream<AgentTurn, Error> {
    AsyncThrowingStream { continuation in
        Task {
            await self.runConversationTurnEventsLoop(message: message, continuation: continuation)
        }
    }
}
private func runConversationTurnEventsLoop(message: String, continuation: ...) async {
    // actor-isolated loop body: access self.* freely here.
    // yield(AgentTurn(finalResponse: "", reasoning: reasoning, toolSteps: toolSteps)) after each LLM pass
    // yield(AgentTurn(finalResponse: "", reasoning: reasoning, toolSteps: toolSteps)) after each tool dispatch
    // yield(AgentTurn(finalResponse: content, reasoning: reasoning, toolSteps: toolSteps, iterations: ..., done: true))
    // then continuation.finish()
}
```

**Actor isolation gotcha (this bit the build):** the body must NOT be
inlined in the `AsyncThrowingStream { Task { ... } }` closure — that Task is
not actor-isolated, so `self.config` / `self.messageHistory` /
`self.dispatchToolCall` accesses fail to compile ("actor-isolated instance
method cannot be called from outside of the actor"). Extract the body into a
**private actor method** on the actor (like the toolkit's existing
`runStreamingTurnLoop`), and mark the public stream-returning method
`nonisolated` so another actor (the session agent) can call it directly
without `await`. This is the canonical shape.

## THE regression: consumers on a long-lived session stream

The session response stream is **long-lived** (one per session agent, stays
open until the agent is superseded). Previously the agent yielded ONE string
per turn, so REST's `for await ... break` got the answer and returned fine.

Switching to a multi-envelope stream breaks naive consumers **both ways**:
- REST that `break`s on the *first* envelope now returns the interim
  (empty `finalResponse`).
- REST that iterates to the *end* (removing `break`) now **hangs** — the
  stream never closes during a turn, so `for await` never terminates.

**Fix:** add a `done: Bool` on the terminal envelope and have every consumer
`break` on `turn.done` (for the web, also release the composer's `busy` flag
on `done` so the next turn isn't blocked). REST: `if !turn.finalResponse.isEmpty
{ responseText = turn.finalResponse } ; if turn.done { break }`. Web
ChatConnection: replace the single assistant message on each envelope and
`if turn.done { break }`. The helper must strip the `<base>-node-` style
prefixes only for tree ids; the envelope is different (it's a full object).

## Web rendering (no-webui components/CSS)

`ChatMessage` wears `reasoning: String?`, `toolSteps: [AgentToolStep]?`,
`summary: String?`. The assistant bubble body is built as raw HTML:
- `<details class="turn-reasoning"><summary>Reasoning</summary><pre>…</pre></details>`
- per tool: `<div class="turn-tool">` with `.turn-tool__name` (name + duration),
  `.turn-tool__args`, `.turn-tool__result` (truncate long results ~200 chars,
  scrollable via `max-height` + `overflow-y:auto`); `turn-tool--error` variant.
- `.turn-summary` muted line: "N tools · X tokens · M iterations".

Because the framework's `markdownBody` escapes raw HTML, put these blocks in
the content **before** the `markdownBody(finalResponse)` fragment (they are
raw HTML, not markdown). CSS lives in `design-system.css` (`.turn-reasoning`
`.turn-tool` `.turn-summary`), token-only.

## Verification recipe

- Web: log in → send a tool task → poll `document.querySelector('.turn-reasoning')`,
  `.turn-tool`, `.turn-summary`, and full answer. Assert reasoning + tool +
  summary present, and that a SECOND message still sends (busy released).
  Note: label-targeted clicks time out on rows with `pointer-events:none` —
  click the row id (`#base-node-id`) instead.
- REST: `POST /v1/chat` with a tool task must return the plain answer within
  the timeout (a hang means a consumer is iterating to end without a `done`
  break).
- Poll break-conditions must NOT match text that also appears in your own
  prompt (the prompt often contains the tool names/keywords). Match on a reply
  substring that can't be in the prompt, or gate on state that postdates the
  user message.
