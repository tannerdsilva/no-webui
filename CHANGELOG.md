# changelog

all notable changes to this project are documented here.

## [unreleased]

### added

- interactive `WebUITable` — server-driven sort / select / expand: clickable
  headers with `aria-sort` + `.sort` affordance, select-all / per-row
  checkboxes (`aria-checked="mixed"` for partial selection), per-row detail
  expansion with `.table__detail-row`. stable control ids
  (`{id}-sort-{col}`, `{id}-select-{rowId}`, `{id}-expand-{rowId}`); the smoke
  server's table card is the reference implementation.
- companion primitives: `WebUIStat` (KPI card with trend + normalized inline-svg
  sparkline), `WebUIPagination` (windowed list with `…` ellipsis, stable
  control ids, `aria-current`), `WebUITimeline` (vertical/horizontal, four
  statuses), `WebUITree` (recursive nodes, CSS open/close, server-driven
  selection, stable row ids), `WebUIBreadcrumb` (ellipsis collapse, sanitized
  hrefs), `WebUIDescriptionList` (`<dl class="list--desc">`).
- table feature set: `.table-wrap` scroll container (sticky thead), per-column
  `alignments` (`.num` numeric-column class), `footer` (`<tfoot>`),
  `emptyState` (colspan row), and `striped` / `hoverable` / `compact` /
  `responsive` variants.
- `WebUIAuth` foundation (M0): identity model, `SessionToken`
  (SecureRandom-only, SHA-256 hashed at rest), `HTTPCookie` parse/build with
  the full flag surface and `__Host-` rules, `InMemoryAuthSessionStore` +
  `LMDBAuthSessionStore`, Argon2id password verification with dummy-hash
  equalization, `AuthContext` `@TaskLocal`.
- `WebUIAuthExample` — login-gated interactive demo on :9091 (`admin` /
  `password`): runtime-free native-POST login page, CSRF-protected POST
  logout, origin-checked WebSocket upgrade, per-event session-liveness
  enforcement (post-logout sockets are redirected and closed).
- `constantTimeEquals` in the core (`Sources/WebUI/ConstantTime.swift`);
  `CSRFProtection.validate` switched to it.

### fixed

- dark-theme accent-text contrast and the designer-preview layout.
- page shell + form-control theming across the design system (polish pass).

### changed

- icon stroke style tightened: `WebUIIcon` / `WebUIIconCustom` / the preview
  generator now emit `stroke-linecap="butt"` + `stroke-linejoin="miter"`
  (flat stroke ends, crisp corners) instead of the Feather round
  treatment — geometry untouched. zero-length dot markers (`alert-circle`,
  `info`, `list`, the faces, …) carry an explicit per-element
  `stroke-linecap="round"` in the manifest so they survive the butt cap.
  component glyphs (table sort/expand arrows, stat trend arrows) and the
  select caret match the new style; data-ink strokes (chart lines) stay
  round.
- 398 tests / 35 suites (was 320 / 22) once the interactive table, companion
  primitives, and auth suites landed.

### changed

- `CommonCrypto` and `SecRandomCopyBytes` are replaced by the official rawdog
  crypto suite (`RAW_sha256` + `RAW_hmac`, v21+) plus a thin `/dev/urandom`
  reader on linux and `SecRandomCopyBytes` on apple for entropy. the rfc 4231
  hmac-sha256 vectors are pinned in `CryptoTests` and pass byte-identically on
  both platforms.
- linux support: the framework and its plugins build and pass the full suite
  on ubuntu 24.04 (swift 6.3.3). the plugins gained conditional
  `FoundationNetworking` (linux) imports for `URLSession`, a `Glibc`/`Darwin`
  guard for the socket-based probe, and dropped the
  `HTTPURLResponse.statusCode` readiness cast in favor of an any-body GET
  probe; `WebUIProbePlugin` shims glibc's typed `SOCK_STREAM` enum.
- the crypto suites added test coverage on top of the earlier 307 / 20 total
  (the current unreleased totals are 398 tests / 35 suites — see above).


### docs

- `DESIGN_SYSTEM.md` component reference rebuilt against the shipped css and
  `WebUIComponents` sources: removed the fictional `WebUIToggle`,
  `WebUIDropdown`, `WebUISelect`, and `WebUITextArea` sections, corrected every
  initializer signature and BEM class (`.button--full`, not
  `.button--full-width`; `modal__title`, `chip__remove`, `empty-state__icon`,
  `spinner__ring`, `tooltip__arrow`, …), and added the previously undocumented
  `WebUISkeleton`, `WebUIChip`, `WebUIEmptyState`, and `WebUISpinner` sections.

