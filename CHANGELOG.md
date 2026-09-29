# changelog

all notable changes to this project are documented here.

## [unreleased]

### developer experience

- `WebUIServer` now injects its router as the render context around `render()`
  (`RenderContext.$current.withValue`): handlers a page wires through
  `.onX`/`controlAttributes` register into the server's router directly, so
  hosts no longer juggle a page-local `EventRouter` alongside the server's (the
  classic two-router mismatch). a page that wraps its own context still wins
  (inner `withValue` takes precedence), so existing hosts are unaffected.
- engine: a click on an unwired interactive control (a `button`/`role=button`
  with no `data-component-id` in the path, outside a native `form[action]`)
  now logs a one-time console warning naming the element — the silent
  "nothing happens" failure gets a pointer at the cause.

### consumer experience

- showcase is now a **live** page: `WebUIShowcaseServer` wires a shared
  `ShowcaseState` through the server's router and the interactive demos
  round-trip for real — click counter (−/+/Reset with optimistic reset), form
  echo (submit → server echo), live preview (`onInput`), tab content switching
  (`WebUITabs.onSelect`), sortable/selectable/expandable table, pagination
  (page + rows-per-page), server-driven tree open/selection, and the
  dismissible alert/toast/modal close buttons (`me.remove()`). the static
  `designer/previews/showcase.html` artifact stays a compiled snapshot (no
  runtime).
- `WebUITabs` gains `onSelect: (me, tabID)` — a typed self-wiring tab-switch
  handler (additive parameter, `nil` default keeps the static render
  byte-identical; each tab emits `data-component-id="<id>-<tabID>"`).
- engine: when a page already carries a `WebUIEngineStatus` mirror
  (`data-webui-status`), the engine no longer injects its own duplicated
  `reconnecting…` chip — one truthful indicator instead of two.
- `Tests/WebUITests/ShowcaseWiringTests.swift` pins the showcase's wired
  surface (routing ids + exact handler count) so a wiring migration can never
  silently leave the showcase static again.
- `HTMLDocument.includeRuntime: false` now genuinely suppresses the client
  boot (no `webui-config` meta, no engine/chamber script tag) and switches
  the csp to the no-runtime shape (no `wasm-unsafe-eval`, no `ws:` in
  connect-src); an explicit `clientMode` still wins. the parameter had drifted
  inert during the engine-first flip and a loose `<script>` pin masked it —
  the pins are hardened and the static showcase artifact is script-free again.

### charts

- `RadarMark` and `RadialMark`: a closed polygon per series over shared axes, and
  a *stroked* gauge arc (track + value arc + centered percentage, clamped
  0...100). `chartAspectRatio` makes the square viewBox a gauge wants expressible.
- `AreaMark(...).areaGradient(_:)`: an area fill from a `<linearGradient>` whose id
  is derived from the gradient's own contents, so it is stable across renders and
  collision-free between charts sharing a page.
- css-only hover tips on bars, points, sectors and radar vertices (revealed by
  `:hover + .chart__tip` - no javascript, no new event), with the divergences
  documented in `Documentation/CHARTS.md`.
- **negative values render correctly**: bar edges are normalized (a negative datum
  used to collapse to a zero-height rect) and the bar domain always spans zero.
  charts also carry intrinsic `width`/`height` now - without them a `viewBox`-only
  svg fell back to the 300x150 replaced-element default and every chart rendered at
  ~0.47 scale, axis labels included.

- **chart text keeps its size**: the figure publishes the width it was laid out
  for (`--chart-w`), renders at it, may compress to 92% — 12px labels still paint
  11.04px — and pans below that. before this, in-svg text multiplied by the
  container's scale, so a 390px viewport painted 10px axis labels at **3.6px**.
  the plot is inline-size-contained (so the pan works in any container) and the
  figure declares its own width (a chart contributes no intrinsic width, so a
  content-sized container collapses to its text). chart text moves onto
  `--font-size-xs`.
- the figure's **accessible name is the chart's title** when one is set
  (`.chartAccessibilityLabel(_:)` still wins), instead of `Chart with N marks` —
  and the singular case reads `Chart with 1 mark`.
