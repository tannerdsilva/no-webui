# High-level shell components — building a no-webui "powered app"

Session 2026-09-19: built a 4-column app shell (nav rail, two side panels, a
main content column) entirely from NEW high-level no-webui components — no
host-side raw `Div`/`Button`/class strings. The goal: no-webui should enable
"as complex and sophisticated web ui as possible, with as little swift code as
possible", and a host app should lean on it maximally.

## The components (the library side)

`Sources/WebUIDesignSystemCore/WebUIShell.swift` (re-exported to consumers via
`@_exported import WebUIDesignSystemCore` in `Sources/WebUIDesignSystem/`), with
CSS for each in `designer/assets/design-system.css`:

| component | purpose | key params |
|---|---|---|
| `WebUISidebar` | nav rail or full sidebar | `items:[WebUISidebarItem]`, `activeID`, `id`, `style:.rail/.full`, `header`, `onSelect`; item `href` → renders `<a>` |
| `WebUISegmentedControl` | single-select tabs w/ counts | `items:[WebUISegmentedItem]`, `selectedID`, `id`, `size`, `onSelect` |
| `WebUISearchField` | labelled search input | `placeholder`, `id`, `value`, `onInput` |
| `WebUIListView` / `WebUIListItem` | selectable rows | `items`, `selectedID`, `id`, `onSelect` |
| `WebUIComposer` | docked composer | `placeholder`, `inputID`, `id`, `disabled` (default `false`), `onSubmit` |
| `WebUIPanel` | titled side panel | `title`, `subtitle`, `edge:.leading/.trailing`, `actions`, `content` |

Compose with `WebUITree`/`WebUITabs`/`WebUIButton`/`WebUIBadge`/
`WebUIEmptyState`/`WebUISpinner` for the rest. Layout stacks (`HStack`/
`VStack`/`ScrollView`) are fine in the host; raw `Div`/`Button` are not.

## The 4-column app shell (host-side composition)

```
HStack(spacing:0) {
    WebUISidebar(items: railItems, activeID: active, id: "nav-rail", style: .rail).stretch() // ~72px
    WebUIPanel(title:"Chat", subtitle: count, edge:.leading) { search + segmented + list }.width("280px").stretch()
    VStack(spacing:0) { ScrollView{thread bubbles}.id("chat-thread").fill().maxWidth("100%")
                        WebUIComposer(inputID:id, id:"chat-bar", onSubmit: submit).padding(...) }.fill()
    WebUIPanel(title:"Workspace", subtitle: n, edge:.trailing) { WebUITabs + WebUITree }.width("320px").stretch()
}
.fill()   // passed into the shell with fills:true so it owns its scroll regions
```

`AppShell.document(..., fills:true)` hands the content all remaining space
(no wrapping scroll container) so the thread scrolls and the composer stays
docked. `fill()` = `flex:1`; `stretch()` = full height without growing.

## Interaction contract (what makes the round-trip work)

- **Container handler + bare-item ids.** Each of the sidebar/list/segmented
  registers ONE handler on its container via
  `controlAttributes(id: <stable-id>, event: .click, handler: onSelect)`.
  Every row gets a DOM `id` = the **bare item id** (not `<listid>-item-…`),
  and `.…__item > * { pointer-events: none }` so `event.target` = the row.
  The handler dispatches on `event.string("targetId")` (runtime
  `clickTargetData` sets `targetId = event.target.id`). This keeps the target
  id clean and avoids per-row handlers.