### changed

- `WebUIAssetPlugin` migrated to the URL-based PackagePlugin API
  (`directoryURL`, `pluginWorkDirectoryURL`, `URL` input/output files) — the
  package now compiles warning-free end to end.
- two test-target warnings fixed (`String(describing:)` for the optional
  `Mirror` label comparison; `var` → `let` for unmutated `RenderContext`
  locals).
- docc: confirmed deliberately out of scope — the package ships no `.docc`
  catalog and no docc plugin (`swift package generate-documentation` is not a
  configured subcommand); documentation lives in `Documentation/*.md`. the
  swift-audit docc check reports a clean package (no catalog, no warnings).


### added

- `RuntimeConfig` — the js runtime tuning knobs (debounce, reconnect, settle,
  log level, `wsUrl`) are now reachable from swift via `HTMLDocument` /
  `WebUIDocument`'s new `runtimeConfig:` parameter. a non-empty config emits
  `WebUIRuntime.init({...})` with only set keys; the default bootstrap stays
  byte-identical.
- `onFocusIn` / `onFocusOut` modifiers, matching the `HTMLEvent` cases that
  already existed without a delivery path.
- `.attribute(_ key:, _ value:)` — generic attribute modifier (and the
  `data-prevent-enter="false"` escape hatch).
- `FontWeight` and `TextAlignment` typed enums with `.custom(_:)` escape
  hatches, added as overloads — string call sites still compile.
- `minifyCSS(_:)` — render-time css minification for shipped pages.
- the core `LayoutStyles` now ships the `.zstack > *` overlap rule, making
  `ZStack` self-sufficient without the design-system stylesheet.
- `data-dismiss` / `data-remove` markers on dismissible alert/toast/modal and
  removable chip close buttons.

### changed