- the **inert scroll API is removed**: `ChartScrollAxes`,
  `ChartConfig.scrollAxes`, `ChartConfig.visibleDomain`, `.chartScrollableAxes(_:)`
  and `.chartXVisibleDomain(_:)` shipped with no reader anywhere (no renderer, no
  runtime, no css), so every call was already a no-op — see the note in
  `Documentation/STABILITY.md`. the replacement for the intent is the plot's pan
  behaviour or a declared design width via `.chartHeight` / `.chartAspectRatio`.
- `designer/chart-mobile-audit.mjs`: a gate over six viewports × two themes that
  asserts painted text ≥ 11px, the **visible fraction** of every plot, label
  collisions, tip reachability and page overflow (five assertions per slide,
  six from 390px up).
- the showcase charts section is a responsive gallery — `chartHeight(150)` plots
  in `Grid(columns: .custom("repeat(auto-fit, minmax(min(100%, 344px), 1fr))"))`
  tracks — so every chart is fully visible from a 390px viewport up, 1-up on a
  phone and 3-up at 1440px.

### data table

- `WebUITable.hiddenColumns` (server-owned column visibility), plus the client fix
  that made composite controls work at all: a click's `targetId` now resolves to
  the nearest id-bearing element *inside* the component, so a menu item reports
  itself instead of omitting the id - which had made the server answer nothing.

### blocks

- `WebUIBlocks` (library) and `WebUIBlocksServer`: seven standalone page scaffolds
  - dashboard, login, signup, four sidebar variants - plus a patterns block
  (carousel, menubar, questionnaire), served one per process with no showcase
  dependency. composition only: every class a block emits already exists in the
  sheet, and a pin proves it.

### direction

- `HTMLDocument`/`WebUIDocument` gain `dir:` (emitted on `<html>`, omitted when
  unset, invalid values dropped). the sheet's flow-relative rules are logical now
  (`margin-inline-*`, `padding-inline-*`, `border-inline-*`,
  `text-align: start|end`); what stays physical is the arrow/chevron geometry,
  documented and pinned by a ratchet.

### long tail

- `WebUICarousel` (css scroll-snap on a focusable track, so the arrow keys scroll
  it) and `WebUIMenubar` (panels open on hover and on `:focus-within`, so it is
  keyboard reachable) - both zero-js, divergences documented. a css-only
  split-pane was **scrapped**, with the probe recorded: a `flex: 1` pane cannot be
  resized by `resize`, and css cannot let a handle move a sibling.

### verification

- new gates: `designer/blocks-sweep.mjs` (every block, 320/768/1440, both themes,
  no-overflow and parts assertions) and `designer/rtl-audit.mjs` (both directions,
  both themes, with an ltr control). the pin that enumerates every class a block
  emits has now caught three pre-existing orphan classes - css emitted by shipped
  components with no rules in the sheet.

### the wasm monolith client is deleted

- `WebUIClientRuntime`, `WebUIClient` (and their test target), the `WebUIWasmPlugin`
  artifact carrier, the `wasm-client` plugin verb, the chamber/boot/worker assets and
  `WebUIBoot` are gone. **the engine is the client runtime**; wasm survives only as
  capability islands (`WebUIIslandCore`, `WebUIValidateIsland`, the `wasm-island`
  verb, `WebUIWasmTool`), which share the same toolchain and `WebUISharedCore` leaf.
- why: the chamber fetched and instantiated a 55 mb module (~12 mb brotli) on every
  app-mode page for work the ~37 kb engine does, and it could not render server
  views. `NEXT_ARCHITECTURE.md` records the measurement.
- `ClientBoot` survives, describing the engine boot only; the smoke preview's
  `WEBUI_BOOT=wasm` mode, its client routes and the demo pages are gone with the
  path. the six `WASM_*.md` design documents were deleted outright (git history
  keeps them). the consumer skill no longer promises a link-able client product.

### public surface

- **three dead public symbols removed** (measured: no non-comment reference
  outside their own declaration, no conformer, no renderer):
  - `AnyView` (`WebUICore`) — the framework's erasure idiom is `[any View]`, so
    the wrapper was both unused and misleading about the intended shape.
  - `UserStore` and `Authenticator` (`WebUIAuth`) — a never-implemented identity
    seam: nothing in the repo conformed to either, and no shipped API accepted
    them. `Credential` and `Identity` stay as the data vocabulary, and a host
    wires its own verifier directly (as `WebUIAuthExample` does).
  `Documentation/API.md` (three table rows) and `AUTH_SESSIONS.md` (the protocol
  sketch, plus a note on why no seam is shipped) were updated in the same
  commit. the frozen surface is untouched — none of the three was listed.