- **`replaceElement` consumes the patched node.** Any re-rendered region must
  re-carry its routing anchor. So a fragment-targeted element must be the
  component's own root or a persistent wrapper, and the component re-emits
  `data-component-id` on re-render. `controlAttributes(id:handler:)`
  re-emits attrs WITHOUT re-registering when `RenderContext.current` is nil
  (i.e. during a handler's fragment render) — the page-build registration
  persists in the router, so routing survives re-renders.
- **Composer fragment.** The `<form>` gets BOTH `id="<id>"` (so
  `FragmentUpdate(id:"chat-bar")` can `replaceElement` it) AND
  `data-component-id="<id>"` `data-event="submit"` (routing). The submit
  handler reads `event.string("message")` (form `name="message"`).
- **Fresh input id per composer render** (`nextInputID()`) so the runtime's
  input-state preservation can't restore a sent message into the cleared box.

## Escaping check (bites every generated-HTML component)

After writing a `render()` that concatenates HTML, confirm the served page has
no literal source fragments:
```bash
curl -s http://127.0.0.1:PORT/ | grep -c htmlEscape        # want 0 (besides JS source)
grep -n 'htmlEscape(item' Sources/WebUIDesignSystemCore/WebUIShell.swift | head | od -c
```
A doubled backslash (`\\(htmlEscape…` / `\\"`) emits literal text. `write_file`
does NOT double backslashes (`od -c` proves single `\`), so double backslashes
indicate the authored content. Prefer multiline `"""` strings to avoid `\"`.

## Verification recipe (host app)

1. `cd ~/workspace/no-webui && swift build` (re-embeds `design-system.css` via
   `WebUIAssetPlugin`) then `swift package plugin showcase
   --allow-writing-to-package-directory` if you changed the showcase.
2. `cd <your-app> && swift build` (the path dependency picks up the new
   components + CSS).
3. Serve auth-disabled on two fresh ports that don't collide with any running
   instance: `<your-app> serve --port 8198 --web-port 8199`.
4. Verify in a browser under a **dark** color-scheme (assert the body
   background is `rgb(6,9,16)` before screenshotting) — dark mode is automatic.
5. Confirm the search-field computed `padding-left` is `36px` (2.25rem) — if
   it's `12px` the reset `:not()` chain is clobbering it (add `:not(.search-field__input)`).
6. Confirmed the render token is baked into the served page
   (`WebUIRuntime.init({"renderToken":"…"})`).

## Composer round-trip — VERIFIED WORKING (2026-09-19)

The interactive submit round-trip works end-to-end against a live host
gateway. Earlier "403 / gateway gate" and "composer broken" observations were
**artifacts of browser instrumentation, not a real defect**: a raw-shell
`curl -H "Upgrade: websocket"` probe 403s at the upgrade gate (`/ws`), and
overriding `window.WebSocket` in the browser (to capture `send`) corrupts the
runtime's socket state, so the runtime stops transmitting (no server dispatch,
sockets close with code 1006). Both are test-harness confounds.

The faithfully-working path (verified in a CLEAN, uninstrumented browser
context):
1. `config.renderToken` is baked in (`WebUIRuntime.init({"renderToken":"…"})`)
   and preserved in the live runtime (the `DEFAULTS`-whitelist fix in
   `render-token-whitelist-bounce.md` is applied; `renderToken: null` is in
   `DEFAULTS`).
2. The runtime connects to `/ws`, socket reaches readyState OPEN, and
   `wsClient.isConnected()` is true. `handleEvent` process the form `submit`
   (it `preventDefault`s).
3. Submitting sends `{"type":"event","component":"chat-bar","event":"submit",
   "data":{"message":"…"},"token":"<renderToken>"}`; the server's `boundEntry`
   resolves via `routers.resolve(forTokenHash:renderToken:)` and the handler
   runs. The thread appends the user message + "thinking…" status and the
   composer clears.

Verified clean-context result: `sent` carries the tokenized submit, thread =
`"you\n<msg>\nthinking…"`, composer value `""`.

Pitfall for future tests: never inject a `WebSocket`-crafting init script into
the MCP page to "observe" sends — it breaks the runtime. Create a fresh
`browser.newContext()` page (no init script) and drive it directly, or assert
on DOM effects (thread content, composer cleared) rather than intercepted
frames.

## Showcase demo section

Add a `section("Shell Components", "shell")` block in
`Sources/WebUIShowcase/ShowcasePage.swift` (after the "Design System" section)
with one `demoCard(...)` per new component. Then regenerate.
