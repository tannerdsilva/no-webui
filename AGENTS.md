# AGENTS.md — no-webui

operational guidance for autonomous agents working on this project.

## project overview

one Package.swift, one family — the swiftui-for-web stack:

1. **WebUI** — the swiftui-for-web core: view protocol, primitives, layouts,
   modifiers, css system, html document assembly, websocket protocol, js
   runtime. the host of the design-system assets (embedded at build time).
   actively developed — this is where most work happens.
2. **WebUIDesignSystem** — the nexus design system: 225 css custom properties
   (tokens) and 22 styled components. mature, stable.
3. **WebUIAuth** — authentication + sessions: identity model, session tokens,
   cookies, in-memory + LMDB session stores, argon2id password verification,
   constant-time compare, `AuthContext`.

the low-level core libraries (ip, futures, fifo, pthread) were removed from
the manifest — the package is web-ui only now.

## first law — comments allowed in swift, none in shipped web assets

comments are welcome in swift source. `///` doc comments and `//` line comments
are fine anywhere a comment helps — libraries, executables, plugins, tests.
`// MARK:` remains the convention for structural navigation.

the one place comments stay forbidden is the distributed web surface: the html,
css, and js shipped to clients. `designer/assets/design-system.css`,
`designer/assets/webui-runtime.js`, and every generated html document go over
the wire verbatim — comments there are payload weight and leak implementation
detail. keep the bytes the client receives free of comments.

framework-level prose documentation still belongs in `Documentation/*.md`;
inline comments explain code, markdown files explain architecture and APIs.

## build and test

```bash
swift build             # includes the WebUIAssetPlugin that auto-generates Assets+Generated.swift
swift test              # 398 tests, 35 suites
swift run WebUIExample  # example server on :9090
```

all project tooling is command plugins — there are no shell scripts. see
`Documentation/ASSEMBLY.md` for the full stage map and `designer/README.md`
for the designer workflow.

## plugin verbs

| verb | how to run | what it does |
|---|---|---|
| `serve` | `swift package --disable-sandbox plugin serve` | hosts the WebUISmokeTest server on :9123 (long-running; Ctrl+C stops, no orphans). binds require the sandbox to be disabled. |
| `smoke` | `swift package --disable-sandbox plugin smoke` | self-contained gate: spawns the server, checks served-asset byte integrity + page signatures + CSP + interactive-component count, tears down. |
| `fullstack-smoke` | `swift package --disable-sandbox plugin fullstack-smoke` | self-contained gate: spawns the server, drives live WebSocket round-trips (click/echo/redirect/optimistic) via node, tears down. |
| `probe` | `swift package plugin probe [port]` | connect-based port check (bind-probe is sandbox-denied). |
| `showcase` | `swift package plugin showcase --allow-writing-to-package-directory` | regenerates `designer/previews/showcase.html` directly (declared `writeToPackageDirectory`). add `--output <path>` for ad-hoc targets. |

browser layout gate (not a plugin — headless Chromium cannot run inside the
plugin sandbox):

```bash
node designer/browser-smoke.mjs   # self-contained: builds, serves, drives real DOM (counter/echo, optimistic patch+rollback, scroll survival), screenshots to .smoke/, tears down
```

the `WebUIAssetPlugin` build tool plugin runs automatically during `swift build`.
it reads `designer/assets/*.css` and `*.js` and generates
`Assets+Generated.swift` with the content embedded as Swift string constants.
no manual `swift run WebUIAssetTool` needed. these assets power every served
page; at render time the css is minified (comments + blank lines stripped) so
the client never receives the designer notes kept in the working file (see the
first law).

### why serve/smoke/fullstack-smoke need `--disable-sandbox`

the command-plugin sandbox forbids listening: `bind()` fails with `EPERM` even
when `allowNetworkConnections(scope: .local(ports:))` is granted (that
permission is outbound-only). `--disable-sandbox` (a global flag, placed before
`plugin`) lifts the sandbox for the invocation, letting the plugin spawn the
server child that binds. these verbs therefore declare no network permission —
the flag is the only gate. a forgotten `--disable-sandbox` surfaces as
`server did not become ready on :9123 — run with --disable-sandbox`.

### the lock