- `Documentation/STABILITY.md` now records **measured consumption** of the
  frozen surface: 9 frozen names have no library and no demo consumer (the
  `APISurfaceTests` pin is their only exerciser), and 16 showcase-rendered
  components sit *outside* the promise. the promise itself is unchanged; the
  mismatch is documented rather than implied, and every name is listed as a
  candidate for review at the next major.
- **`CSRFProtection.token(for:…)` no longer leaks the crypto dependency's error
  type.** it is public and `throws`, but an hmac failure propagated `RAW_hmac`'s
  error — a caller could not catch it without importing rawdog. the failure is
  now caught and rethrown as `CSRFError.signingFailed`, a case that was declared
  and documented but never actually thrown. a caller that previously matched the
  hmac error must match `CSRFError` instead; the success path is byte-identical.
  the cause is collapsed on purpose — no caller can act differently on which
  internal step failed.
- doc truth: `AUTH_SESSIONS.md`'s login flow named `PasswordAuthenticator` (no
  such type — now `PasswordVerifier`), and its entropy note described the
  `.signingFailed` throw before the code produced one. both corrected (the
  second by fixing the code, above).
- `Documentation/IMPLEMENTATION_PLAN.md` (688 lines; self-declared "historical
  plan") removed, matching the wasm-design-doc precedent — git history keeps it.
  its four inbound references (`Documentation/API.md`, `Documentation/README.md`,
  `README.md`, `Sources/WebUIAuth/WebUIAuth.swift`) were updated in the same
  commit.
- `CHANGELOG.md` itself carried a stray generator placeholder token in the
  wasm-deletion section (it had swallowed a word); removed.
- **the render path's additive surface** (the render-buffer arc: `S0`–`S4a`):
  `View` gains `render(into buffer: inout HTMLBuffer)` and `ViewModifier` gains
  `decorate(_:into:)`, both *defaulted* requirements — a conformer that
  implements only `render()` / `apply(to:)` keeps rendering byte-identically,
  which is what keeps this a minor. `HTMLBuffer` is a `public` **type** (a
  protocol requirement is implicitly as visible as its protocol, and the
  requirements name it) while **every member stays `package`**: this is the
  framework's own render path, and the members open with the 2.0 flip, when
  `render(into:)` becomes the requirement and `render()` a deprecated
  convenience. pinned by `APISurfaceTests.renderBufferAdditionsPin` and
  documented in `Documentation/API.md`'s View Protocol table. measured on the
  reference box (Debug, interleaved passes): page render ≈ -11% against the
  pre-arc tree, with byte-identity held on every page, every gate, and both
  platforms. the rest of the design-system migration was scoped, measured
  neutral, and deliberately deferred to the flip.

### server: linux + speed

- **the server runs on linux.** three apple-only dependencies were removed, each
  verified on a linux box rather than reasoned about: `CryptoKit` (the stylesheet
  content hash — now the framework's own `SHA256` over rawdog, digest
  byte-identical, so the content-addressed css url did not move), the
  `WebUICompression` C target (`compression.h` is apple's libcompression — and it
  backed `GzipEncoder`, which **no call site ever invoked**: `respond(gzip:)`
  accepted the flag and ignored it, so every page and asset shipped uncompressed
  while claiming gzip), and a missing `libm` link for the zero-dep leaf
  (`Double.rounded()` lowers to a `round` call, which no island product otherwise
  pulls in). the test target also needed `FoundationNetworking` and a guard for
  `URLSessionWebSocketTask`, neither of which exists in swift-corelibs-foundation.
- **class validation is 7.8× faster.** `HTMLClassValidator.classTokens` ran a
  swift regex over the whole rendered document — 30.7 ms of every 166 KB page.
  it is now a single-pass byte scanner at 3.9 ms, measured A/B on identical
  input. the orphan ratchet's guarantees are unchanged (all 816 tests, including
  the ratchet, still pass).
