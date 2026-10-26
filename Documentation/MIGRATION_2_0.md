# Migrating to 2.0

the contract for the 2.0 cut: every 1.x spelling that changed across wave 1–5,
one table per wave, each row naming the deprecated shim and the version that
removes it. this document is derived from the tree at `245eecc` (waves 1–5) —
the typed-markup arc's `markup` materializer is documented against HEAD in the
section below — and from the plan's wave log (section 16) — every symbol below
greps in `Sources/` at its stated base; a row whose symbol does not grep is a
failed push, not a typo.

two corrections to the plan's own sketch, stated up front because a host that
starts from the plan would migrate into APIs that do not exist:

- **the plan's `Variant` → `emphasis:`/`tone:` row was never shipped.** no
  `emphasis:` parameter exists anywhere in the tree (0 hits tree-wide). the
  three components the plan wanted to split — `WebUIButton`, `WebUITag`,
  `WebUIAccordion` — were *renamed* instead: their `Variant` became
  `Appearance` and their parameter is `appearance:`. `Emphasis` exists only
  as a top-level vocabulary slot with no consumer. only `WebUICard` was
  genuinely split, and it split onto `elevation:` plus typed flags.
- **the plan's replace-classes escape was never implemented.** `.class(_:)`
  and its siblings merge in 2.0, and there is no replace-classes modifier in the
  tree. a host that needs to take a framework class off an element does it
  host-side, through the cascade (unlayered host css outranks the layered
  framework sheet) — see `Documentation/STABILITY.md` and `CascadeLayerTests`.

## the deprecation contract

per `Documentation/STABILITY.md` ("deprecation"): before a frozen-surface
member may be removed it ships a public `@available(*, deprecated, …)` marking
across **one full minor release**, plus a changelog entry naming the
replacement; removal lands in the next **major**. the shims below therefore
live through `1.1.x` (the minor shipping right now is `1.1.0`) and are removed
**in 2.0.0** — every "removal" column below says 2.0.0 unless noted, and the
row for `render()` carries the caveat that the shim is a deprecated
*default*, removed with the rest.

how to read the tables: | old 1.x spelling | 2.0 spelling | emits | shim that still compiles | removed in |

the byte guarantees are the wave gates' own: `plugin smoke` (19 assertions)
pins served bytes, `blocks-sweep` (107) pins 8 blocks × both themes, and the
showcase `--generate` byte pin re-renders exactly 168671 bytes — the number is
re-measured, not asserted, at the end of this document.

## wave 1 — one semantic vocabulary

wave 1 replaced the nested, per-component slot enums with 18 top-level types
in `Sources/WebUIDesignSystemCore/Vocabulary.swift`, keyed by the semantic
token each raw value names. the wave-start measurement: 15 nested `Size`, 13
nested `Variant`, 5 `State`, 3 `Status`, 2 `Side`, 2 `Edge`, and `Brand`
declared twice with different raw value sets — a generic bearer was
impossible while the same concept had 15 spellings. every 1.x spelling below
survives as a deprecated alias, and `DeprecatedVocabularyTests` calls all 56
of them so an alias that points somewhere else fails at compile-in-test rather
than at a host's call site.

