# AGENTS.md — no-webui

operational guidance for autonomous agents working on this project.

## project overview

one Package.swift, one family — the swiftui-for-web stack:

1. **WebUI** — the swiftui-for-web core: view protocol, primitives, layouts,
   modifiers, css system, html document assembly, websocket protocol, js
   runtime. the host of the design-system assets (embedded at build time).
   actively developed — this is where most work happens.
2. **WebUIDesignSystem** — the nexus design system: 257 css custom properties
   (tokens) and 133 component types. mature, stable. the counts are measured,
   not asserted — re-measure rather than trust them:
   `grep -oE '^\s*--[a-z0-9-]+:' designer/assets/design-system.css | sort -u | wc -l`,
   `grep -rhoE '^public struct WebUI[A-Za-z]+' Sources/WebUIDesignSystemCore/*.swift | sort -u | wc -l`.
3. **WebUIAuth** — authentication + sessions: identity model, session tokens,
   cookies, in-memory session store behind an `AuthSessionStore` protocol,
   argon2id password verification,
   constant-time compare, `AuthContext`.

4. **WebUIChart / WebUIServer / WebUIBlocks** — the surface around the core: a
   declarative chart library (`Documentation/CHARTS.md`), the NIO server that
   hosts a page plus its assets and websocket, and the standalone page
   scaffolds (dashboard, login, signup, four sidebar variants, patterns),
   served one per process by `WebUIBlocksServer`.

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
swift build             # includes the WebUIAssetPlugin + WebUIIconPlugin + WebUIWasmPlugin (auto-generates Assets+Generated.swift + DesignTokens+Generated.swift + IconLibrary.swift + Wasm+Generated.swift)
swift test              # 805 tests — re-count rather than trust: grep -rc '@Test' Tests/ | awk -F: '{s+=$2} END {print s}'
swift run WebUIExample  # example server on :9090
```

the wasm client is a separate product built with the official swift 6.4 wasm sdk
(the swiftly-hosted `swift-6.4-RELEASE` toolchain — the Xcode frontend cannot
read the sdk's prebuilt modules and lacks `swift-autolink-extract`; wasm commands
need the swiftly shim, not `source ~/.swiftly/env.sh`, which is
PATH-order-dependent in spawn contexts). the *native* way to produce an
island artifact is the `wasm-island` plugin verb (see below) — it wraps the raw
invocation in an isolated scratch build root:

```bash
swift package --disable-sandbox plugin wasm-island [--product TheirIsland] [--no-strip]
# verify modes (an island is browser-hosted once its env imports are linked)
node designer/browser-smoke.mjs
```

the `wasm-island` verb cross-builds into `.build/wasm-island-scratch` (an
isolated build root — the plugin invocation holds the package `.build` lock,
so building into the package's own `.build` deadlocks), strips custom sections
(name table + DWARF) by default (`--no-strip` keeps readable devtools stack
traces), and copies the artifact to
`.build/out/Products/Release-webassembly-wasm32/<product>.wasm` — the path the
`WebUIWasmPlugin` build-tool plugin validates + hashes into `WebUIWasmInfo`
during every host build.

pages are engine-first: the default client runtime is `webui-engine.js`
(`HTMLDocument`/`WebUIDocument` emit the `webui-config` meta + engine script
automatically; `includeRuntime: false` ships no client at all — no script, no
config meta). the wasm monolith client was deleted — the engine is the client runtime, and
wasm survives as capability islands declared per page (see `NEXT_ARCHITECTURE.md`).

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

svg icon toolset (an executable target, not a plugin — the plugin
`WebUIIconPlugin` runs `generate` automatically during every build):

```bash
swift run WebUIIconTool lint --manifest designer/icons/icon-manifest.json
swift run WebUIIconTool list --manifest designer/icons/icon-manifest.json --category actions
swift run WebUIIconTool stats --manifest designer/icons/icon-manifest.json
swift run WebUIIconTool render-preview --manifest designer/icons/icon-manifest.json --output designer/previews/icons-preview.html
```

see `Documentation/ICONS.md` for the full icon guide (catalog, api,
tooling, security).

browser layout gate (not a plugin — headless Chromium cannot run inside the
plugin sandbox):

```bash
node designer/browser-smoke.mjs   # self-contained: builds, serves, drives real DOM (counter/echo, optimistic patch+rollback, scroll survival), screenshots to .smoke/, tears down
```

the `WebUIAssetPlugin` build tool plugin runs automatically during `swift build`.
it reads `designer/assets/*.css` and `*.js` and generates two files: the
`Assets+Generated.swift` embedded-assets enum for the `WebUI` target, and the
`DesignTokens+Generated.swift` token vocabulary for the wasm-clean
`WebUIDesignSystemCore` target (the two outputs are what keep `DesignToken`
reachable from the client build without rawdog). no manual
`swift run WebUIAssetTool` needed. these assets power every served page; at
render time the css is minified (comments + blank lines stripped) so the client
never receives the designer notes kept in the working file (see the first law).

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
  via `Synchronization.Mutex`. max 10,000 handlers by default. missing-handler
  events log at `.debug` (via the unified `logger.emit` funnel) and `handlerCount` is public.
- **event modifiers** — `.onClick`/`.onSubmit`/`.onInput`/`.onChange` plus
  keyboard, mouse, and focus variants (`.onKeyUp`, `.onMouseDown`,
  `.onFocus`/`.onBlur`, `.onFocusIn`/`.onFocusOut`, ...) emit
  `data-component-id` + `data-event` and register the handler in one step. the
  runtime only delivers the event a component declares — a click-only
  component never receives hover/press noise — and every click carries
  `targetId`/`targetClass` so a container handler can tell what was clicked — `targetId` resolves to the
  nearest id-bearing element *inside* the component boundary (a click usually
  lands on a label or icon child, not the item); clicking the component itself
  reports none.
  `focus`/`blur` are delivered via the bubbling `focusin`/`focusout` and
  normalized to the declared event name.
- **typed component handlers** — `ElementRef` + `controlAttributes(id:event:handler:)`
  give components self-wiring interactive controls: `WebUITable`
  (`.onSort`/`.onSelectAll`/`.onSelect`/`.onToggleExpand`), `WebUIPagination`
  (`.onPageChange`/`.onRowsPerPageChange`), `WebUIChart` (`.onSelectMark`),
  and dismissibles (`.onDismiss`) each register their controls under stable ids
  at page build and hand the handler an `ElementRef` + typed payload — no
  `targetId`/`targetClass` string matching, no container handler. `me.remove()`
  relies on the pinned empty-fragment-removes-element runtime branch.
  `controlAttributes` re-emits the stable id on context-free fragment re-renders
  without re-registering, which is what keeps routing alive across patches.
- **`RuntimeConfig`** — passed to `HTMLDocument`/`WebUIDocument` to tune the
  js runtime (debounce, reconnect, settle, log level, `wsUrl`). a non-empty
  config turns the bootstrap into `WebUIRuntime.init({...})`; the default
  `WebUIRuntime.init();` is byte-identical.
- **`.onOptimisticClick(predict:perform:)`** — applies a render-time prediction
  to the DOM in the same turn as the click, auto-confirms on the authoritative
  update, and rolls back to last-known-good after `optimisticSettleMs` (5s) if
  the server never confirms. predictions are render-time snapshots — use for
  value-independent transitions (reset, toggle-on, set).
- **`WebUIIcon` / `IconName`** — native svg iconography. `IconName` is a
  generated `CaseIterable` enum (618 glyphs from
  `designer/icons/icon-manifest.json`); `WebUIIcon` renders inline
  `<svg stroke="currentColor">` so coloring rides `ColorToken` via
  `.foregroundColor(_:)`. `IconSize` is `.small/.medium/.large/.extraLarge`
  (em multiples) or `.slot` (sized by the container's icon-slot css — used by
  alert/empty-state/tree/table). `WebUIIconCustom` sanitizes caller-supplied
  geometry. the emoji-based `icon: String` parameters are gone — the four
  migrated components take `IconName` (`IconName(emoji:)` bridges ~30 legacy
  glyphs). see `Documentation/ICONS.md`.
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
`Assets+Generated.swift` during every build (embedded into the `WebUI`
target), plus `DesignTokens+Generated.swift` (the generated `DesignToken`
vocabulary, embedded into `WebUIDesignSystemCore`). the generated files land
under `.build/` (gitignored).

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
3. **HTML sanitization** — the runtime parses each fragment into a detached
   DOM subtree (the target element as parse context, so table fragments
   survive), then strips `<script>` elements, `on*` event-handler attributes,
   and unsafe `href`/`src`/`action`/`formaction`/`xlink:href` values on the
   real nodes — the parser itself resolves character references and attribute
   quoting, so entity- and whitespace-obfuscated `javascript:` schemes cannot
   ride into the DOM.
4. **Prototype pollution protection** — `State.set()` rejects `__proto__`,
   `constructor`, `prototype` keys.
5. **Attribute escaping** — `htmlEscape()` on all attribute keys and values
   the framework emits: modifier attributes and primitive `id`/`class`/`name`/
   `for`/`data-status`/`method` parameters and every `aria-*`/`role` emission
   (the chart empty-state figure included) alike. icon `aria-label`/`class`/
   `data-icon` included.
6. **CSRF tokens** — `CSRFProtection` with HMAC-SHA256 stateless tokens. secret
   and token minting fail loudly (`throws`) on entropy or hmac failure — no prng
   fallback, and `validate` returns `false` on signing failure (never co-signs an
   empty signature). pre-auth login tokens are single-use via `SingleUseTokenStore`,
   which budgets unsubmitted tokens per issuer key (`maxOutstandingPerKey`,
   default 5) so one caller cannot stockpile tokens and flood the store.
7. **Thread safety** — `Mutex` (Swift `Synchronization`) on all EventRouter.State
   and ObserverList mutations.
8. **Growth caps** — EventRouter.maxHandlers (10K) and ObserverList.maxObservers
   (100).
9. **SVG icon sanitization** — `IconSanitizer.sanitize()` is a parse-and-reemit
   allowlist, not a regex denylist: only geometry elements (`path`/`line`/
   `circle`/`rect`/`polyline`/`polygon`/`ellipse`) and geometry/stroke/fill
   presentation attributes re-emit, self-closing and html-escaped — `script`,
   `foreignObject`, url-bearing attributes, and `on*` handlers are absent from
   the allowlist by construction, so whitespace- and entity-obfuscated
   `javascript:`/`data:` schemes cannot ride into any `WebUIIconCustom` body.
10. **Bounded wire parsing** — `JSONValue.parse` caps container nesting at 128
    (`JSONError.nestingTooDeep`). an adversarial websocket frame — probe-verified
    to stack-overflow the parser at ~5k depth inside NIO's 16 kb frame budget —
    throws, never crashes.
11. **Websocket render binding** — pages mint a per-render token
    (`RuntimeConfig.renderToken`) and every `event`/`ping` echoes it; a server
    that mints tokens routes each message against the session's current render
    tokens and closes the socket on unknown/missing ones. a stale page from a
    different (or former) session can never drive another user's router.

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

### adding a new icon

1. add the icon object to `designer/icons/icon-manifest.json` (name, category,
   title, tags, viewBox, and the inner svg elements — real 24-grid geometry
   from a licensed stroke set)
2. `swift run WebUIIconTool lint --manifest designer/icons/icon-manifest.json`
   (validates the element whitelist, self-closing tags, and on-grid bounds)
3. `swift build` — `WebUIIconPlugin` regenerates `IconLibrary.swift`; the new
   case is on `IconName`
4. add/extend tests in `Tests/WebUITests/IconTests.swift` (the catalog-integrity
   suite asserts case count == manifest icon count)
5. `swift run WebUIIconTool render-preview --manifest designer/icons/icon-manifest.json --output designer/previews/icons-preview.html`
   and review in a browser (light + dark)

see `Documentation/ICONS.md` for the full guide.

### verifying a change end-to-end

```bash
swift build
swift test
swift package --disable-sandbox plugin smoke
swift package --disable-sandbox plugin fullstack-smoke
node designer/browser-smoke.mjs      # requires node + playwright (chromium)
node designer/showcase-ws-smoke.mjs  # stable-id dispatch gate against the showcase server
node designer/blocks-sweep.mjs     # p6 blocks gate: one server per block, 320/768/1440 in both themes, no-overflow + parts assertions
node designer/rtl-audit.mjs        # p7 direction gate: both directions x both themes x 3 viewports, mirrored-order assertions with an ltr control
```

the dispatch gate exists because the other four steps cannot see this failure: `smoke`
checks served bytes, `fullstack-smoke` drives the *smoke* page, and the unit pins count
handler registrations without ever dispatching one. `showcase-ws-smoke` spawns
`WebUIShowcaseServer`, clicks a stable-id control (`controlAttributes`, e.g. a table sort
header) in a real browser, captures the websocket frames and requires both the outbound
`event` and an inbound `update`. a click that sends but never receives is exactly the
class of break that shipped invisibly on :9092.

**this gate is GREEN, and it is the honest observer the earlier revision lacked.** it is
a *raw* client: it fetches the page over HTTP, reads the stable control ids out of the
served markup, connects its own socket and asserts a non-empty `update` reply — no browser,
no page patching, nothing inferred. first green run: 27 stable-id controls, all three probed
sort headers answered with one fragment each.

**what it corrected:** an earlier browser-based revision of this gate, which captured frames
by patching `WebSocket` *inside the page*, reported "sent but never answered" for every
probe. that was an instrument artifact (the engine assigns `onmessage` on the instance at
connect time, so a post-load hook is blind; a pre-boot hook perturbs the page). the server
had been answering correctly the whole time. lesson recorded in
`.hermes/plans/2026-09-26_094442-verification-rearchitecture.md`: never patch the runtime you
are measuring, and make every probe assert its own preconditions.

### fixing a security issue

1. fix in the appropriate source file
2. add a test that proves the fix (e.g., XSS payload that now produces safe output)
3. run `swift test` to verify
4. update `Documentation/ARCHITECTURE.md` security table if adding a new mitigation
5. explain the fix inline with a `//` comment where it helps, and update the
   appropriate `Documentation/*.md` file when the change affects documented
   behavior

## pitfalls

- **new files inside a target's source dir warn on every build.** swiftpm reports
  `found 1 file(s) which are unhandled; explicitly declare them as resources or exclude
  from the target`. for a test fixture (e.g. `Tests/WebUITests/orphan-class-baseline.txt`)
  declare it in the target's `resources: [.copy("…")]` and read it via `Bundle.module`
  (keep a package-root-relative fallback for runners that don't vend the bundle). a file
  placed *outside* every target dir — like `designer/url-payloads.json` — needs neither.
- **generated files** are auto-generated and live under `.build/` (gitignored):
  `Assets+Generated.swift` (the `WebUI` target's embedded assets), `IconLibrary.swift`
  (the `WebUICore` target's icon catalog), and `DesignTokens+Generated.swift`
  (the `WebUIDesignSystemCore` target's token vocabulary). to inspect one, run
  `swift build` first then look in
  `.build/plugins/outputs/no-webui/<Target>/destination/<Plugin>/<file>`.
  none is hand-edited.
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
- **smoke pins the interactive count** — the smoke gate asserts exactly 25
  `data-component-id` attributes on the smoke page (3 counter + 2 progress +
  1 echo + 1 column menu + 12 routed table controls + 6 routed chart bars). adding or removing
  an interactive component there means updating the expected count in
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
- **`@unchecked Sendable`** — retired for the lock layer: `EventRouter.State`,
  `ObserverList`, `AsyncSemaphore`, `LoginThrottle`, and the example state
  classes are Mutex-backed and now declare plain `Sendable`. `@unchecked` should
  still be avoided unless the class genuinely cannot prove Sendability; prefer
  `Synchronization.Mutex` with a `Sendable` payload so the lock is the
  synchronization mechanism and the type system sees real Sendability.
- **`#if DEBUG`** — avoid for security-relevant warnings. use unconditional
  `Logger.warning()` instead so production builds also see the warning.
- **`defer { txnAbort }` after `txnCommit`** — aborting a committed LMDB
  transaction crashes with SIGTRAP. not applicable here (no LMDB), but worth
  noting for future database work.

## related projects

- `swift-mcp` — MCP server framework for Swift (macros, Service Lifecycle)
- `rawdog` — lean binary encode/decode (alignment, endianness)

## shipped agent skills (deliverable)

This repo ships two Hermes agent skills and a `Makefile` installer that deploys
them into an active Hermes profile's skill library:

- `no-webui` (`./SKILL.md`) — the public-API consumer skill for composing web
  UIs in Swift with this framework.
- `webui-design-system` (`skills/webui-design-system/`) — the consumer-facing
  companion (design-system components, tokens/theming, interactivity, serving,
  verification, gotchas). Maintainer-only framework work is deliberately
  excluded and lives in this file + `Documentation/*`.

Install / remove both into the browser-dev profile (or `PROFILE=<name>`):

```bash
make install-skill                 # validate + install both (non-interactive)
make install-skill INTERACTIVE=1   # prompt for root/profile/category
make uninstall-skill               # remove both
make skill-info                    # show defaults / targets
```

overrides: `PROFILE`, `HERMES_ROOT`, `FORCE=1` (overwrite existing installs).
Skills are discovered at a fresh agent session, so a newly installed skill
appears in a new session, not the running one.
