# Live server + component internals (no-webui)

Session-derived detail: the "serve a page live from Swift" recipe (as done for
`WebUIShowcaseServer`) and the `*__body` padding convention that explains a
whole family of "content flush against the container edge" bugs.

## Container components pad via `*__body`, not the container

Panel/container design-system components carry their interior padding on a
`__body` *child* element, never on the container itself. Examples in
`design-system.css` / the components:

- `.card { padding: 0; … }` but `.card__body { padding: var(--space-4); }`
- `.panel__body`, `.alert__body`, `.list__body`, `.modal__body` — same idea.

Consequence: if a `WebUI*` container renders its content flush against a
rounded/edged box (e.g. the `WebUICard` bug where `Counter`/buttons sat at the
card's edge), the fix is to **wrap the children in the `__body` element**, not
to add padding to the container. `WebUICard.render()` was emitting
`<div class="card …">…children…</div>` with no `.card__body`; the fix wraps the
children so the stylesheet's `--space-4` default actually applies.

The padding is a **CSS token default, overridable** via the normal cascade:
a host can override it with a page-scoped style, a modifier, or a more-specific
rule. Verify it's a real default (not baked inline) by injecting a competing
rule and re-reading `getComputedStyle(...).padding`:
`default 16px → inject .card__body { padding: var(--space-1); } → 4px`.

When auditing a new container component for this class of bug, read the CSS
rule for the element you see flush, then check whether the component emits the
`__body` wrapper that carries the padding.

## Serving a no-webui page from a live Swift NIO server

The always-on server pattern (as in `WebUIExample`, `WebUISmokeTest`, and the
new `WebUIShowcaseServer`).

- **Executable targets can't be imported by other targets.** If a page
  composition (e.g. `ShowcasePage`) must be shared between a generator
  executable and a new server executable, move it into a **library target**
  (mirroring the `WebUISmokeShared` pattern), make the struct `public` with a
  `public init()`, and have both executables depend on that library.
- **Model the server on `WebUIExample/main.swift`:**
  `NIOTypedWebSocketServerUpgrader` + `NIOUpgradableHTTPServerPipelineConfiguration`;
  wrap the non-upgraded channel into
  `NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>`;
  add an outbound `HTTPByteBufferResponsePartHandler` (converts the typed
  `HTTPPart` back to `HTTPServerResponsePart`); respond via
  `channel.channel.writeAndFlush(HTTPPart<…>.end(nil)).get()`.
- **`includeRuntime: true` requires a working `/ws`.** Setting it makes the
  page's JS runtime open a `/ws` socket at load. The server MUST upgrade
  `/ws` and at least answer `.ping` frames with `.pong` (and echo a close),
  or the client logs a failed-handshake console error on every load. A purely
  static reference page uses `includeRuntime: false` for exactly this reason.
- **Render the page per request** to reflect current Swift source (each render
  mints a fresh CSP nonce). Prewarm `DesignSystemAssets.prewarm()` before the
  first request so the one-time minify never lands in a handler.
- **Plugin verb (optional)**: mirror the `serve` plugin — `context.tool(named:)`
  spawns the built server as a child, forwards SIGTERM/SIGINT, polls
  `httpOK(base/)` until ready, and prints a `Ctrl+C to stop` banner. Requires
  `--disable-sandbox` (the command-plugin sandbox forbids `bind()`). Confirm the
  verb registered via `swift package plugin --list`.
- **Run it directly** — a plain `swift run` isn't sandboxed, so unlike a plugin
  invocation no `--disable-sandbox` is needed:
  `swift run WebUIShowcaseServer --port 9092`, or via the plugin
  `swift package --disable-sandbox plugin showcase-serve`. The shared library is
  `WebUIShowcaseContent` (holds `ShowcasePage`), used by both the static
  `WebUIShowcase` generator and the live `WebUIShowcaseServer`.