- `sanitizeURL()` (and the js router's `isSafeUrl`) strip c0 controls and
  ascii whitespace before the scheme check, matching the browser's URL parser
  — padded and obfuscated `javascript:` URLs are now blocked on both sides.
- every `id` / `class` / `name` / `for` / `data-status` / `method` / icon
  emission site across the core primitives, semantic containers, and
  design-system components is now html-escaped.
- `sanitizeFragmentHTML()` decodes numeric and named character references
  before stripping, so entity-encoded `javascript:` URLs are neutralized.
- focus/blur events are delivered via the bubbling `focusin` / `focusout` and
  normalized to the declared event name — `.onFocus` and `.onBlur` now
  actually fire.
- click events carry the clicked element's `targetId` and `targetClass`, so a
  container handler can disambiguate without per-button wiring.
- `keydown` Enter no longer preventDefaults inside `TEXTAREA` /
  `contentEditable`.
- `GridColumns.fixed(n)` emits grid-safe `repeat(n, minmax(0, 1fr))` and is
  distinct from `.fraction(n)`; `.autoFill(n)` / `.autoFit(n)` treat n as the
  minimum track size in px.
- `markdownToHTML(_:)` is a real minimal safe subset (atx headings, lists,
  bold/emphasis/code/links, escaped input) instead of a `<p>` stub.
- `highlightCode(_:language:)` remains escape-only and is now documented
  honestly as such.
- shipped pages minify the embedded css at render time (no comments, no blank
  lines) — smaller payloads, and the no-comments-in-shipped-assets law holds
  for css on the wire while the designer file keeps its notes.
- 307 tests / 20 suites (was 264 / 11).

### fixed

- `javascript:` URL execution via control-character obfuscation (leading
  whitespace and embedded tab/newline) in `sanitizeURL` and the js router —
  verified in a live browser.
- attribute injection via `id` / `class` / `name` / `data-status` / `method`
  on primitives and components.
- `.onFocus` / `.onBlur` never firing, because the runtime listened for
  non-bubbling events on `document`.
- entity-encoded `javascript:` fragments slipping past the client sanitizer.
- `Enter` in `TEXTAREA` being swallowed when a keydown handler was present.
- unpaired markdown delimiters emitting unbalanced tags (now render literal).

### added

- command plugins for the whole project tooling: `serve` (hosts the
  WebUISmokeTest server on :9123, run with `--disable-sandbox`), `smoke`
  (self-contained asset-integrity + page-structure gate), `fullstack-smoke`
  (self-contained live-WebSocket gate), `probe` (connect-based port check).
- `Documentation/ASSEMBLY.md` — the build/verification stage map.
- `.onOptimisticClick(predict:perform:)` — the optimistic/pending path. the
  client applies a render-time prediction to the DOM in the same turn as the
  click, auto-confirms when the authoritative update lands, and rolls back to
  last-known-good after `optimisticSettleMs` (default 5s) if nothing confirms.
  scoped to value-independent/idempotent transitions (e.g. reset); predictions
  are a render-time snapshot, so stateful increments are not optimistic yet.
- token-backed modifiers: `SpaceToken`/`ColorToken` enums plus
  `.padding(.four)` and `.foregroundColor(.primary)` that emit
  `var(--space-4)` / `var(--color-primary-500)` instead of raw px/hex.
- fluent event modifiers for the full delivered event set:
  `onKeyDown`/`onKeyUp`/`onKeyPress`/`onMouseDown`/`onMouseUp`/`onMouseOver`/
  `onMouseOut`; runtime `EVENT_TYPES` extended to match (keydown/keyup/keypress
  share key data; mouse events send `{}`).
- `EventRouter.handlerCount`.
- live interactive `WebUIExample` on :9090 — the example now upgrades `/ws`
  and round-trips counter + echo end to end (previously static-only).

### changed

- `WebUITheme` mirror retired: `design-system.css` is the single token source
  of truth. `WebUIDocument` ships layout styles + the nexus css only; the
  stale teal block is gone (~4KB/page). tests that pinned the mirror now pin
  the shipped css (nexus values, z-index scale, dark theme).
- `EventRouter.handle` logs a missing handler at `.warning` (was `.debug`).
- runtime `saveInputState`/`restoreInputState` now also capture/restore scroll
  position for scrollable fragment elements and re-focus non-form
  `[tabindex]`-focused elements across a patch.
- runtime filters delegated events by the element's declared `data-event` —
  a click-only component no longer receives `mouseover`/`mousedown`/
  `mouseup` (previously a real click fired all four and dispatched the same
  handler 4x).
- runtime `Router` no longer references an out-of-scope `log` — navigation
  and redirect are wired through a `createRouter(log)` factory so a server
  `{type:"redirect"}` actually redirects. smoke server gained a reserved
  `redirect-test` component path; `fullstack-smoke` asserts the redirect frame.
- `Documentation/GETTING_STARTED.md` rewritten — §6 decodes `WSIncoming` and
  wraps `WSOutgoing.update`, §7 shows only the auto-generated
  `data-component-id` pattern, plus a three-id concepts table; the manual
  `context.register` path is documented as an escape hatch.
- `Documentation/DESIGN_SYSTEM.md` token reference rewritten from the shipped
  css with correct nexus names/values, dark theme, and z-index scale.
- designer gate workflow is now single plugin commands; the designer shell
  scripts (`sync.sh`, `demo.sh`, `smoke.sh`, `fullstack-smoke.sh`,
  `browser-smoke.sh`) were removed.
- `showcase` now declares `writeToPackageDirectory` and writes
  `designer/previews/showcase.html` directly
  (`swift package plugin showcase --allow-writing-to-package-directory`).
- the browser layout gate runs as a self-contained node command
  (`node designer/browser-smoke.mjs`) — headless Chromium cannot run inside
  the plugin sandbox.

### fixed

- `Router` out-of-scope `log` made server-sent redirects silently no-op.
- optimistically-patched fragments that the server never confirms now roll
  back to last-known-good instead of sticking.
- scroll position lost when a fragment patch replaced a scrollable element.

- removed the stale `WebUIDesignerSync` plugin reference from the README.

- build tool plugin (`WebUIAssetPlugin`) that auto-generates `Assets+Generated.swift`
  from CSS and JS assets during `swift build`. no more manual `swift run WebUIAssetTool`.
- `CSRFProtection` — stateless HMAC-SHA256 token generation and validation.
  `Form` accepts optional `csrfToken:` parameter.
- `ObserverList.maxObservers` cap (default 100) to prevent unbounded growth.
- `EventRouter.maxHandlers` cap (default 10,000) to prevent unbounded growth.
- `sanitizeURL()` — blocks `javascript:`, `data:`, `vbscript:` protocols.
  applied to `Link`, `Image`, `Form`.
- `sanitizeFragmentHTML()` — strips `<script>` tags, event handler attributes,
  and `javascript:` URLs before DOM insertion.
- auto-generated CSP with per-document nonces. all inline `<script>` tags
  include `nonce="..."`.
- prototype pollution protection — `State.set()` rejects `__proto__`,
  `constructor`, `prototype` keys.
- `EventHandlerModifier` now uses unconditional `Logger.warning()` instead of
  `#if DEBUG` print for missing RenderContext.
- `injectAttributes` now passes closing tags through unchanged instead of
  wrapping in `<span>`.
- JS runtime now preserves keyboard focus (and caret) when a re-rendered
  fragment contains the control the user is editing.
- comprehensive `Documentation/` directory with 7 markdown files covering
  architecture, getting started, API reference, JS runtime, design system,
  and layouts.
- `AGENTS.md` and `CONTRIBUTING.md` for project guidance.

### changed

- JS runtime input debouncing now uses trailing + max-wait semantics: a burst
  of keystrokes on a field coalesces into a single well-timed send instead of
  firing a leading event per keystroke. `change`, `blur`, and `submit` send
  immediately so no input is lost.
- JS runtime reconnect now applies 0.5–1.5× jitter to the exponential backoff
  delay so clients do not reconnect in lockstep.
- full visual redesign of the design system to the "nexus" language:
  indigo primary (`#6366f1` family, replaces the teal accent), cool
  neutrals, soft 6px radii (`--radius-button`/`--radius-input` no longer
  square), quieter shadows, and an all-sans type treatment (display serif
  retired — `--font-display` now mirrors `--font-sans`).
  dark mode is near-black-first: `--color-bg` `#060910`, raised surfaces
  `#0c111c`, solid primary button on `#4f46e5` with white ink.
  all control types unchanged; `designer/previews/designer-preview.html`
  palette swatches now read live tokens in both themes.
- `design-system.css` moved from `WebUIDesignSystem/Assets/` to
  `WebUI/Assets/` (co-located with JS runtime for plugin access).
- `Assets+Generated.swift` removed from source tree — now generated by plugin
  and gitignored.
- `EventRouter.State` thread safety — replaced `@unchecked Sendable` with
  `NSLock`-guarded access.
- `htmlEscape()` applied to event names and attribute keys/values in modifiers.
- `swift-docc-plugin` dependency removed (no DocC catalog exists).
- comment policy: inline `///` doc comments and `//` line comments are allowed
  in swift source again (the earlier strip within this cycle is superseded).
  the no-comment rule now applies only to the distributed web assets — the
  html, css, and js shipped to clients, which embed verbatim — those stay
  comment-free. framework prose documentation still lives in
  `Documentation/*.md`.

### fixed

- JS runtime keepalive: a pong no longer leaves a pending reconnect timer
  armed, which could have triggered a spurious reconnect on a healthy
  connection.
- JS runtime multi-select form fields now send a comma-joined string instead
  of an array (the server's `EventData.data` is `[String: String]`, so an
  array would have failed to decode).
- JS runtime `destroy()` now removes the `popstate` listener it registered.
- prototype pollution via `State.set("__proto__.polluted", value)`.
- XSS via WebSocket fragment injection (`sanitizeFragmentHTML`).
- `javascript:` URL execution in `Link.href`, `Image.src`, `Form.action`.
- attribute injection via `EventHandlerModifier` and `HTMLAttribute`.
- CSP bypass — no default CSP and `'unsafe-inline'` required.
- silent handler dropping — `EventHandlerModifier` now warns in all build
  configurations.
- malformed HTML from `injectAttributes` on closing tags.

## [7.1.0] — 2025

### added

- `no-webui_pthread` made public.
- revised rawdog requirements.

### changed

- general improvements to `no-webui_ip` and other tooling.
- better support for Swift 6.2.
- `size_t` changed to `Int` throughout.

## [7.0.0] — 2025

### added

- `WebUI` — SwiftUI-for-web framework.
- `WebUIDesignSystem` — WebUI design system with 110 CSS tokens and 16 components.
- `WebUIExample` — HTTP/WebSocket example server.
- comprehensive smoke test suite (216+ tests).

### changed

- `no-webui_ip` revisions for better access to system address translation functions.
- `no-webui_fifo` fixes and cleanup.

## [6.x] — 2024-2025

earlier versions — core library development. IP addressing, futures, FIFO,
pthread wrappers, async streams, scheduling service.