- **page latency on the reference box fell 40%** (p50 66.08 → 39.68 ms) and
  throughput rose 73% (15 → 26 req/s) — the render is the whole cost, and both
  figures track the validator's speedup. the page is byte-identical (166,167 B).
- transport: **keep-alive** replaces `Connection: close` (200/200 requests now
  reuse one socket instead of none), **tcp_nodelay** is set on accepted children
  (nio sets it for client channels only), `respond` writes the body into the
  channel's buffer in one copy instead of two, and the framework's own assets
  (320 KB css, engine, shell) are pre-encoded once at startup instead of per
  request. the read-idle reaper and the 256-connection admission gate are
  unchanged, so the bound on live connections still holds.
- `WebUIShowcaseServer` gains `--render-bench N` (an instrumented render profile:
  page with/without validation, a synthetic node tree, the id/escape/growth
  micro-paths, and a scanner A/B) and `--no-class-check`.
- profiles disproved three plausible micro-optimizations and one attempt:
  `nextComponentID` (mutex + string alloc) is under 0.5 µs, the `htmlEscape`
  guard under 3 µs, and `reserveCapacity` changes nothing for 2,850 appends. a
  utf-8 byte-scan rewrite of `htmlEscape` measured *slower* (4.15% of render cpu
  against 2.05%) and was reverted, with the result recorded in the code. the
  render is flat and arc/string-bound: no symbol exceeds 4.5%, and the remaining
  cost is ~5.7 µs per node — the case for the buffer-based v2 render path.

## [1.0.0] — stability epoch (2026-09-20)

### stability epoch

- `Documentation/STABILITY.md` — semantic-versioning policy, the frozen
  consumer surface (enforced by `Tests/WebUITests/APISurfaceTests.swift`:
  compile-time initializer pins + render-contract assertions), deprecation
  rule (one full minor), and the honest known limitations (session caps are
  deployment policy; the wasm client runtime does not mirror the JS
  runtime's keyboard affordances; modal focus trapping pending; charts
  youngest).
- `WebUIAuthExample`: per-session interactive state containers (`SessionStates`
  — bounded, purged on logout/expiry by the sweep); ceremony test proving two
  authenticated sessions get independent state.
- modal `Escape`-to-dismiss in `webui-runtime.js` — the dismiss control is
  activated through the normal routed-click path (verified against a live
  server; no console errors).
- wasm trajectory status corrected: phases 0–6 executed in `dev` (P3/P4/P5
  landed), phase 6 (size diet + per-SKU distribution) declared post-1.0.
- docs made application-type agnostic and the webui-design-system skill
  dropped its chat-streaming knowledge at the owner's request.

### added

- icon catalog tripled: **618 glyphs** (was 206). the 64 remaining
  non-brand Feather icons plus a curated 348 from Lucide (ISC — Feather's
  successor, same 24-grid / 2-stroke line language; 19 further brand
  logos and 3 icons whose compact arc data trips the bounds tokenizer are
  excluded). manifest `_meta`
  records both licenses; titles follow the existing `Name Title` convention
  and tags combine name words with the upstream tag list. the full preview
  was vision-passed in both themes across all 10 categories.
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
  the full flag surface and `__Host-` rules, `InMemoryAuthSessionStore` and
  the `AuthSessionStore` protocol, Argon2id password verification with
  dummy-hash equalization, `AuthContext` `@TaskLocal`.
- `WebUIAuthExample` — login-gated interactive demo on :9091 (`admin` /
  `password`): runtime-free native-POST login page, CSRF-protected POST
  logout, origin-checked WebSocket upgrade, per-event session-liveness
  enforcement (post-logout sockets are redirected and closed).
- `constantTimeEquals` in the core (`Sources/WebUI/ConstantTime.swift`);
  `CSRFProtection.validate` switched to it.

### removed

- the QuickLMDB-backed `LMDBAuthSessionStore` and its tests. `WebUIAuth`
  session storage is protocol-driven (`AuthSessionStore` + in-memory store);
  a persistent store is backend-provided — no database dependency remains in
  the package.

### fixed

- gate integrity: `browser-smoke` self-resolves the swiftly-hosted wasm toolchain
  (invoking `~/.swiftly/bin/swift` directly — order-independent, unlike
  `source env.sh`) so its client-mode probes run instead of silently
  self-skipping; a registered sdk whose build fails is now a gate failure, and
  sdk-less runs label their skips in the summary instead of claiming a full pass.
