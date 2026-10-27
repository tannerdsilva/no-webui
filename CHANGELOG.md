# changelog

all notable changes to this project are documented here.

## [unreleased] — application state and the multi-tenant host

### added

- **`WebUIState`** — a page as a pure function of state. `Store<State>`
  (`final class` + `Mutex`, synchronously readable because render cannot
  `await`), `StatefulPage` (`initialState()` + `body(_:)`),
  `StatefulPageSession` (`patch(in:)` → `PagePatch`), `SessionStores` (one
  store per session, idle-only eviction), `PageSubscription`, and the
  store-aware handler sugars `.onClick(binding)` / `.onSubmit(binding)` — a
  handler mutates and returns nothing, so application code authors no html.
- **`WebUIHost`** — the multi-tenant composition point, and the only target
  that knows `WebUIServer` + `WebUIAuth` + `WebUIState` together (the absent
  `WebUIServer` → `WebUIAuth` edge is the compile-time proof identity is not
  the transport's job). `PrincipalResolver` / `CookieSessionResolver`,
  `PageCatalog` (`StaticCatalog`, `AuthenticatedCatalog`), `SessionRouterTable`
  (`RouterTable`: per-session render window + forward chain, so an evicted page
  refreshes in place), `RevocationBus` (`SocketRevocationBus`: logout closes
  the live socket), `IdentityDirectory`, `SessionRevocation`, and the
  `AuthenticatedHost` façade (`Responder` + `dispatch` + `signOut`).

### changed

- **`WebUIAuthExample` rewritten onto the two new products: 1,183 → 741
  lines** (432 app + 309 listener; the listener is the seam below). the hand-rolled `RouterRegistry`, `AuthConnectionRegistry`,
  `SessionStates`, `AuthDemoState` and the `counterValueHTML`-style string
  fragments are deleted; the dashboard is a `StatefulPage` whose controls are
  mutations, sessions route through `RouterTable`, logout tears down through
  `SocketRevocationBus`, and per-session state lives in `SessionStores`.
  the remaining listener is the seam `WebUIServer` does not expose (see
  `Documentation/ARCHITECTURE.md`, "what these two do not yet carry").
- `swift test`: **1,702 tests in 9 runs** (was 1,406 in the docs, 1,571 in
  `AGENTS.md`); frozen surface re-measured at **5,040 symbols across 11
  modules**. the showcase byte pin is unchanged at 168,671 bytes.

## [2.0.0] — the typed web (2026-10-10)

### breaking changes

a 1.x host migrating to 2.0 breaks in four places, and every one of them is
spelled row by row in `Documentation/MIGRATION_2_0.md` (five wave tables, 58
rows, every symbol grep-verified against the tree):

- **`View.render()` is no longer the protocol requirement.** since the wave-2
  flip, a `View` declares `func render(into buffer: inout HTMLBuffer)` and
  nothing else; `render() -> String` survives only as a deprecated *default* —
  it is `BufferRendering.markup.html`. the two string materializers the 1.x
  buffer path once offered were **deleted**, not deprecated (see the typed
  markup section below). a 1.x view
  that implements only `render()` does **not** satisfy the protocol — it does
  not compile against 2.0. keep the body, change the shape: `return X` becomes
  `buffer.append(X)`. `HTMLBuffer` itself is a public type; `init`, `append`,
  `appendEscaped`, `appendBytes`, `beginElement`, `endOpenTag`,
  `endElement`, `voidElement`, `addAttribute`, `addAttributeValue`,
  `byteCount`, `hasPendingAttributes` and `bytes` are the public members, and
  the modifier plumbing (`mark`, `takePendingAttributes`, `wrapSpan`,
  `settlePendingAttributes`, `finish`) stays package.
- **`.class(_:)` merges; it no longer replaces.** in 1.x a `.class("mine")`
  wiped the element's own classes; in 2.0 the content's classes survive, in
  call order, duplicates folded — `appendClassList` in `WebUISharedCore` is
  the one merge, and both merge passes route through it. a page that relied
  on replacement to *remove* a framework class loses that ability, and there
  is no replace escape: the plan's replace-classes escape was never
  implemented — no such modifier exists anywhere in the tree (0 hits).
  removing a framework class is now done
  host-side through the cascade — unlayered host css outranks the layered
  framework sheet (wave 5, below). the byte gate did not move because no
  in-repo page chained `.class()` onto a classed element; the merge is proven
  by `AttributeMergeTests` (37 green).
- **the slot vocabulary moved out of the components.** the 15 nested `Size`
  enums became one `ControlSize`; `Variant` became `Appearance` on
  `WebUIButton`/`WebUITag`/`WebUIAccordion` (renamed, not split: their
  classes conflict, so a two-axis API would type-check and lie) and `tone:
  Tone` on the seven tone components; `WebUICard`'s fused `Variant` genuinely
  split into `elevation: Elevation?` plus the typed flags `interactive:`,
  `horizontal:`, `hover:`, `compact:`, `disabled:`; the state families became
  `ValidationState`/`LoadState`/`EditState`/`StepStatus`; and the stringly
  slots — `WebUIGantt.Bar.state`, `WebUIJsonTree.Node.type`,
  `WebUIDiff.Line.kind`, `WebUITerminal.Line.kind`, `WebUIDonut.Slice.color`
  — became typed enums (`GanttBarState`, `JsonNodeType`, `DiffLineKind`,
  `TerminalLineKind`, `ChartColorSlot`). every 1.x spelling survives as a
  deprecated alias or forwarding initializer that emits its old bytes
  (`DeprecatedVocabularyTests` calls all 56 of them), so a 1.x host migrates
  on the deprecation schedule below, not all at once.
- **the server's render-closure inits are deprecated.** the 2.0 way to stand
  up a server is `WebUIServer(router:config:logger:)` with a typed `Router`.
  the deprecated pair — each marked `build a Router and use
  init(router:config:logger:)` — is `init(render:router:config:logger:)` and
  `init(requestRender:router:config:logger:)`. the direction is load-bearing:
  the router init is the *new* one (the plan's sketch once described it as
  deprecated — that falsehood is corrected, with the other two, in
  `Documentation/MIGRATION_2_0.md`). a path-dependent page is a
  `Route.page` that reads `request.path`.

### the semantic vocabulary (w1)

- `Sources/WebUIDesignSystemCore/Vocabulary.swift` declares all 18 semantic
  slots as top-level types, and the rule is now *the raw value is the
  semantic token* — each component builds its own class name from the shared
  type at render, so the emitted bytes for `sm`/`md`/`lg` are exactly what
  1.x emitted. the wave-start measurement is why this existed at all: 15
  nested `Size`, 13 nested `Variant`, 5 `State`, 3 `Status`, 2 `Side`, 2
  `Edge`, and `Brand` declared twice with different raw value sets — no
  generic bearer could name a concept with 15 spellings.
  `SlotBearing.swift` provides the bearer protocols
  (`SizeBearing`/`ToneBearing`/`ElevationBearing`), one conformance line per
  measured bearer.
- **the migration was byte-gated at every step.** `plugin smoke` (19/0)
  pinned the served bytes throughout; the per-component `classFor(_:)` maps
  were audited by a generator that refuses to write unless every mapping
  equals the original raw value; and `SizeConsolidationTests`/
  `VariantSplitTests`/`StateFamilyTests`/`DuplicateTypeTests`/
  `TypedSlotTests`/`SlotInvariantTests` assert old → new → bytes for every
  case. the discipline surfaced the shapes that made this a migration and not
  a rename: `WebUIKbd` and `WebUICircularProgress` named their cases
  `small`/`medium`/`large` (kept as deprecated static aliases on
  `ControlSize`); `WebUIStat`'s `md` is the bare `stat` class; eight
  components use an empty-string `md` with a leading-space `sm`/`lg`; and
  `WebUIBanner.danger` has always emitted `banner--error` — the mapping is
  built from each enum's own raw values, never from case names. the suites
  also caught two real bugs the byte gate could not see: a name-keyed map
  that silently gave the circular progress its `xl` class for all four sizes,
  and the legitimate `md = ""` case read as falsy and substituted `xl`.
- the seven tone components take `tone: Tone` (the vocabulary gained
  `secondary` as the brand position the sheet already treated as a peer), the
  exact-match shapes took `shape: SkeletonShape` and
  `position: SlidePosition`, the duplicates merged (`Side` →
  `BubbleSide`/`Placement`, `Edge` → `DrawerEdge`/`PanelEdge`, two `Brand`s →
  one), and the stringly slots were typed **from the sheet, not from the
  plan's case lists** — their cases are the rules the sheet actually ships.
  the donut is the wave's one intended byte change: `WebUIDonut.Slice.color`
  took raw css (`#6366f1`) and now names the sheet's own palette
  (`ChartColorSlot` → `--color-chart-1…8`).
- wave-1 gate: **1172 tests / 0 issues, exit 0** (1125 at wave start, +47);
  smoke 19/0; blocks-sweep 107/0; rtl-audit 54/0.

### the protocol stack and typed escape hatches (w2)

- `View` keeps carrying only what every view must meet, and the wave made
  that a compile-time invariant: the capability protocols `Interactive`,
  `Identified`, `StreamingContent`, `AsyncContent`, `Recoverable`
  (`Capabilities.swift`) all live in `WebUICore` with defaults, so conforming
  is a one-word change — `CapabilityProtocolTests` stops compiling the day a
  requirement lands on `View`. the real conformers arrived with the
  capabilities themselves (streaming, the event deck, error boundaries).
- **`.class(_:)` merges** — the semantic change is in the breaking list
  above; its typed spellings are `ClassName`, `classes(_:)`, `addClass(_:)`.
- the escape hatches are typed and explicit. `UnsafeMarkup` has **no public
  initializer** — `.trusted(_:)` is the only way in, one grep-able act that
  names the exact line that took responsibility for unverified bytes — and
  `Raw` takes it as its primary initializer, with the `String` initializer
  deprecated as a one-word-fix path. the `<head>` got the same treatment:
  `HeadContent`/`HeadContentBuilder`/`LinkRelation` are typed nodes (meta,
  og, jsonld, link, script), urls sanitized (an unusable `og:image` or
  `href` is dropped rather than emitted empty), and scripts stay typed until
  render so the document's **nonce cannot be forgotten** — including on
  inline JSON-LD, which escapes `</` to `<\/` so a payload containing
  `</script>` cannot close the element it lives in.
- `Directionality` lives in `WebUICore` beside `Raw` (the design system
  re-exports it as a typealias) so the document can name it without importing
  the design system.
- `HTMLBuffer` opened as a consumer type and the `render()` →
  `render(into:)` flip landed (breaking list above): every `View` in the tree
  declares `render(into:)` now, and the only `render() -> String`
  declarations left are the deprecated default plus the two attribute-render
  helpers on `AriaRole`/`Aria` — neither of those is a `View` renderer.
- wave-2 gate: **1195 tests / 0 issues, exit 0**; smoke 19/0; browser-smoke
  46/0; blocks-sweep 107/0; rtl-audit 54/0. the typed view-tree spike (w2.5)
  was measured and decided — recorded in `Documentation/DESIGN_NOTES.md`, not
  shipped: containers migrate one per task, each behind the byte gate.

### typed markup — markup, not render() (w6/w7)

- **`BufferRendering` is the one materializer.** a public protocol with
  `public var markup: UnsafeMarkup` (`Sources/WebUICore/BufferRendering.swift`),
  and `View` **refines** it — so `.markup` works on any view *and* on
  `HTMLDocument`, `WebUIDocument` and `CSSStylesheet` (a document is not a view,
  but it sings the same door). `markup` became public so a host has a non-deprecated
  way to materialize rendered bytes; before it, every host hand-rolled
  `String(decoding: buffer.bytes…)`.
- **the two string materializers (renderThroughBuffer, renderedString) are
  deleted** — not deprecated, so a 1.x host that calls either fails to compile.
  neither exists at HEAD. `render() -> String` survives only as a deprecated 1.x
  spelling (`markup.html`), kept so 1.x call sites compile.
- **`HTTPResponse.Body.html` now carries `UnsafeMarkup`, not `String`** — a bare
  `String` can no longer become a page; the compiler rejects it. the convenience
  `HTTPResponse(_ markup:status:headers:cookies:)` answers from a rendered value,
  and `HTMLDocument.body` / `WebUIDocument.body` carry `UnsafeMarkup`.
  `HTMLDocument.diagnostics(body:)` and `WebUIDocument.declaredIslandNames(in:)`
  deliberately stay `String` — both are pure scans that render nothing.
- **`Route.page` widened to `Route.page<D: BufferRendering>`** in both sync and
  async form with the **same `content:` label** — the compiler disambiguates on the
  closure's async-ness, so a trailing closure keeps working — and `PageResponder`
  is typed on `BufferRendering`, so a document (not a view) serves as a page.
- **`UnsafeMarkup.trusted(_:)` is the one escape hatch** for genuinely hand-written
  markup, and it is greppable by design.
- the arc closed the `String`-to-page seam from outside: the real consumer
  (`~/workspace/no-webui-migrate-test`) reaches served bytes four ways with zero
  `String`s materialized and zero calls to `UnsafeMarkup.trusted(_:)`. the naive
  (1.x) first build surfaces four error classes — document body, route content,
  response body, stylesheet-served-as-page — each answered `String` is not
  `UnsafeMarkup`/`BufferRendering`; the typed doors (`markup`, `HTTPResponse(_:)`,
  `Route.page`, `CSSStylesheet.markup`) close each. recorded in that repo's
  `naive-diagnostics.md` and the migration guide's typed-markup section.

### the web's actual HTTP surface (w3)

- **a typed request/response model.** `HTTPMethod`, `HTTPStatus`,
  `HTTPRequest` (method/path/query/headers/cookies/body/`renderToken`/
  `isSecure`/`params`) and `HTTPResponse` (`Body`: `.html(_:)`, `.text(_:)`,
  `.bytes(_:contentType:)`, `.stream(_:contentType:)`) are the server's
  vocabulary. `WebUISharedCore` gained a **Foundation-free** `HTTPCookie`/
  `CookieParser` (self-contained `HTTPDate`), and `WebUIAuth` re-exports both
  through deprecated renamed typealiases. a render answer keeps the guides
  the server already enforced: the `.html` body still carries auto-CSP and a
  **fresh nonce per render**, and `Set-Cookie` survives the response path.
- **a typed router.** `Router(_ routes:)` with
  `Route.get(_:_:)`/`Route.post(_:_:)`/`Route.page(_:content:)` and
  `PathPattern` (`"/users/:id"`, trailing `*rest`), matched
  most-specific-first by a computed `specificity` score so declaration order
  cannot matter (a test pins it), and the `/..%2f` traversal guard splits on
  `/` **before** percent-decoding. a page's `renderToken` flows into
  `RuntimeConfig(renderToken:)`, so `navigate` and events are answered — the
  gate that had been silently red since the runtime gained per-render tokens.
- **request bodies, forms and uploads.** `FormBody` with `FormValues`,
  `MultipartForm`, `UploadedFile`, and `BodyReader(maxBodyBytes: 1 MiB,
  maxMultipartParts: 64)`. `Form(enctype:)` and `Input(accept:multiple:)`
  ship real file inputs, and the engine's progressive enhancement submits a
  native multipart POST when a form has an explicit `action`, `method=post`
  and a file input — proven live in headless Chromium with JavaScript
  disabled, the uploaded bytes compared via the `X-Upload-Sha256` header.
- **renders return a typed response.** `HandlerOutcome` gains
  `.response(HTTPResponse)` — the case that retired the auth example's
  hand-rolled NIO — and a websocket handler's `.response` drives a redirect
  frame.
- **chunked streaming and SSE.** `HTTPStream` +
  `HTTPResponse.Body.stream(AsyncStream<[UInt8]>, contentType:)` for
  mid-stream cancellable chunks, and `SSEEvent`/`SSE` for server-sent
  events: every field value is split on line boundaries and re-emitted one
  `name: value` line each, so a payload containing a raw newline stays data
  and cannot manufacture a frame boundary.
- typed capability islands closed the wave and are covered in their own
  section below. the acceptance demo — `WebUIExample`, driven by
  `designer/acceptance-demo.mjs` (8/0) — exercises the surface in a real
  browser: a click over the websocket, a native form POST → 303, a real file
  upload persisted with a byte + sha-256 proof, three SSE events on an
  `EventSource`.
- wave-3 lines, every gate green at each step: 1206 → 1225 → 1254 → 1258 →
  1273 → 1284 tests, the byte pin **exactly 167300** throughout.

### breadth — the event deck, typed media, the typed aria surface (w4)

- **the full event deck.** seven families of events now round-trip typed
  payloads over the wire — pointer, touch, drag & drop, clipboard,
  wheel/scroll (rAF-throttled), misc, media — across `EventHandling.swift`,
  `Modifiers.swift` and `webui-engine.js`, and `View.on(_:perform:)`
  attaches any `HTMLEvent`, including the previously unreachable
  `.custom("dragstart")`. the gate is `designer/event-deck-probe.mjs`:
  33/33 browser, 32/32 socket, 35 other, 0 fail.
- **typed media.** `Video`, `Audio`, `Picture`, `Source`, `Track`, `Iframe`,
  `Canvas` with `TrackKind`, `IframeSandbox`, `LoadingStrategy`. `sanitizeURL`
  guards all six src-bearing paths **including `Video.poster`**, and a
  hostile src drops the element rather than emitting an empty attribute;
  `IframeSandbox.strict` is the **empty** set — no permissions at all — with
  `allow-scripts` an explicit opt-in. the framework's default CSP has no
  `media-src`, so `data:`/`blob:` media is browser-blocked unless a host adds
  a directive — recorded in the Video/Audio doc comments (w4.3).
- **the typed aria surface and its audit.** `Aria` (one case per attribute)
  and `AriaRole`, plus the typed states `AriaChecked`/`AriaExpanded`/
  `AriaPressed`/`AriaSelected`/`AriaModal`/`AriaHidden`/`AriaBusy`/`AriaLive`/
  `AriaCurrent`/`AriaSort`/`AriaHasPopup`/`AriaOrientation` — the case names
  are mnemonics and the raw values are the served bytes
  (`.expanded(.yes)` ships `aria-expanded="true"`).
  `A11yAudit.audit(_:)` answers `[A11yFinding]` with six named rules
  (`buttonNoName`, `imageNoAlt`, `controlNoLabel`, `interactiveNoName`,
  `headingSkip`, `roleMissingAria`), and the framework's own markup is clean:
  `designer/a11y-audit.mjs` (26/0) proves its own rules fire by feeding a
  synthetic `<img src="x.png">` to `imageNoAlt` before asserting zero
  findings. **this is the wave's one authorised byte-pin move, 167300 →
  168671 (+1371), proven fragment-by-fragment to be a11y-only**: 62 added
  fragments, 43 carrying `aria-`/`for=`/`<label`/`role=`, the removed side
  exactly the 8 old unassociated `<label class="demo-label">` tags — nothing
  deleted, nothing cosmetic.
- error boundaries (w4.2) and localization + typed direction (w4.5) have
  their own sections below. wave 4 closes at **1355 tests / 0 issues, exit
  0**, twelve gates.

### aesthetics — typed theming and public stylesheets (w5)

- `DesignTheme` is the typed theming protocol: five **mandatory** static axes
  (`palette`, `spacing`, `radii`, `typography`, `motion`) with no defaults,
  so a conformer that omits one cannot compile — the completeness promise is
  structural, not documented. `DefaultDesignTheme`,
  `DerivedTheme<Base: DesignTheme>` (a value that statically inherits the
  base and applies overrides at render time), `TokenOverrides`
  (`ExpressibleByDictionaryLiteral`, so `.overriding([.colorPrimary500:
  "…"])` is a bare dictionary literal), `resolvedPalette`, `.webUITheme(mode:)`
  and the `@Theme` conformance macro complete the surface. the demo —
  `WebUIExample`, driven by `designer/theme-default-probe.mjs` (40/0) —
  overrides exactly three tokens for both themes through the typed path
  (`.overriding([.colorPrimarySolid, .colorBg, .colorBorder], mode:)`) and
  renders them from one host at `/theme-light`, `/theme-dark` and
  `/theme-default`, the last a control page proving the unoverridden values
  are the framework's (and that the dark page needs no OS media query to
  prove it).
