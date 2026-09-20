# Top-bar runtime controls: live provider + thinking-effort selection

An app can expose session-scoped runtime choices — here an LLM **provider
dropdown** and a **Low/Medium/High thinking-effort** segmented control in a top
bar over the shell. A selection takes effect on the next request. Durable
pieces:

## `WebUISelect` — styled native `<select>` with change routing

A small no-webui component wrapping a native `<select class="select">` that
routes a `change` event to `onChange` (`event.data["value"]`). Pattern:
`controlAttributes(id: id, event: .change, handler: onChange)`. This reuses the
existing `.select` CSS (already used by `WebUIPagination`'s rows-per-page
select) and the runtime's `change` → `{ value }` extract. Options are
`WebUISelect.Option(value:label:)`.

```swift
// WebUIShell.swift
public struct WebUISelect: View {
    public struct Option: Sendable, Equatable { public let value: String; public let label: String }
    public let id: String; public let options: [Option]; public let value: String?; public let onChange: EventHandler?
    public func render() -> String {
        let attrs = controlAttributes(id: id, event: .change, handler: onChange)
        var html = "<select id=\"" + htmlEscape(id) + "\" class=\"select\"" + attrs + ">"
        for opt in options {
            let sel = opt.value == value ? " selected" : ""
            html += "<option value=\"" + htmlEscape(opt.value) + "\"" + sel + ">" + htmlEscape(opt.label) + "</option>"
        }
        return html + "</select>"
    }
}
```

Use for many-option selects; use `WebUISegmentedControl` for a few
mutually-exclusive choices (like low/medium/high).

## `RuntimeSettings` actor + `applyRuntimeSettings()`

Live selections are not write-through config (they reset on restart). Hold them
in a shared actor; the app re-reads and re-applies at the top of every turn.

```swift
public actor RuntimeSettings {
    public static let shared = RuntimeSettings()
    private(set) var reasoningEffort = "medium"     // low|medium|high
    private(set) var providerName: String?
    private(set) var providerBaseURL: String?
    func setEffort(_ e: String) { reasoningEffort = e }
    func overrideProvider(name: String, baseURL: String?) { providerName = name; providerBaseURL = baseURL }
    func clearProvider() { providerName = nil; providerBaseURL = nil }
}
```

In the host app, `applyRuntimeSettings()` reads the snapshot and rebuilds the
client only when it changed (track `lastAppliedProvider/BaseURL/Effort` to avoid
rebuilding every turn). The client is built with the chosen `baseURL` and a
`RequestParameters(reasoningEffort: effort == "auto" ? nil : effort)`; the
OpenAI-compatible client serializes that as the `reasoning_effort` request field
(reasoning models honor it).

**Call it at the start of the turn, before you capture the client** — the turn
loop uses the *passed* client, so a rebuild inside the loop wouldn't be picked
up. In the turn handler: `await applyRuntimeSettings()`
then `guard let client = self.llmClient …`. Gate it on the change so it's a no-op
when nothing changed.

## Wiring the controls

- Options: `"default"` (the configured provider) + each available provider
  name; `value` = the current config provider.
- Handlers update the actor over the ws router (registered under the render
  token like any other control); return `[]` (no re-render needed). `"default"`
  → `clearProvider()`.
- Provider switch keeps the current **model** and changes only the **endpoint**
  (so pick the provider that serves the model). Making the model switch too (or
  a second model dropdown) is the natural follow-up.

## Verification

- Top bar renders: provider `<select>` (`data-event="change"`) + effort
  segmented (`data-component-id`, `data-event="click"`); the provider select
  `options` list the providers and the initial `value` is the config provider.
- Select `default` in the provider select → `clearProvider` fires, no errors.
  Click an effort option → `setEffort` fires.
- A turn after changing provider/effort uses the new endpoint / sends
  `reasoning_effort` (verify via the model's behavior or a request capture).