| old 1.x spelling | 2.0 spelling | emits | shim that still compiles | removed in |
|---|---|---|---|---|
| nested `Size` enums — `WebUIButton.Size`, `WebUIBadge.Size`, `WebUIAvatar.Size`, `WebUIProgress.Size`, `WebUISpinner.Size`, `WebUIStat.Size`, `WebUICircularProgress.Size`, `WebUISlider.Size`, `WebUIToggle.Size`, `WebUIStepper.Size`, `WebUIOTP.Size`, `WebUIRating.Size`, `WebUIFab.Size`, `WebUIDrawer.Size`, `WebUIKbd.Size` | `ControlSize` (`size: ControlSize`) | byte-identical — each component maps through its own `classFor(_:)`, so `sm`/`md`/`lg`/`xl` emit the exact class fragments 1.x emitted | `@available(*, deprecated, renamed: "ControlSize")` typealias per component | 2.0.0 |
| `ControlSize.small` / `.medium` / `.large` (the case names `WebUIKbd` and `WebUICircularProgress` used) | `.sm` / `.md` / `.lg` | byte-identical | deprecated static aliases on `ControlSize` (`Vocabulary.swift:51,53,55`) | 2.0.0 |
| `WebUIButton.Variant`, `WebUITag.Variant`, `WebUIAccordion.Variant` + `variant:` parameter | `Appearance` + `appearance:` parameter (one axis each; the plan's split is unsound for these three) | byte-identical | deprecated `typealias Variant = Appearance` + a required `variant:` forwarding init per component | 2.0.0 |
| `WebUICard.Variant` (fused: `elevated`/`outlined`/`flat` + `interactive`/`horizontal`/`hover`/`compact`/`disabled`) | `elevation: Elevation?` + typed flags `interactive:`, `horizontal:`, `hover:`, `compact:`, `disabled:` — `nil` elevation is the base surface a flag case rendered | byte-identical, and the flags now compose with elevation | deprecated `Variant` enum (`WebUIComponents.swift:280`) + deprecated `init(variant:)` (`:383`) | 2.0.0 |
| `WebUISkeleton.Variant` + `variant:` | `shape: SkeletonShape` | byte-identical, exact case-for-case match | typealias + deprecated `init(variant: SkeletonShape)` (`:857,:892`) | 2.0.0 |
| `WebUIBottomSheet.Variant` + `variant:` | `position: SlidePosition` (`peek`/`half`/`full`) | byte-identical, exact case-for-case match | typealias + deprecated `init(variant:)` (`WebUIExtrasNavOverlay.swift:526,:554`) | 2.0.0 |
| `Variant` on the seven tone components — `WebUIBadge`, `WebUIAlert`, `WebUIProgress`, `WebUIToast`, `WebUIChip`, `WebUIBanner`, `WebUIFab` + `variant:` | `tone: Tone` (`Tone` gained the brand-position case `secondary`; the mapping is built from each enum's own raw values, so `WebUIBanner.danger` still emits `banner--error`) | byte-identical | deprecated `typealias Variant = Tone` + a required `tone:` forwarding init per component | 2.0.0 |
| `WebUINotification.Kind` | `Tone` | byte-identical | `@available(*, deprecated, renamed: "Tone")` typealias | 2.0.0 |
| `WebUICircularProgress`'s private nested `Tone` (fragment raw values, `primary = ""`) | shared `Tone` (its un-offered tones forward the ring's own pattern) | byte-identical | deprecated `typealias Tone = WebUIDesignSystemCore.Tone` (`:2200`) | 2.0.0 |
| `WebUIInput.State`, `WebUIValidation.State` + `state: State` | `state: ValidationState` (`.normal` → `.none` on the way) | byte-identical | deprecated typealias + the deprecated case name `normal` | 2.0.0 |
| `WebUIPullRefresh.State`, `WebUIAttachment.State` | `state: LoadState` (`.active`/`.uploading` → `.loading`, `.error` → `.failed`) | byte-identical | deprecated typealias + deprecated case names | 2.0.0 |
| `WebUIInlineEdit.State` | `state: EditState` | byte-identical | deprecated typealias | 2.0.0 |
| `WebUIWizard.Status`, `WebUITimeline.Status` | `status: StepStatus` (`.plain` → `.pending`; `completed` and `done` stay distinct — the sheet ships both rules) | byte-identical | deprecated typealias + the deprecated case name `plain` | 2.0.0 |
| `WebUIStat.Trend`, `WebUIDelta.Direction` | `Trend` | byte-identical | deprecated typealias | 2.0.0 |
| `WebUIBadgeStatus.Status` | `status: Presence` | byte-identical | deprecated typealias | 2.0.0 |
| `WebUIChatBubble.Side` | `side: BubbleSide` (`received`/`sent`) | byte-identical | deprecated typealias (`WebUIExtrasCommsState.swift:770`) | 2.0.0 |
| `WebUIPopover.Side` | `side: Placement` | byte-identical | deprecated typealias (`WebUIExtrasNavOverlay.swift:660`) | 2.0.0 |
| `WebUIDrawer.Edge` | `edge: DrawerEdge` | byte-identical | deprecated typealias (`:589`) | 2.0.0 |
| `WebUIPanel.Edge` | `edge: PanelEdge` | byte-identical | deprecated typealias (`WebUIShell.swift:401`) | 2.0.0 |
| `WebUIPayCard.Brand` and `WebUICardInput.Brand` (declared twice, different raw value sets) | one shared `Brand`; the raw class fragments move into `classFor(_:)`/`token(_:)` | byte-identical | deprecated typealiases (`WebUIExtrasForm.swift:589`, `WebUIExtrasData.swift:572`) | 2.0.0 |
| `WebUISeparator.Orientation`, `WebUITimeline.Orientation` | `orientation: Axis` | byte-identical | deprecated typealias | 2.0.0 |
| `WebUIGantt.Bar.state: String?` (empty default) | `state: GanttBarState?` (`active`/`done`/`warn`; unstyled is `nil`) | byte-identical | typed parameter; the stringling could never compile away the warning | 2.0.0 |
| `WebUIJsonTree.Node.type: String` | `type: JsonNodeType` (`string`/`number`/`boolean`/`null`) | byte-identical | — | 2.0.0 |
| `WebUIDiff.Line.kind: String` | `kind: DiffLineKind` (`context`/`added`/`removed`/`header`) | byte-identical | — | 2.0.0 |
| `WebUITerminal.Line.kind: String` (default branch) | `kind: TerminalLineKind` (`plain`/`ok`/`warn`/`error`; `plain` is the unstyled line) | byte-identical | — | 2.0.0 |
| `WebUIDonut.Slice.color: String` raw hex (`#6366f1`) | `color: ChartColorSlot` (`c1`…`c8` → `--color-chart-1…8`) | **the one intended byte change of the wave** — raw css leaves the call site | — | 2.0.0 |

the 56 surviving 1.x spellings are: 3 `ControlSize` case names, 5 state case
names, and 48 typealiases across 40 components — all pinned by
`DeprecatedVocabularyTests`, which also proves `WebUICard(variant:)` forwards
to `elevation:` + flags byte for byte.

## wave 2 — the protocol stack and typed escape hatches

wave 2 made "complexity available, never required" structural: `View` has one
requirement, escaping is an explicit act, and classes compose.

| old 1.x spelling | 2.0 spelling | emits | shim that still compiles | removed in |
|---|---|---|---|---|
| `.class("…")` (and the `class:` parameters) **replaced** the content's own classes | `.class(_:)` **merges** — the content's classes survive, in call order, duplicates folded; the typed spellings `ClassName`, `classes(_:)`, `addClass(_:)` say the same thing (`Modifiers.swift:369–389`) | a byte change where call sites previously *relied on* replacement; the wave gates reviewed it block by block | the modifier keeps its name; no replace-escape was ever implemented | 2.0.0 |
| `Raw(_ content: String)` | `Raw(UnsafeMarkup.trusted("…"))` — `UnsafeMarkup` has no public init; `.trusted(_:)` is the only way in | byte-identical | deprecated `init(_ content: String)` + the old `content` property (`Sources/WebUICore/Markup.swift:41,:45`) | 2.0.0 |
| `head:` raw string parameter | `headContent: HeadContent` — the typed builder (`HeadContentBuilder` with `meta(name:content:)`, `og(title:description:image:)`, `jsonLD(_:)`, `link(rel:href:type:)`, `script(src:module:)`, `unsafe(_:)`); scripts keep their nonce until render time | byte-identical for equal content | the raw `String` parameter stays, deprecated | 2.0.0 |
| `dir:` string parameter | `direction: Directionality` (lives in `WebUICore` beside `Raw`; the design system re-exports it as a typealias) | byte-identical | the `String` parameter stays, deprecated | 2.0.0 |
| `View.render() -> String` (the only `View` requirement) | `View: BufferRendering` — the sole requirement is `func render(into buffer: inout HTMLBuffer)`; the flip is all-or-nothing because a kept `render()` would be silently bypassed through `any View`. a `View` only refines `BufferRendering`, whose **public** `markup: UnsafeMarkup` is the materializer — a host no longer hand-rolls `String(decoding: buffer.bytes…)` | byte-identical (a migrated view writes its bytes directly into the buffer) | deprecated `render()` *default* — `render() -> String` is `markup.html`; it is not a way to conform | 2.0.0 |
| (nothing to migrate) | the capability protocols `Identified`, `Recoverable` (`Sources/WebUICore/Capabilities.swift`) — conformance is a one-word change, no capability adds a `View` requirement | — | — | — |
| (nothing to migrate) | consumer `HTMLBuffer` — `init`, `append`, `appendEscaped`, `appendBytes`, `beginElement`, `endOpenTag`, `endElement`, `voidElement`, `addAttribute`, `addAttributeValue`, `byteCount`, `hasPendingAttributes`, `bytes` are public; `BufferRendering.markup` (not on the buffer) is the materializer | — | the modifier plumbing (`mark`, `takePendingAttributes`, `wrapSpan`, `settlePendingAttributes`, `finish`) stays package — `finish()` is the internal boundary that hands the buffer's bytes to `UnsafeMarkup.rendered(_:)`, the framework-vouched variant; making it public would let a host mint framework-trusted markup without taking responsibility, which is exactly what `.trusted(_:)` exists to keep loud. the public door to a rendered value is `markup` | — |

## wave 3 — the web's actual HTTP surface

wave 3 gave the server a typed request/response model, a router, forms and
uploads, streaming and SSE, and typed capability islands. the wave's one
deprecation is the server init; everything else is new surface a 1.x reader
needs to know about.

| old 1.x spelling | 2.0 spelling | emits | shim that still compiles | removed in |
|---|---|---|---|---|
| `WebUIServer(render:router:config:logger:)` | `WebUIServer(router:config:logger:)` — the router is a typed `Route` table and the server owns its `EventRouter` | byte-identical — the deprecated inits stand on a single-route router for `config.pagePath` | `@available(*, deprecated, message: "build a Router and use init(router:config:logger:)")` (`WebUIServer.swift:350`) | 2.0.0 |
| `WebUIServer(requestRender:router:config:logger:)` | same `init(router:config:logger:)` — a path-dependent page is a `Route.page` with `request.path` | byte-identical | `@available(*, deprecated, …)` (`WebUIServer.swift:366`) | 2.0.0 |
| raw render closures returning `String` | `HTTPResponse` (`HTTPResponse.Body`: `.html(_:)`, `.text(_:)`, `.bytes(_:contentType:)`, `.stream(_:contentType:)`) — `.html` now carries an **`UnsafeMarkup`**, so a bare `String` can no longer become a page (the compiler rejects it). a handler that renders a view answers `HTTPResponse(view.markup)` — the `HTTPResponse(_ markup:status:headers:cookies:)` convenience — or `.html(view.markup)`. the 1.x response-body materializer this row once pinned has been **deleted**, not deprecated — see the typed-markup section | — | — | — |
| hand-parsed request plumbing | `HTTPRequest` (method/path/query/headers/cookies/body/`renderToken`/`isSecure`/`params`), `HTTPMethod`, `HTTPStatus`, `RequestBody` (`.none`/`.bytes`/`.form`/`.multipart`) | — | — | — |
| `WebUIAuth.Cookie`, `WebUIAuth.CookieParser` | `WebUISharedCore.HTTPCookie`, `WebUISharedCore.CookieParser` — the Foundation-free shared leaf; `@_exported` from `WebUIServer` | — | deprecated `renamed:` typealiases in `WebUIAuth/Cookie.swift` | 2.0.0 |
| `Router(…)` doesn't exist; paths were the config's single page | `Router(_ routes: [Route])` + `Route.get(_:_:)`, `Route.post(_:_:)`, `Route.page<D: BufferRendering>(_ pattern:content:)`, `PathPattern` (`"/users/:id"`, trailing `*rest`), matching most-specific-first with a computed `specificity`. `Route.page` exists in **both a sync and an async form with the same `content:` label** — the compiler disambiguates on the closure's async-ness, so a trailing closure keeps working — and `PageResponder` is typed on `BufferRendering`, so a document (not a view) serves as a page | — | — | — |
| `Route.page` and `ErrorBoundary.init` took `@ViewBuilder` | plain closures — this package's `ViewBuilder` is array-shaped, so a builder-returned single view is never inferred; build the view first, return it | — | — | — |
| forms | typed `FormMethod` (`.get`/`.post`/`.dialog`) with a raw-string init kept for byte fidelity; `Form(enctype:)`, `Input(accept:multiple:)` for file inputs; `FormValues`/`MultipartForm`/`UploadedFile`/`BodyReader` (`maxBodyBytes` 1 MiB, `maxMultipartParts` 64 — a declared `Content-Length` over the cap is refused before buffering) | — | — | — |
| (nothing to migrate) | chunked streaming: `HTTPStream` + `HTTPResponse.Body.stream(AsyncStream<[UInt8]>, contentType:)`; server-sent events: `SSEEvent` (field values splitLines-guarded) + `SSE.response(_:)` | — | — | — |
| (nothing to migrate) | typed capability islands: `Island`, `IslandRegion`, and `RuntimeConfig(capabilities:)` — declaring an island makes `WebUIDocument` emit `ClientBoot` with those capabilities | — | — | — |
| (nothing to migrate) | `HandlerOutcome` + `HandlerFailurePolicy` (`.silent`/`.log`/`.notifyClient`) and `WebUIServerConfig.handlerFailurePolicy` — the router always reports a failure through the `ObservableEvent` funnel; the policy decides what the client frame says | — | — | — |
| (nothing to migrate) | `WebUIServerConfig.onRenderFailure` — a throwing render/handler is answered as a 500 with the host's error page, never a dropped connection | — | — | — |

## wave 4 — breadth: events, boundaries, media, a11y, i18n

| old 1.x spelling | 2.0 spelling | emits | shim that still compiles | removed in |
|---|---|---|---|---|
| `EventData.data` as a raw dictionary (`[String: String]` in the old docs; actually `[String: JSONValue]`) | the typed readers `string(_:)`, `number(_:)`, `bool(_:)` and the convenience `targetID`, `targetClass`, `value`, `key`, `checked` — **there is no raw-key escape; `bool(_:)` exists and the framework's handlers all read through it** | — | — | — |
| named modifiers only, `HTMLEvent.custom(_:)` unreachable | `View.on(_:perform:)` attaches any `HTMLEvent` including `.custom("dragstart")` | — | — | — |
| (nothing to migrate) | `ErrorBoundary` + `.errorBoundary(_:)`; boundaries catch *failures*, never traps — `STABILITY.md` item 8 states the trap contract | a boundary patch degrades to its fallback; no `onRenderFailure` answers a plain-text 500 | — | — |
| (nothing to migrate) | typed media: `Video`, `Audio`, `Picture`, `Source`, `Track`, `Iframe`, `Canvas` with `TrackKind`, `IframeSandbox` (`.strict` is the **empty** set), `LoadingStrategy`; `sanitizeURL` guards all six src-bearing paths including `Video.poster` — a hostile src drops the element | — | — | — |
| hand-written `aria-*`/`role=` strings in components | typed `Aria`/`AriaRole` (+ `AriaChecked`, `AriaExpanded`, `AriaPressed`, `AriaSelected`, `AriaModal`, `AriaHidden`, `AriaBusy`, `AriaLive`, `AriaCurrent`, …) — the design system emits zero hand-written aria rows | a11y-only byte delta (+1371, proven fragment-by-fragment); the typed surface itself is byte-zero | — | — |
| (nothing to migrate) | `A11yAudit.audit(_:)` → `[A11yFinding]` with the six named rules `buttonNoName`, `imageNoAlt`, `controlNoLabel`, `interactiveNoName`, `headingSkip`, `roleMissingAria` — the framework's own markup is clean; `designer/a11y-audit.mjs` proves the rules fire | — | — | — |
| hardcoded English literals in components | `WebUIStrings` (67 properties; `english` default catalog + an Arabic catalog) resolved through `RenderContext.currentStrings`/`localized`; `WebUIDocument` gains `locale:` (feeds `<html lang>`) and `strings:` | byte-identical — the english defaults ARE the literals they replaced, pinned by the byte gate | — | — |
| `dir:` string | typed `direction: Directionality` on `WebUIDocument` (wins over `dir:`), mirrored in `RenderContext` | byte-identical | `dir:` stays, deprecated | 2.0.0 |
| `aria-valuenow` written from a `String` | `Aria.valuenowDouble(Double)` keeps `aria-valuenow="50.0"` byte-exact for the slider | byte-identical | — | — |

## wave 5 — aesthetics: fully customizable, still typed

wave 5 is additive — the byte pin never moved across it (fourteen gates green,
`168671` unchanged, asserted twice).

| old 1.x spelling | 2.0 spelling | emits | shim that still compiles | removed in |
|---|---|---|---|---|
| `WebUITheme` / `theme:` only | `DesignTheme` (five **mandatory** static axes: `palette`, `spacing`, `radii`, `typography`, `motion` — a conformer that omits one cannot compile), `DefaultDesignTheme`, `DerivedTheme<Base: DesignTheme>` (value-level `init(mode:overrides:)`, statically inheriting `Base`), `TokenOverrides` (`ExpressibleByDictionaryLiteral`), `resolvedPalette`, `.webUITheme(mode:)`, `overriding(_:mode:)`, the `@Theme` conformance macro | additive | existing `theme:` usage keeps working | — |
| hand-rolled theme sheets | `ThemeSheet.init<T: DesignTheme>(theme: T.Type, mode:)` and the `ThemeCatalog` path for cacheable linked sheets | additive | — | — |
| (nothing to migrate) | token completeness, machine-checked in both directions: generated `DesignToken.verify(_ theme: any DesignTheme.Type) -> [MissingToken]` with `.notInStylesheet`/`.misplacedAxis` kinds | — | — | — |
| `rawStyles: [String]` is the only host sheet | `StyleSheet(name:layer:rules:)` with typed `CascadeLayer` (`.webui`, `.utilities = "webui.utilities"`, `.host` — host declared last so it wins by origin), the `CSSRuleBuilder`, and `StyleSheet.css` emitting the canonical `@layer` statement; `WebUIDocument.styleSheets` and `stylesheetURL` (cacheable `<link>` instead of inlining) | additive; a host rule beats the framework at equal *and* lower specificity with zero `!important` (proven in `designer/cascade-probe.mjs` on computed style against a control) | `rawStyles` stays | — |

## the typed markup surface — markup, not render()

(the typed-markup arc, measured against HEAD: the migration tables above were
written against `245eecc`, before the arc landed.)

the arc made `markup` the one door a host reaches a rendered value through, and
removed the two string materializers 1.x trained hosts to call. measured against
HEAD:

- `BufferRendering` is a **public** protocol with `public var markup: UnsafeMarkup`
  (`Sources/WebUICore/BufferRendering.swift`). `View` **refines** it, so `.markup`
  works on any view *and* on `HTMLDocument`, `WebUIDocument` and `CSSStylesheet` —
  a document is not a view, but it sings the same door.
- the two string materializers this document's 1.x rows once named — renderThroughBuffer
  and renderedString — are **deleted**, not deprecated. neither exists at HEAD (0 hits
  tree-wide), so a 1.x host that calls either simply fails to compile. `render() -> String`
  survives only as a **deprecated 1.x spelling**: it is `markup.html`.
- `HTTPResponse.Body.html` now carries **`UnsafeMarkup`**, not `String` — a bare
  `String` can no longer become a page; the compiler rejects it. the convenience
  `HTTPResponse(_ markup:status:headers:cookies:)` answers from a rendered value.
- `HTMLDocument.body` and `WebUIDocument.body` carry **`UnsafeMarkup`**.
- `Route.page<D: BufferRendering>` exists in **both sync and async form, same
  `content:` label** — the compiler disambiguates on the closure's async-ness, so a
  trailing closure keeps working. `PageResponder` is likewise typed on
  `BufferRendering`.
- `UnsafeMarkup.trusted(_:)` is the **one escape hatch** for genuinely hand-written
  markup, and it is greppable by design.
- two public parameters **deliberately stay `String`**: `HTMLDocument.diagnostics(body:)`
  and `WebUIDocument.declaredIslandNames(in:)` — both are pure scans that render
  nothing. do not "fix" them.

### the consumer proof (measured, not invented)

the arc's real consumer — `~/workspace/no-webui-migrate-test` — was built the naive
(1.x) way first, one shape fixed per build so `swiftc` surfaces the next error
class (`naive-diagnostics.md` there records each raw batch). the four error classes
a 1.x host hits, in the order they surface, are the migration:

| shape | the compiler says | the typed door |
|---|---|---|
| document body | `cannot convert value of type 'String' to expected argument type 'UnsafeMarkup'` (`HTMLDocument.init body:`) | `HTMLDocument(body: shell.markup, styles: sheet)` — `View: BufferRendering.markup` → `UnsafeMarkup` |
| route content | `static method 'page(_:content:)' requires that 'String' conform to 'BufferRendering'` | `Router { Route.page("/") { doc } }` — a document, not a view |
| response body | `.html(A String)` rejected — `String` is not `UnsafeMarkup` | `HTTPResponse(doc.markup)` — the `HTTPResponse(_ markup:)` convenience |
| stylesheet served as a page | same rejection on a css `String` body | `HTTPResponse(sheet.markup)` — `CSSStylesheet: BufferRendering`, served typed, no `String` |

the async route changes nothing at the call site: `Route.page("/async-page") {
_ async in … doc }` keeps the same `content:` label, gains only `async`, and the
compiler picks the async overload. the whole consumer reaches served bytes with
zero `String`s materialized and zero calls to `UnsafeMarkup.trusted(_:)`.

## new in 2.0, in one place

the surfaces above are the migration; `STABILITY.md`'s frozen list already
covers the rest. three practical notes for a 1.x host:

- **a document route renders one view.** build the view, return it from
  `Route.page(_:content:)` — its closure is deliberately not `@ViewBuilder`
  (see wave 3).
- **a live page carries its render token.** `HTTPRequest.renderToken` flows
  into `RuntimeConfig(renderToken:)`; a page served with `content="{}"` (no
  token) cannot answer `navigate` or events — `showcase-ws-smoke` pins this.
- **`Text` is a bare text node, not an element.** a grid/flex container that
  renders texts directly has no items to lay out; wrap them in `Span`/`Div`.

## appendix a — the deprecated inventory at HEAD (re-measured)

`grep -rn "@available(\*, deprecated" Sources/ | wc -l` → **79 lines**. of
those, one is a comment mention (`Vocabulary.swift:31`), so 78 are real
`@available(*, deprecated)` markers. the same grep, grouped by file:

| file | markers | what remains deprecated |
|---|---|---|
| `WebUIDesignSystemCore/WebUIComponents.swift` | 28 | the slot typealiases (`Variant`/`Size`/`Tone`/`State`/`Trend`/`Axis`/`StepStatus`), the `appearance:`/`tone:`/`shape:`/`elevation:` forwarding inits, Card's `Variant` enum + `init(variant:)` |
| `WebUIDesignSystemCore/WebUIExtrasNavOverlay.swift` | 15 | `tone:`/`appearance:`/`position:` forwarding inits + the slot typealiases (`SlidePosition`, `DrawerEdge`, `Placement`, `Axis`, `Tone`, `ControlSize`, `Appearance`), the menu `destructive` → `danger` read-through |
| `WebUIDesignSystemCore/WebUIExtrasForm.swift` | 10 | `Size` typealiases, `ValidationState`/`EditState`/`Appearance`/`Brand` typealiases, the tag `appearance:` forwarding init |
| `WebUIDesignSystemCore/Vocabulary.swift` | 8 (+1 comment) | the `ControlSize` case-name statics (`small`/`medium`/`large`) and the state case names (`normal`, `loading`, `failed`, `pending` on their enums) |
| `WebUIDesignSystemCore/WebUIExtrasCommsState.swift` | 8 | `Tone`/`Trend`/`LoadState`/`Presence`/`BubbleSide` typealiases + the banner `tone:` forwarding init |
| `WebUIServer/WebUIServer.swift` | 2 | the two render-closure inits (wave 3) |
| `WebUICore/Markup.swift` | 2 | `Raw(_ String)`, `Raw.content` (wave 2) |
| `WebUIAuth/Cookie.swift` | 2 | the `HTTPCookie`/`CookieParser` renamed typealiases |
| `WebUIDesignSystemCore/WebUIShell.swift` | 1 | `PanelEdge` typealias |
| `WebUIDesignSystemCore/WebUIExtrasData.swift` | 1 | `Brand` typealias |
| `WebUICore/View.swift` | 1 | the `render()` default (wave 2) |

## appendix b — how this document was verified

every backticked symbol above was grepped against the tree at `245eecc`
(`sources`, `tests`, `plugins`, `designer`, `skills`, `Package.swift`); the
symbol gate script resolved every token (see the wave-6 run record). sampled
labelled-parameter census that killed the plan's false row: `emphasis:`
**0** hits tree-wide; `appearance: Appearance` 6 hits (button/tag/accordion
inits + their assignments); `tone: Tone` 14 hits in `WebUIComponents.swift`
alone; `variant: Variant` exactly 1 (Card's deprecated init). the byte pin
re-renders at exactly 168671 bytes. the wave gates: `swift test` 1396/0,
`smoke` 19/0, `fullstack-smoke` 24/0, `browser-smoke` 50/0,
`showcase-ws-smoke` 9/0, `blocks-sweep` 107/0, `chart-mobile-audit` 77/0,
`rtl-audit` 54/0, `acceptance-demo` 8/0, `event-deck-probe` 33/33 · 32/32 ·
35 other / 0 fail, `a11y-audit` 26/0, `cascade-probe` 12/0,
`theme-default-probe` 40/0, `engine-theme-default-probe` 5/0.

this document is the contract for the 2.0 cut: a 1.x host should be able to
compile against it, row by row, with the shims in appendix a as the running
bridge across the one minor of deprecation.