- gate identity: the smoke/fullstack/browser gates mint a per-run nonce
  (`WEBUI_SMOKE_NONCE`) that the server reflects on every response
  (`X-WebUI-Smoke-Nonce`); the readiness probe requires it, so a stale or
  foreign process holding the port fails the gate loudly instead of
  false-passing. the browser gate also hard-kills its spawned server on every
  exit path so a failed or truncated run cannot orphan it on :9123.
- asset plugin now fails the build when `designer/assets/` is missing or empty
  instead of warning and letting a stale/empty embed ship.
- render-token replay gate: a token this session minted but LRU-evicted now
  resolves through a bounded forward chain and the page is handed the live
  token as an in-place `token` refresh over its existing socket — no reload,
  no logout. a genuinely foreign/forged token still fails resolution (the
  cross-session gate stays intact); a reload is now only the fallback for a
  valid session whose router entries have all been swept.
- the wasm chamber now runs the same parse-and-strip fragment sanitizer as the
  server runtime on every fragment write (`applyUpdates`/`setInnerHTML`),
  closing the client-path sanitization gap.
- dark-theme accent-text contrast and the designer-preview layout.
- page shell + form-control theming across the design system (polish pass).
- the default `title` was `"WebUI UI"` (a stutter) in both `HTMLDocument` and
  `WebUIDocument`; it is now `"WebUI"`, so a document that omits `title` no
  longer ships a doubled brand in the tab. the showcase's own title/heading
  ("WebUI UI Showcase") is corrected to "WebUI Showcase".
- documents now emit a branded tab icon: a 32 px accent-tile/window glyph
  inlined as a `data:` uri in the head (the framework csp already permits
  `img-src data:`), so a host that serves no `/favicon.ico` still gets a
  branded tab and the browser no longer logs a favicon 404 on page load.
  `HTMLDocument(icon:)` accepts a custom `<link>` or an empty string to
  suppress.
- `WebUIDocument` gains `rawStyles:` — page-scoped styles appended after the
  design sheet, used by the login page, whose `.login`/`.login__card`/
  `.login__form` classes had no rules and rendered as an ungrouped form row
  at the top-left of the page. the login screen is now a centered raised card
  with a full-width form column.
- the auth example's throttled (`429`) and not-found (`404`) text responses
  now send `Content-Type: text/plain; charset=utf-8`; without it the browser
  mis-decoded the em dash and painted a bare mojibake page.
- `respond404` in the example and smoke servers returned http 200 with a
  "not found" body; it now returns `404`.

### changed

- `WebUIComposer` sends on **Enter** (Shift+Enter for a newline): a plain
  Enter inside a `form.composer` textarea now submits the composer (via
  `form.requestSubmit()`, the same path as the send button) instead of
  inserting a newline. runtime behavior only — no markup/CSS change; pinned
  by `runtimeComposerEnterSubmits`.
- client transport wiring: the chamber opens a WebSocket when the boot config
  declares a `wsUrl`, forwards events through it (echoing the render token),
  and routes inbound server `update`/`redirect`/`reload` frames — `update`
  frames advance the sync ledger via the new `webui_apply_seq` export before
  applying their (sanitized) fragments. `wsSend` with no open transport
  now warns once instead of silently dropping. the local demos stay silent
  (`wsSent === 0`): they ship no `wsUrl`.

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
- the fragment sanitizer now parses each patch into a detached DOM subtree
  and strips scripts, `on*` handlers, and unsafe URL attributes on the real
  nodes — the parser itself resolves character references and quoting, so
  entity-obfuscated, unquoted, and whitespace-obfuscated `javascript:` URLs
  are all neutralized (the previously-bypassing `&Tab;`/`&NewLine;`/unquoted/
  space-less-handler payloads are now blocked).
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
- fragment sanitizer (`sanitizeFragment`) — parses each patch into a detached
  DOM subtree and strips `<script>` tags, event handler attributes, and
  unsafe URL attributes before insertion.
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
- XSS via WebSocket fragment injection — the string-regex sanitizer passes
  were replaced by a DOM-based sanitizer that also blocks
  `&Tab;`/`&NewLine;`-entity-obfuscated schemes, unquoted URL values, and
  space-less `on*` attributes.
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