- token completeness is machine-checked **in both directions**: the
  generated `DesignToken.verify(_ theme: any DesignTheme.Type) ->
  [MissingToken]` (with `.notInStylesheet`/`.misplacedAxis` kinds)
  re-implements the stylesheet scan independently of the generator, and two
  negative tests assert a `MissingToken` that *names* the token.
- **a public `StyleSheet` with typed cascade layers.** `StyleSheet(name:
  layer:rules:)` with `CascadeLayer` (`.webui`, `.utilities`, `.host` —
  declared last so it wins by origin), the `CSSRuleBuilder`, and
  `StyleSheet.css` emitting the canonical `@layer webui, webui.utilities,
  host;` statement — a host rule beats the framework at equal **and** lower
  specificity with zero `!important` in host bytes, proven in
  `designer/cascade-probe.mjs` (12/0) on computed style against a control.
  `WebUIDocument.styleSheets` and `stylesheetURL` ship it as a cacheable
  `<link>` instead of inline bytes.
- additive throughout: wave 5 closes at **1396 tests / 0 issues, exit 0**,
  fourteen gates, the **byte pin unmoved at 168671** — the wave that proved
  theming and stylesheets cost the served page nothing.

### deprecation and removal schedule

- per `Documentation/STABILITY.md` ("deprecation"), a frozen-surface member
  ships its deprecation across **one full minor release** and removal lands
  in the **next major**. `Documentation/MIGRATION_2_0.md` carries the
  schedule row by row, and its removal column says **2.0.0** for every row:
  the slot spellings (the nested `Size`/`Variant`/`State`/`Status` enums and
  the 56 surviving aliases and forwarding inits), the case-name aliases on
  `ControlSize` and the state enums, `Raw(_ content: String)` (and
  `Raw.content`), the `head:`/`dir:` string parameters, `WebUIAuth.Cookie`/
  `CookieParser`, and the two render-closure server inits (`init(render:…)`/
  `init(requestRender:…)`). the `render()` default is a deprecated
  requirement-replacement, removed with the rest.