a running plugin invocation holds the package `.build` lock for its whole run —
any concurrent `swift package` command waits ("Another instance of SwiftPM is
already running using '.build'"). therefore: never run a gate while `serve` is
up, and never expect a client-style plugin to query a server hosted by another
invocation. gates host their own server, check, and tear down in one call.

## project conventions

### code

- **lowercase comments** in `Documentation/*.md` prose and in `//` line
  comments. sentences start lowercase (no sentence capitalization). preserve
  backticked identifiers, quoted string literals, CLI flags, and acronyms.
- **tabs for indentation** in Swift source. `.spacesToTabs(4)`.
- **value types first** — default to struct. only use class for identity (===),
  reference semantics, or ObjC interop. only use actor for shared mutable state
  accessed from multiple tasks.
- **protocols first** — every abstraction starts as a protocol. multiple
  conformances encouraged. protocols never depend on concrete types.
- **no ad-hoc cleanup** — no `shutdown()` methods on non-Service types.
  cleanup belongs at the end of `Service.run()`.
- **no fatalError() in macro implementations** — always emit a Diagnostic.
- **no defer { await ... }** — `await` is forbidden in `defer` in Swift 6.
- **Swift Testing** (`import Testing`, `@Test`, `#expect`) for all new tests.
- **Swift Regex** over `NSRegularExpression` when targeting macOS 13+.
- **Int over size_t** everywhere.

### web UI framework conventions

- **View protocol** — `func render() -> String`. pure function, no side effects.
- **ViewModifier protocol** — `func apply(to html: String) -> String`. wraps
  rendered HTML with attributes or styles.
- **EventRouter** — routes WebSocket events to registered handlers. thread-safe
  via NSLock. max 10,000 handlers by default. missing-handler events log at
  `.warning` and `handlerCount` is public.
- **event modifiers** — `.onClick`/`.onSubmit`/`.onInput`/`.onChange` plus
  keyboard, mouse, and focus variants (`.onKeyUp`, `.onMouseDown`,
  `.onFocus`/`.onBlur`, `.onFocusIn`/`.onFocusOut`, ...) emit
  `data-component-id` + `data-event` and register the handler in one step. the
  runtime only delivers the event a component declares — a click-only
  component never receives hover/press noise — and every click carries
  `targetId`/`targetClass` so a container handler can tell what was clicked.
  `focus`/`blur` are delivered via the bubbling `focusin`/`focusout` and
  normalized to the declared event name.
- **`RuntimeConfig`** — passed to `HTMLDocument`/`WebUIDocument` to tune the
  js runtime (debounce, reconnect, settle, log level, `wsUrl`). a non-empty
  config turns the bootstrap into `WebUIRuntime.init({...})`; the default
  `WebUIRuntime.init();` is byte-identical.
- **`.onOptimisticClick(predict:perform:)`** — applies a render-time prediction
  to the DOM in the same turn as the click, auto-confirms on the authoritative
  update, and rolls back to last-known-good after `optimisticSettleMs` (5s) if
  the server never confirms. predictions are render-time snapshots — use for
  value-independent transitions (reset, toggle-on, set).
- **`SpaceToken`/`ColorToken`** — back `.padding(.four)` and
  `.foregroundColor(.primary)` with `var(--space-4)` / `var(--color-primary-500)`
  references. every case resolves to a token in `design-system.css`
  (deployment-guarded).
- **fragment save/restore** — scroll position and non-form `[tabindex]` focus
  survive a patch alongside value/checked/caret for form controls.
- **RenderContext** — `@TaskLocal` context for component ID generation and
  handler registration. must be set before rendering.
- **HTMLDocument** — assembles complete HTML with auto-generated CSP and nonce.
- **ObserverList** — thread-safe collection of Observable conformers. max 100
  observers by default.
- **CSRFProtection** — stateless HMAC-SHA256 tokens. no server-side storage.

### asset embedding

CSS and JS assets live in `designer/assets/` (the design system's working
directory). the `WebUIAssetPlugin` build tool plugin reads them and generates
`Assets+Generated.swift` during every build. the generated file lands under
`.build/` (gitignored).

to update assets:
1. edit the `.css` or `.js` file in `designer/assets/`
2. run `swift build` — the plugin regenerates the Swift file automatically

the designer's live preview is `designer/previews/designer-preview.html`, which
links `designer/assets/design-system.css` directly, so it reflects edits
instantly in the browser with no build step.

`designer/previews/showcase.html` is a generated artifact — a compiled snapshot
of the showcase page (Swift sources + embedded assets). it is not hand-edited.
regenerate it with `swift package plugin showcase --allow-writing-to-package-directory`.

### security invariants

these must never be weakened:

1. **CSP with nonces** — every HTML document gets a unique nonce. all inline
   `<script>` tags include `nonce="..."`. default CSP covers script-src,
   style-src, img-src, connect-src.
2. **URL sanitization** — `sanitizeURL()` blocks `javascript:`, `data:`,
   `vbscript:` protocols. applied to Link, Image, Form, Router.
3. **HTML sanitization** — `sanitizeFragmentHTML()` strips `<script>` tags,
   event handler attributes, and javascript: URLs before DOM insertion.
4. **Prototype pollution protection** — `State.set()` rejects `__proto__`,
   `constructor`, `prototype` keys.
5. **Attribute escaping** — `htmlEscape()` on all attribute keys and values
   the framework emits: modifier attributes and primitive `id`/`class`/`name`/
   `for`/`data-status`/`method` parameters alike.
6. **CSRF tokens** — `CSRFProtection` with HMAC-SHA256 stateless tokens.
7. **Thread safety** — NSLock on all EventRouter.State and ObserverList
   mutations.
8. **Growth caps** — EventRouter.maxHandlers (10K) and ObserverList.maxObservers
   (100).

## common workflows

### adding a new primitive view

1. add the struct conforming to `View` in `Primitives.swift`
2. add any modifier methods in `Modifiers.swift`
3. add tests in `Tests/WebUITests/`
4. update `Documentation/API.md` with the new type and parameters
5. run `swift test` to verify

### adding a new design system component

1. add the component struct in `WebUIComponents.swift`
2. add CSS classes in `designer/assets/design-system.css`
3. add tests in `Tests/WebUITests/`
4. update `Documentation/DESIGN_SYSTEM.md` with the new component
5. run `swift build` (plugin regenerates assets) then `swift test`
6. run `swift package --disable-sandbox plugin fullstack-smoke` to prove the
   component deploys and interacts live

### regenerating the showcase artifact

1. run `swift package plugin showcase --allow-writing-to-package-directory`
2. review `designer/previews/showcase.html` in a browser

### verifying a change end-to-end

```bash
swift build
swift test
swift package --disable-sandbox plugin smoke
swift package --disable-sandbox plugin fullstack-smoke
node designer/browser-smoke.mjs     # requires node + playwright (chromium)
```

### fixing a security issue

1. fix in the appropriate source file
2. add a test that proves the fix (e.g., XSS payload that now produces safe output)
3. run `swift test` to verify
4. update `Documentation/ARCHITECTURE.md` security table if adding a new mitigation
5. explain the fix inline with a `//` comment where it helps, and update the
   appropriate `Documentation/*.md` file when the change affects documented
   behavior

## pitfalls

- **Assets+Generated.swift** is auto-generated and lives under `.build/`
  (gitignored). if you need to inspect it, run `swift build` first then look in
  `.build/plugins/outputs/no-webui/WebUI/tools/WebUIAssetPlugin/Assets+Generated.swift`.
- **Plugin failures** — if `swift build` fails with a plugin error, check that
  `designer/assets/` exists and contains both `design-system.css`
  and `webui-runtime.js`. if those files are deleted/renamed the build still
  succeeds (the plugin warns and returns no commands) — the server then embeds
  empty assets.
- **bind() is sandbox-denied** — `serve`/`smoke`/`fullstack-smoke` must run with
  `--disable-sandbox`. without it the child server fails to bind and the plugin
  reports `server did not become ready — run with --disable-sandbox`.
- **the `.build` lock** — a running plugin (e.g. `serve`) blocks every other
  `swift package` command until it exits. never launch a gate while `serve` is up.
- **smoke pins the interactive count** — the smoke gate asserts exactly 7
  `data-component-id` attributes on the smoke page. adding or removing an
  interactive component there means updating the expected count in
  `WebUISmokePlugin.swift` (the fullstack driver's `>=6` check is tolerant).
  the same page is what `browser-smoke` drives for optimistic + scroll
  survival, so keep those probes' target ids consistent with the page.
- **showcase permission** — the `showcase` verb declares
  `writeToPackageDirectory`; every invocation needs the approval flag
  (`--allow-writing-to-package-directory`), even with `--output /tmp/...`.
- **stale `-tool` binaries** — when an executable target is also a plugin tool
  dependency, `swift build --target` refreshes
  `.build/<triple>/debug/<Name>-tool`, not `.build/debug/<Name>`. a fresh clone
  (no `.build`) has no staleness: the first plugin invocation cold-builds and
  serves byte-fresh sources.
- **`Logger.Message` type** — swift-log's `Logger` methods take `Logger.Message`,
  not `String`. string concatenation with `+` doesn't produce `Logger.Message`.
  use string interpolation or a single string literal.
- **`@unchecked Sendable`** — used for NSLock-guarded classes. the lock is the
  synchronization mechanism, not the type system. do not remove `@unchecked`
  without adding real Sendable safety.
- **`#if DEBUG`** — avoid for security-relevant warnings. use unconditional
  `Logger.warning()` instead so production builds also see the warning.
- **`defer { txnAbort }` after `txnCommit`** — aborting a committed LMDB
  transaction crashes with SIGTRAP. not applicable here (no LMDB), but worth
  noting for future database work.

## related projects

- `arc-agent` — ARC agent (Swift agent/gateway with LMDB persistence, web UI, MCP)
- `swift-mcp` — MCP server framework for Swift (macros, Service Lifecycle)
- `rawdog` — lean binary encode/decode (alignment, endianness)