- `WebUIMenu.Item.destructive` rode the w0.8 read-through into `danger`
  (deprecated property + deprecated initializer); `WebUICard`'s deprecated
  `Variant` enum and `init(variant:)` forward to `elevation:` + flags byte
  for byte; the inert chart scroll api listed in the charts entry below was
  removed without a cycle because it had no reader anywhere — recorded in
  `STABILITY.md` as "removals that were never
  functional", the corrective precedent rather than a deprecation.
- **a schedule note the cut must decide.** `MIGRATION_2_0.md` frames the
  deprecation carrier as "the minor shipping right now is 1.1.0", but the
  1.1.0 tag (`94301a1`, 2026-09-23) predates every deprecation this arc
  introduced (wave 1 opened 2026-10-08) — none of them has shipped in a
  public release. STABILITY's "one full minor" therefore does not hold
  automatically if 2.0.0 is cut directly from this tree: the deprecations
  would have lived **zero** minors in the wild. the consistent reading is
  that a 1.x minor carrying the deprecations ships first (the schedule the
  migration guide assumes), or the owner records an explicit waiver in the
  cut record. this changelog names the rule and the fact; the cut is the
  owner's call.

### security invariants preserved

- the release keeps every security invariant the 1.x epoch documented, and
  the new surface is held to the same bar: server-authoritative rendering
  with a per-render CSP nonce; escaping that cannot be accidentally skipped
  (`UnsafeMarkup.trusted(_:)` is the only way in, and the typed head keeps
  scripts' nonce until render); typed slots that make old injection payloads
  inexpressible (the wave-1 hardening test that used a `status:` string as an
  injection vector now asserts the structural property instead); the router's
  split-before-decode traversal guard; body caps defaulted-on and refused
  **before buffering** (a declared `Content-Length` over the cap, a lying
  `Content-Length` answered 400, an overloaded body a 413 naming its limit);
  SSE fields that cannot manufacture frame boundaries; media urls sanitized
  on every src-bearing path with a hostile src dropping the element; and an
  iframe sandbox that defaults to zero permissions.
- the shipped bytes stay prose-free (build-time `ProseGuard`), the pre-paint
  theme prelude carries the render nonce, and the framework's own pages are
  a11y-clean — the audits each prove their rules fire before asserting zero
  findings.

### verification

- `swift test` **1398 passed / 0 issues, exit 0**; `swift build` clean.
- the fourteen-gate ladder, one consecutive run at this head:
  plugin `smoke` **19/0**; plugin `fullstack-smoke` **24/0**;
  `designer/browser-smoke.mjs` **50/0**; `designer/showcase-ws-smoke.mjs`
  **9/0**; `designer/blocks-sweep.mjs` **107/0**;
  `designer/chart-mobile-audit.mjs` **77/0**; `designer/rtl-audit.mjs`
  **54/0**; `designer/acceptance-demo.mjs` **8/0**;
  `designer/event-deck-probe.mjs` 33/33 browser · 32/32 socket · 35 other,
  0 fail; `designer/a11y-audit.mjs` **26/0**; `designer/cascade-probe.mjs`
  **12/0**; `designer/theme-default-probe.mjs` **40/0**;
  `designer/engine-theme-default-probe.mjs` **5/0**.
- **the showcase byte pin: exactly 168671 bytes** at this epoch. the number
  is enforced in-repo — `showcaseBytePin` in `ShowcaseWiringTests.swift`,
  the single occurrence tree-wide — and re-rendered by `swift run
  WebUIShowcase --generate`. per `Documentation/STABILITY.md` ("the showcase
  byte pin"), what the gate asserts is the byte **count**, never a hash of
  the raw bytes: `JSONValue.serialize()` iterates a `Dictionary`, so byte
  *order* is nondeterministic across processes while the count is stable.
  "byte-identical" is therefore only ever true in the weak sense — identical
  count and identical markup under a stable process — never as a
  hash-verifiable promise. a drift fails the suite naming measured vs pinned.
- STABILITY's coverage number, stated per the cut criterion: the generated
  `Documentation/frozen-surface.symbols` enumerates **4561 member-level
  symbols** across the eight modules a consumer reaches, re-extracted
  in-process on every `swift test` and failing by name on any added or
  removed symbol. the migration contract is `Documentation/MIGRATION_2_0.md`:
  five wave tables (w1 = 26, w2 = 7, w3 = 12, w4 = 9, w5 = 4 data rows,
  58 in all — measured), appendix a the re-measured 79-line deprecated
  inventory, appendix b how the document verifies itself.

### localization and direction (w4.5)

- the framework's own rendered strings — labels, aria names, default
  placeholders, toolbar chrome — now live in one catalog (`WebUIStrings`,
  `Sources/WebUICore/Localization.swift`) and resolve through the render
  context: a page sets strings/locale/direction once and every component in
  the pass reads the same catalog. `WebUIDocument` declares `locale` (feeds
  `<html lang>`) and `direction` (feeds `<html dir>`); the english defaults
  are byte-identical to the pre-i18n output (showcase byte pin unchanged),
  and a host overrides any subset. numeric/date formatting stays host-side —
  recorded as a limit in `STABILITY.md`.
- `LocalizedEnvironment` is read through `RenderContext`; `WebUILocalization`
  is the default (english/en/ltr). ships an arabic example catalog
  (`WebUIStrings.arabic`).
- tests: `LocalizationTests` (defaults pinned, english render outside a
  context, context threading, subset override, arabic render, and
  locale/direction on the document).

### error boundaries (w4.2)

- `ErrorBoundary<Content, Fallback>` answers a failing handler in its subtree
  with rendered fallback markup: while its content renders, every component
  id the subtree registers is recorded, and the boundary registers a fallback
  for exactly those ids. when one of those handlers later throws, the
  `HandlerOutcome.fail` path patches the boundary's wrapper element (a
  `div` with a per-render stable id, replaced by id on the client) with the
  rendered fallback. a failing handler outside any boundary keeps the
  pre-w4.2 behaviour: the error frame fires and the page keeps what it
  had. `.errorBoundary { ... }` wraps any view, and `ErrorBoundary` is the
  first real conformer of the `Recoverable` capability.
- the responder chain can now fail: `Route.page` content and the render
  closures may throw, and a throw is answered as a 500 carrying the host's
  error page (`WebUIServerConfig.onRenderFailure`) instead of dropping the
  connection. default (no host page): a plain-text 500 naming the failure.
- boundaries catch *failures*, not swift *traps* — process isolation stays
  explicitly out of scope, recorded as a limit in `STABILITY.md`.
- tests: `Tests/WebUITests/ErrorBoundaryTests.swift` (fallback in / out of
  the boundary, the modifier, inertness without a context, the 500 path with
  and without a host error page). `Responder`/`Router.respond` became
  `async throws`; the route-tests now `try`.

### capability islands are typed (w3.6)

- `Island` (`static let name` + `static func render(_:)`, same swift both
  sides) and `IslandRegion<I: Island>` make declaring an island the whole
  wiring: the view renders the engine's mount point
  (`data-webui-island="<name>"` + a json `data-webui-args` envelope carrying
  the input), and `WebUIDocument` collects every declared capability out of
  the rendered body and folds it into the emitted `RuntimeConfig.capabilities`
  (merging with an explicit `runtimeConfig:`/`clientMode:` list, deduplicated,
  caller order preserved). the engine's existing lazy fetch does the rest —
  no new client runtime, no manual `capabilities:` entry.
- the region carries its own server-rendered fallback (`I.render(input)`), so
  an absent artifact degrades to static markup with the page fully
  server-rendered. a body with no islands leaves the emitted config
  byte-identical (the showcase pin holds).
- the smoke page declares two typed regions — one sharing the existing
  `validate` artifact (two regions, one fetch — the browser gate counts it),
  one with no artifact (degrades to the fallback) — and `browser-smoke.mjs`
  asserts the artifact is fetched exactly once and the regions render.
- tests: `Tests/WebUITests/IslandTests.swift` (mount contract, escaping,
  config collection, merge, dedupe).

### docs — the high-level docs now match the shipped surface

every claim below was measured against the tree, not restated. the five defects
D1–D9 were all drift of the same kind: a document describing a different
package than the one that builds.

- **README**: test count 903 → **1095**; doc-file count 11 → **16**; rawdog pin
  "v21+" → **`22.0.0..<23.0.0`**; the module table listed 11 entries against
  **24 targets** and omitted every target added since — it now names the 24
  (13 libraries, 10 executables, 1 macro), the 11 plugins split into 3 build
  tools vs **8 command verbs as `swift package plugin --list` actually reports
  them** (`budget` had been misfiled as a build tool), and the real dependency
  set (swift-log 1.x, swift-nio 2.x, swift-service-lifecycle 2.6.x,
  swift-syntax 603.x, rawdog 22.x — the list had omitted two of the five).
  the project tree, the doc index and the requirements were re-derived the same way.
- **API.md**: `EventData.data` documented as `[String: String]` — it is
  `[String: JSONValue]`, and the accessors are `string(_:)` / `number(_:)`
  (**no** `bool(_:)`; the wrong accessor would have been easy to write here and
  impossible to compile). the `WebUITable` parameter list was paraphrased and
  three parameters short — it now names `sortableColumns`, `hiddenColumns`,
  `sort`, `selectable`, `selectedRows`, `expandedRows` exactly. `OutcomeHandler`
  (added in W0.2) is now documented too.
- **ARCHITECTURE.md**: the wasm monolith client was described as live — "the
  **wasm client** (`WebUIClient`) remains available via an explicit
  `ClientBoot(flavor: .wasm, …)`" — in a file that notes its deletion fifty lines
  later. `flavor:` does not exist anywhere in `Sources/`, and
  `designer/assets/webui-client.js` does not exist either. Layer 5 is now the
  capability-island model (`wasm-island`, `WebUIIslandCore`, the artifact path),
  and the three security-table rows describing the deleted chamber as a current
  mitigation were corrected or dropped.
- **STABILITY.md**: the post-deletion note disclaimed "any reference to the
  client boot **below**" while sitting *below* the stale references — the file's
  own contradiction. the note now heads the section it governs, and items 2/3/5/7
  state the deletion instead of describing the deleted path as available.
- **CHANGELOG.md** is at the repo root, not `Documentation/` as the plan had it.

evidence: `swift test` → 1095 tests / 113 suites pass, exit 0 (docs-only change;
the suite is run because the claims above are about the code).

### stability — the frozen list now matches its own evidence

- **seven unproven types left the frozen surface.** `WebUISelect`,
  `WebUISpinner`, `WebUITooltip`, `WebUIChip`, `WebUIReasoningBlock`,
  `WebUIToolStep` and `WebUITurnSummary` have no renderer in any library target
  or demo page — their only exerciser is the `APISurfaceTests` pin. they are now
  documented as *shipped but unproven — review on first use*, so a shape nothing
  has validated is no longer bound to a release promise. **this is a promise
  being narrowed, not code being removed**: every one of them still compiles,
  renders and is pinned; the change is that fixing their shape no longer needs a
  deprecation cycle.
- **sixteen exercised types joined the frozen surface.** `WebUIMenu`,
  `WebUIActivityFeed`, `WebUIAspectRatio`, `WebUICircularProgress`,
  `WebUIBanner`, `WebUIToggleGroup`, `WebUISeparator`, `WebUIKbd`,
  `WebUIInputGroup`, `WebUIMarker`, `WebUIAttachment`, `WebUINavbar`,
  `WebUIItem`, `WebUISidebarItem`, `WebUIField` and `WebUIMenubar` are rendered
  by shipped pages, so their shape was already a de-facto contract while the
  list said it was free to change in a minor. `WebUISidebarItem` is named in the
  frozen `WebUISidebar`'s own signature, which made the mismatch a contradiction
  rather than an omission. the criterion is now stated: coverage, not file
  membership — which is why two types living in the `WebUIExtras*` long tail
  (92 components, measured) are frozen while the other 90 of that tail stay
  outside.
- `Documentation/STABILITY.md` re-measured rather than asserted: mention counts
  are recorded per type.
- **no dead API was removed.** the plan's T11 read `Sources/WebUIChart/ChartP5Marks.swift`
  as a `ChartP5*` public surface with no reader. no such type exists — the file
  declares `RadarMark`, `RadialMark` and `ChartGradient`, all of which render on
  the smoke page, in the showcase and in two test suites. the *filename* was the
  defect: it named the plan phase that produced it. the file is now
  `ChartRadialMarks.swift` (suite: `ChartRadialMarkTests`) so the trap is gone.

### runtime — streaming patch ops and calm patches

- **`FragmentUpdate` gains ops.** `append` inserts one subtree as a child of the
  target (anchored via `before`, idempotent by the child's own id, never coalesced);
  `text` writes the target's text content — in steady state the text node's data is
  mutated, so a token stream costs characterData writes and zero element churn.
  Absent op = `replace` (unchanged; emits no `op` on the wire). Unknown ops warn and
  skip rather than guess.
- **transition policy.** A patch animates only when the consumer allows it: no
  per-fragment `transition:false`, no `data-webui-transition="off"` ancestor region,
  no transition already in flight, no `prefers-reduced-motion`. `append`/`text` never
  animate; refused transitions still apply synchronously. Measured pre-change: one
  view transition per push on a token stream (108–368 per turn).
- **`details[open]` survives a patch.** The engine's save/restore captures and
  re-applies `details` open state per stable key (`data-webui-key` / id / structural
  index); a captured-open row the replacement drops warns once per key. Measured
  pre-change: a reasoning row opened mid-stream was re-emitted collapsed by the next
  push.
- **queued application, last-write-wins.** Patches apply in order; same-target
  `replace`/`text` updates collapse to the newest, and applications serialize behind
  an in-flight transition — an older deferred animation callback can no longer clobber
  a newer update. Also: the engine's reduced-motion guard now reads
  `window.matchMedia` (`document.matchMedia` does not exist in current Chromium, so
  the guard had been dead code).

### assets (additive)

- **the asset toolkit ships** — the machinery no-webui already runs for its own sheet,
  engine and shell, as three host-facing products: `WebUIShippedAsset` (the protocol
  generated code conforms to, in `WebUICore`), `WebUIBuild` (host-side gzip, emitter and
  manifest), `WebUIEmbedPlugin` (embeds a target's `Assets/webui-assets.json` on every
  build) and `WebUIAsset` (server-side url + registration + cache from one value). a
  consumer stops hand-rolling hashing, compression, embedding, address/registration pairing
  and cache headers. see `Documentation/ASSETS.md`.
- `WebUIServerAsset` gains `immutable:`; `WebUIAssetTool` gains
  `--embed-manifest <json> --output <swift>`; manifest entries may pin
  `ceilingBytes`/`ceilingGzipBytes`, enforced at embed time (the build refuses before
  anything ships), and `plugin budget` reports one row per consumer entry.
- `ThemeSheet` gains an optional pre-compressed variant and its route negotiates
  (`Content-Encoding` + `Vary`) — the url is unchanged (`/__assets/theme.<sha256>`).

### theming (breaking)

- **`ColorScheme` is now `ThemeMode`**, `WebUITheme` carries a **light/dark pair** instead of
  one `scheme:`, and `stylesheet()` takes a **`ThemeScope`**. in-place breaks — no alongside
  type, no deprecation window, no shim. `ColorScheme` is the name consumers give their *own*
  scheme type (arc's 27-scheme enum is exactly that), and a theme that means different things
  in two modes cannot be one palette. every in-tree call site moved in the same commits.
- `@Theme(base: Base.self)` — themes **inherit**. `static let` members are overrides layered
  per palette over the base's, so a scheme states the tokens it changes (11) instead of all of
  them (35). `light`/`dark` members replace the reserved `scheme`; a theme naming itself as its
  own base is an expansion error.
- `WebUIThemeProvider` gains `themeID`/`themeLabel`/`themeSwatch` (defaulted, so an existing
  conformer still compiles) and `ThemeCatalog` collects providers into `all`/`defaultTheme`, so
  a picker renders from the catalog rather than a hand-written list. catalog integrity — unique
  ids, a default that is a member, every `base` resolving — is tested.
- **one sheet carries every scheme.** `ThemeScope.attribute` emits
  `:root[data-scheme="…"][data-theme="light|dark"]` plus a `prefers-color-scheme` pass, so a
  scheme switch costs no round trip and no server render; the `.root` default keeps a
  single-theme page byte-identical.
- **the engine owns switching**: scheme + mode, persisted in `localStorage`, `system` following
  `prefers-color-scheme`, and a `webui:theme` event. a stored choice is applied by a
  **pre-paint prelude** — a comment-free inline script carrying the render nonce, so the stored
  palette is never flashed over — and the prelude's storage keys are asserted against the
  engine's.
- `ThemeSheet` serves the rendered catalog from a **content-addressed url**
  (`/__assets/theme.<sha256>`), so the theme no longer rides `rawStyles` and a second
  navigation transfers zero theme bytes. the address is computed from the bytes, so the url a
  page links and the url a server serves cannot disagree.
- `WebUITheme`/`ThemePalette`/`ThemeEntry` are **`Codable`**, keyed by css token name, which is
  what lets the catalog ship to the client as data (encode → decode → identical css).
- `TokenAlias("--bg", .colorBg)` declares an app's own property vocabulary **in Swift** against
  `DesignToken` and emits the indirection `--bg: var(--color-bg)`, so a mistyped token is a
  missing enum case instead of a missing colour.
- contrast is swept for **every theme × mode** from the typed catalog
  (`DeploymentIntegrityTests`) rather than 50-odd hand-written pairs that rot.

### css delivery — the cascade is now explicit

- **the sheet ships in cascade layers.** `@layer webui, webui.utilities;` wraps the
  framework's rules — components in `webui`, the layout primitives the asset tool
  prepends in `webui.utilities` — so **unlayered css outranks the framework by cascade
  origin, not by specificity**: an app's own stylesheet, `rawStyles`, and the theme
  sheet win outright, and restyling a component never needs `!important` or matching
  selector weight. measured before the change: 704 of the sheet's 2,511 rules sat above
  single-class specificity, so an override like `.button--icon.button--sm` could only be
  beaten by escalating to the same weight. the browser gate now proves the consequence
  on the deployed page (a single-class consumer rule beats a two-class framework rule),
  and `CascadeLayerTests` scans the served bytes, failing if any rule escapes the layers.
  theme sheets stay *unlayered* by design, so a theme outranks the base sheet's tokens.
  this is a consumer-visible change by intent: css that used to tie or lose to the
  framework now wins.

### engine & assets

- assets are compressed at **build** time (the tool runs the host `gzip`) and `WebUIServer`
  negotiates `Accept-Encoding`, sending `Vary` whenever a variant exists — so the sheet leaves
  the server at its compressed size (321,262 → 44,991 gz) while a client that asks for nothing
  still gets the bytes it always did. no runtime compressor is linked.
- `plugin budget` gates the shipped surface against a pinned table (engine, sheet raw+gz,
  shell, per-island) and reports retired artifacts; every ceiling carries 5-15% headroom and
  names the measurement it came from. the served numbers come from the build manifest, not the
  working files — a budget on the wrong number is a false sense of safety.
- `WebUIEngine.on.afterPatch(fn)` / `on.ready(fn)` — the post-patch seam a consumer needs to
  re-run enhancement work (math, table tooling) against the mutated subtree instead of
  rescanning the whole DOM on every mutation.
- `HTMLDocument.contentSecurityPolicyExtras` (and `WebUIDocument`'s forwarding parameter) lets a
  host add directives — `img-src … https:`, a `font-src`, a `form-action` — without restating the
  policy. extras **merge per directive name** into the effective policy (the nonce-aware default,
  or an explicit `contentSecurityPolicy`), so a repeated name replaces the base's directive and
  every name the host did not mention, including the render nonce, is carried over. the case that
  motivated it: a host that restated the policy to add two directives lost the nonce, and
  `HTMLDocument` then suppressed the pre-paint theme prelude rather than ship an inline script the
  browser refuses — a stored scheme flashed on every load, with only a log line to say why.
- `WebUIAssetTool --used-tokens <path> [--guard-css <path>]` prunes the sheet's `:root` token
  surface to the reachable set (T9): a catalog resolving 40 of the 174 tokens emits a 40-token
  sheet, `--guard-css` keeps anything a consumer's own stylesheet still resolves, the counts
  land in the build manifest, and a name the sheet does not declare fails the build. omitted,
  the sheet ships whole — byte-identical to before.
- `WebUIServerAsset.gzip` — a host may register a **pre-compressed** variant of any asset, and
  the server negotiates it exactly like the framework's own sheet and engine: `Content-Encoding:
  gzip` for a client whose `Accept-Encoding` allows it, `Vary: Accept-Encoding` whenever a
  variant exists (including on the plain response — or a shared cache would hand the compressed
  bytes to a client that never asked). the server still compresses nothing at runtime; a host
  builds both forms in its own tooling and passes both.
- the engine's mode fallback no longer discards a **server-rendered** default: with no stored
  choice it keeps the `data-theme` the server rendered, a stored choice still wins, and only a
  page rendering neither falls back to `system`. `data-scheme` already behaved this way — not
  storing a choice is not the same as choosing nothing — and the pre-paint prelude always had
  this shape; the engine was the odd one out, and a host's server-side default mode was
  silently replaced on every fresh client. `designer/engine-theme-default-probe.mjs` is the gate
  (it drives a synthesised page whose only theme code is the engine), and it refuses to run
  against a port that is already serving: an earlier revision of it passed while measuring a
  **stale** server left over from the previous run.
- **the shipped payloads are prose-free, checked at build time.** `WebUICore.ProseGuard` reads
  comments only where each language says one can start — a `//` inside a string literal is not a
  comment — and the asset tool runs it over every payload a client can receive: the runtime, the
  engine, the shell, and the minified sheet. a comment fails the build naming file, line and text.
  the runtime had been shipping a seven-line "Host extension points" note plus a `///` line
  verbatim (11 comment lines, −698 bytes); the engine's and shell's comment-free pins never
  covered it, and the plan's `grep -c '//'` lint was never built. the note now lives in
  `Documentation/JS_RUNTIME.md`, where prose belongs.

### fixed

- **the orphan-class ratchet no longer hears prose.** `orphanBaselineIsTight` measured
  "reachable" as "mentioned anywhere in swift", so the english word `comment` — in a prose note,
  or in a message string such as `"would ship N comment(s) to clients"` — declared the sheet's
  genuinely orphaned `.comment` class reachable and demanded its deletion from the baseline: the
  ratchet would have rotted a real orphan on the strength of a mention. tightness now measures
  **emissions** (a rendered page, plus the engine's own js-only class names), while the mention
  scan stays what it was written to be — the *growth* direction's lenient floor.
- **a generated csp authorizes the inline theme prelude.** `ClientBoot.csp(nonce:)`
  splices the render's nonce into the default policy. before this, the served default
  policy named no nonce source, so the pre-paint prelude was **blocked by the browser**
  on every reference page — measured: the browser smoke gate and the block sweeps both
  reported `script-src 'self' 'wasm-unsafe-eval'` violations and a stored theme never
  applied before paint. a host policy that names no nonce source now *suppresses* the
  prelude (with a warning naming the fix) instead of shipping a script the browser will
  refuse. `preludeTag` is emitted only when the effective policy can run it.

### developer experience

- `WebUIServerService` — hosts a `WebUIServer` as a `Service`, so a long-lived
  page server starts and stops inside a `ServiceGroup` (ordered startup,
  graceful shutdown) instead of owning its own process lifecycle. a bind
  failure propagates out of `run()`, so a server that cannot listen fails
  startup rather than reporting itself ready. `swift-service-lifecycle` is a
  new dependency of the `WebUIServer` target.
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

- `WebUIServer.broadcast(_:)` — server-initiated fragment pushes, with no
  inbound event to answer. the server tracks its connected pages and writes an
  `update` to each, which is what streaming a turn, reporting background
  progress, or refreshing a panel that changed on disk needs.
  `connectedPages` exposes the live count. a socket whose render token the
  server rejects is already closed, so a push cannot reach a stale page from a
  former session.
- `WebUIServerConfig.assets` — a host can now serve its own assets (vendor
  css/js, woff2 fonts, app scripts) through the same server that serves the
  framework's, via `WebUIServerAsset.text(_:_:contentType:cacheSeconds:)` and
  `.bytes(_:_:contentType:cacheSeconds:)` (the `bytes` case keeps binary
  payloads off the `String` path). no second http server for asset paths. the
  framework routes (`/__assets/css*`, the engine, the shell) are matched first,
  so a host asset can neither shadow nor disable them.
- `WebUIServer` request-aware render —
  `init(requestRender:router:config:logger:)` hands the page closure a
  `WebUIServerRequest` (path + decoded query), so a host can render
  `/index.html?s=<id>` deep links. the zero-argument `init(render:...)` is
  unchanged and now simply ignores the request.
- `WebUIServer` strips the query string before routing. previously the whole
  `uri` was matched, so `/__assets/css?v=9` — and any query-bearing page url —
  404'd. cache-busting query strings and deep links now resolve. `+` decodes to
  a space and `%XX` to its byte; a malformed escape is preserved verbatim
  rather than dropped.
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