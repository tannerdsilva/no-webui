# API Reference

## WebUI

### View Protocol

| Protocol | Requirement | Notes |
|---|---|---|
| `View` | `func render(into buffer: inout HTMLBuffer)` | the **sole requirement** since the 2.0 flip: writes this view's bytes into a shared render buffer. a requirement deliberately — an extension method would resolve statically, so a view's own implementation would never run through `any View`; the dispatch is pinned by `RenderIntoBufferTests` |
| `View` | `func render() -> String` | **deprecated extension default**: `markup.html`. existing call sites keep compiling and rendering identically — the deprecation is the migration signal. it is not a way to *conform*: a type that implements only `render() -> String` does not satisfy the protocol |
| `BufferRendering` | `var markup: UnsafeMarkup` | the materializer: renders this value's bytes into an `UnsafeMarkup` the framework vouches for. `View` refines `BufferRendering`, and so do `HTMLDocument`, `WebUIDocument` and `CSSStylesheet` — a document is not a `View`, but it sings the same door |
| `ViewModifier` | `func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer)` | the **sole requirement**: apply the modifier by writing into the render buffer — `buffer.mark`, contribute an attribute or register a handler, render the content, `settlePendingAttributes(from:)`. one implementation per modifier, and both doors are that behaviour |
| `ViewModifier` | `func apply(to html: String) -> String` | **derived extension, not a requirement**: decorates already-finished html through the buffered door, so it agrees byte for byte with `injectAttributes(into:_:)` — the oracle `ModifierDecorateTests` checks it against. `ModifierContractPinTests` pins that only `AnyViewModifier` and `IconSizeModifier` pay a round-trip, and that `apply` is declared in exactly one place |
| `ModifiedView<Content: View, M: ViewModifier>` | `View` | type-preserving wrapper returned by every modifier |
| `EmptyView` | `View` | renders nothing |

the buffer is a real consumer surface now: `HTMLBuffer` is a `public` type
with **13 public members** — `init(capacity:)`, `append`, `appendEscaped`,
`appendBytes`, `beginElement`, `endOpenTag`, `endElement`, `voidElement`,
`addAttribute`, `addAttributeValue`, `byteCount`, `hasPendingAttributes`,
`bytes` — and the modifier plumbing (`mark`, `takePendingAttributes`,
`wrapSpan`, `settlePendingAttributes`, `finish`) stays `package`. migrating a
1.x conformer: implement `render(into:)`. a 1.x view that implemented only
`render() -> String` does **not** compile against the 2.0 protocol — there is
no default for the requirement (a kept `render()` would be silently bypassed
through `any View`). see `Documentation/MIGRATION_2_0.md` (wave 2) for the
flip and the shim.

### ViewBuilder / ElementBuilder

two result builders, chosen by the parameter's attribute — a call site never
names one.

- `@ViewBuilder` — the block becomes `[any View]`. used by the design-system
  components, which count and enumerate their children to decide markup.
- `@ElementBuilder` — the block becomes concrete views (`TupleView`,
  `OptionalView`, `EitherView`, `RepeatedView`, `ErasedViews`). used by
  `ForEach` and every container primitive, which only forward their children.

same call-site syntax either way; the difference is one array versus a typed
tuple. `Documentation/DESIGN_NOTES.md` records the measurement behind the split.

### Primitives

| Type | Initializer | Notes |
|---|---|---|
| `Text(_ content: String)` | escaped | plain text, html-escaped |
| `Raw(_ content: String)` | unescaped | escape hatch — content goes through verbatim |
| `Div` / `Span` | `id:class:content:` | generic containers |
| `Button(_ label:, id:class:type:disabled:name:)` | escaped label | `ButtonType` = `.submit/.button/.reset` |
| `Input(id:name:placeholder:type:value:disabled:required:attributes:)` | escaped | `InputType` — 22 html input types |
| `Image(src:alt:class:loading:decoding:)` | sanitized src | `ImageLoading`/`ImageDecoding` enums |
| `Link(_ text:, href:class:target:rel:)` | sanitized href | `LinkTarget` enum, `LinkRel` option set |
| `Heading(_ text:, level:class:)` | escaped | `HeadingLevel` = `.h1`…`.h6` |
| `Paragraph`, `Label`, `TextArea`, `Select`, `Table`, `Form` | escaped | `SelectOption.value/label` |
| `ForEach<Data: RandomAccessCollection, Content: View>` | — | renders each element; one concrete view per element (typed `@ElementBuilder`), no wrapper |
| `Group` | — | renders children without a wrapper |
| `WebUIIcon(_ name:, size:, title:)` | escaped title | inline svg from the generated `IconName` catalog; `currentColor` |
| `WebUIIconCustom(name:body:size:title:)` | sanitized body | caller-supplied svg geometry (see the WebUIIcon section) |

every attribute parameter (`id`, `class`, `name`, `for`, `data-status`,
`Form.method`, …) is html-escaped before emission. url-valued parameters
(`Link.href`, `Image.src`, `Form.action`) pass through `sanitizeURL` first.

### Forms

`Form(action:method:id:class:csrfToken:content:)` renders a `<form>`. `method` is a
typed `FormMethod` — `.get`, `.post`, `.dialog` — defaulting to `.post`. the
raw-string spelling (`method: "post"`) is still accepted and still emits verbatim.

**the default does not work against `WebUIServer`.** the shipped server answers `GET`
only; every other method gets a `405` whose body points here. a
`<form method="post">` is correct only when the page runs the js runtime *and* the
form has an `.onSubmit` handler — the engine then intercepts the submit and sends an
event over the websocket instead of letting the browser post. with no render context
there is nothing to intercept, and the browser posts for real.

the framework warns **once per process** when it renders a `method="post"` form with no
render context, naming this section.

| you want | write |
|---|---|
| a live, server-handled form | `Form(action: "/save") { … }.onSubmit { … }`, served through `WebUIServer` |
| an ordinary navigation | `Form(action: "/search", method: .get) { … }` |
| a dialog closer | `Form(method: .dialog) { … }` inside a `<dialog>` |

real `POST` — bodies, uploads, redirect-after-post — lands in **W3**
(`CHANGELOG.md`). until then, `GET` plus websocket events is the supported path.

`csrfToken:` emits a hidden `_csrf` input; see **CSRF Protection** below.

### Layouts

| Type | Initializer | Output |
|---|---|---|
| `VStack` / `HStack` | `alignment:spacing:content:` | `.vstack/.hstack spacing-N align-X` divs |
| `ZStack` | `alignment:verticalAlignment:content:` | `.zstack` grid overlay — children overlap via `.zstack > *` (shipped in `LayoutStyles.complete`) |
| `Spacer(minSize:)` | — | `flex:1` div |
| `ScrollView` | — | `.scrollview` div |
| `Grid(columns:spacing:content:)` | `GridColumns` | inline `display:grid` |

`GridColumns` cases:

| Case | Emits |
|---|---|
| `.fixed(n)` | `repeat(n, minmax(0, 1fr))` — grid-safe equal tracks |
| `.fraction(n)` | `repeat(n, 1fr)` |
| `.minmax(a, b)` | `repeat(auto-fill, minmax(a, b))` |
| `.autoFill(n)` / `.autoFit(n)` | `repeat(auto-fill, minmax(npx, 1fr))` — n is the minimum track size in px |
| `.custom(String)` | passthrough |

### Modifiers

| Method | Effect |
|---|---|
| `.font(size:weight:)` | `style="font-size:Npx;font-weight:W"` — `weight` accepts `FontWeight` or `String` |
| `.textAlign(_ alignment:)` | `style="text-align:..."` — accepts `TextAlignment` or `String` |
| `.foregroundColor(_ color: String)` | `style="color:..."` |
| `.foregroundColor(_ token: ColorToken)` | `style="color:var(--color-...)"` |
| `.backgroundColor(_ color: String)` | `style="background-color:..."` |
| `.padding(_ value: Int)` | `style="padding:Npx"` |
| `.padding(_ token: SpaceToken)` | `style="padding:var(--space-N)"` |
| `.cornerRadius(_ value: Int)` | `style="border-radius:Npx"` |
| `.width(_ value: String)` | `style="width:..."` |
| `.height(_ value: String)` | `style="height:..."` |
| `.class(_ name: String)` | `class="..."` — **replaces** classes the view already emits (the later value wins in the attribute merge; `.class` on a `VStack`/`WebUICard` drops its `vstack`/`card__body` classes). wrap the view in `Div(class:)` to add one |
| `.id(_ id: String)` | `id="..."` |
| `.attribute(_ key: String, _ value: String)` | emits `key="value"` on the root element (e.g. `data-prevent-enter="false"`) |
| `.showIf(_ condition: Bool)` | `display:none` when false |
| `.onClick(_ handler:)` | `data-component-id="cN" data-event="click"` (auto-allocated id) |
| `.onClick(id: String, perform: handler)` | `data-component-id="<id>" data-event="click"` — **stable** id you choose; registers under that id so re-rendered fragments keep routing (use for interactive regions like tables) |
| `.onSubmit(_ handler:)` | `data-component-id="cN" data-event="submit"` |
| `.onInput(_ handler:)` | `data-component-id="cN" data-event="input"` |
| `.onChange(_ handler:)` | `data-component-id="cN" data-event="change"` |
| `.onFocus(_ handler:)` | `data-component-id="cN" data-event="focus"` |
| `.onBlur(_ handler:)` | `data-component-id="cN" data-event="blur"` |
| `.onFocusIn(_ handler:)` | `data-component-id="cN" data-event="focusin"` |
| `.onFocusOut(_ handler:)` | `data-component-id="cN" data-event="focusout"` |
| `.onKeyDown(_ handler:)` | `data-component-id="cN" data-event="keydown"` |
| `.onKeyUp(_ handler:)` | `data-component-id="cN" data-event="keyup"` |
| `.onKeyPress(_ handler:)` | `data-component-id="cN" data-event="keypress"` |
| `.onMouseDown(_ handler:)` | `data-component-id="cN" data-event="mousedown"` |
| `.onMouseUp(_ handler:)` | `data-component-id="cN" data-event="mouseup"` |
| `.onMouseOver(_ handler:)` | `data-component-id="cN" data-event="mouseover"` |
| `.onMouseOut(_ handler:)` | `data-component-id="cN" data-event="mouseout"` |
| `.onOptimisticClick(predict:perform:)` | click + `data-optimistic="{json prediction}"` — client patches before the round-trip, confirms on update, rolls back on timeout |
| `.onDismiss(_ handler:)` | `Dismissible` views (`WebUIAlert`/`WebUIToast`/`WebUIModal`/`WebUIChip`) — wires the close button as a routed component; handler receives `(ElementRef, EventData)` targeting the component's own root |
| `controlAttributes(id:event:handler:)` | free function for component authors: register a handler under a caller-stable id and emit `data-component-id`/`data-event`. registers when a `RenderContext` is present; re-emits the stable id on context-free fragment re-renders so page-build registrations keep routing |
| `.onSort(_:)` / `.onSelectAll(_:)` / `.onSelect(_:)` / `.onToggleExpand(_:)` | `WebUITable` typed handlers — self-wire each sort header / select-all / row-select / expand button as a routed component; receive typed payloads (`column`, `rowID`) + an `ElementRef` to the table root |
| `.onPageChange(_:)` / `.onRowsPerPageChange(_:)` | `WebUIPagination` typed handlers — prev/next/number buttons and the rows-per-page select are routed components; receive the computed page / parsed size + an `ElementRef` |
| `.onSelectMark(_:)` | `WebUIChart` typed handler — each painted bar/sector is a routed component; receives the clicked category + an `ElementRef` to the chart root |

### Event Handling

| Type | Description |
|---|---|
| `EventData` | `{ component: ComponentID, event: String, data: [String: JSONValue] }` — **not** `[String: String]`. read flat fields through `event.string(_:)` / `event.number(_:)`; structured values (search terms, row ids) arrive as `JSONValue` and are read through it. `click` data carries `targetId` and `targetClass` of the clicked element |
| `EventHandler` | `@Sendable (EventData) async -> [FragmentUpdate]` |
| `OutcomeHandler` | `@Sendable (EventData) async throws -> HandlerOutcome` — a handler that can answer with a redirect, a client-state write, a reload or a failure, and may throw. a throw becomes `HandlerOutcome.fail(code: "handler", …)`; register a fallback with `register(fallback:for:)` to keep the control usable. register with `register(outcome:for:)` / `controlAttributes(id:event:outcome:)` |
| `EventRouter` | routes events to registered handlers. `maxHandlers: Int` (default 10,000), `handlerCount: Int`. one router per render pass — call `reset()` before rendering a fresh page. `begin(_:preservingRegistrations:)` starts a render pass, resetting the session; `preservingRegistrations: true` keeps the handlers and fallbacks it already holds and restarts only the mint counters — the in-place re-render shape the server's `navigate` answer uses, so handlers a host registered outside a render pass survive it. the default (`false`) is the original reset. note the signature moved from `begin(_:)` to `begin(_:preservingRegistrations:)` (defaulted, so source-compatible) |
| `RenderContext` | `@TaskLocal` context providing component ID generation, element ID minting, and handler registration |
| `ComponentID` | hashable/codable string wrapper for component ids |
| `ElementRef.stable(_:)` | framework-facing factory for a ref to an element with a caller-chosen stable id (minted by typed component handlers for their root). callers should keep receiving refs rather than fabricating them |
| `ElementRef` | typed handle to a rendered element minted by the framework. `remove()` → empty-html fragment (the runtime removes the element), `replace(with:)` → outerHTML swap, `update(view)` → re-render from a `View`. no caller-supplied ids |
| `Dismissible` | protocol for views with a dismiss/remove affordance. `.onDismiss { me, _ in }` wires the close button to a routed component and receives the root `ElementRef` |
| `FragmentUpdate` | `{ id: String, html: String }` — DOM patch instruction. `html: ""` removes the element (pinned contract, see the engine's fragment patcher) |
| `SpaceToken` | spacing-scale tokens (`.one`…`.twentyFour`) → `var(--space-N)` |
| `ColorToken` | nexus color tokens (`.primary`, `.text`, `.danger`, …) → `var(--color-...)` |
| `FontWeight` | `.thin` … `.black`, `.custom(_:)` → numeric `font-weight` |
| `TextAlignment` | `.left`, `.center`, `.right`, `.justify` → `text-align` |
| `RuntimeConfig` | typing knobs for the js runtime — `wsUrl`, `wsReconnect`, reconnect/ping/pong/debounce/optimistic timings, `logLevel` |

### Observability

| Type | Description |
|---|---|
| `ObservableEvent` | enum with 9 cases: viewRendered, eventReceived, eventHandled, fragmentSent, websocketConnected/Disconnected/Error, error, debug. the framework itself emits eventReceived, eventHandled, and debug (from `EventRouter`); the rest are extension points for adopters whose transport/render layer emits them |
| `ObserverList` | thread-safe collection (`Synchronization.Mutex`-backed, no Foundation) of `Observable` conformers. `maxObservers: Int` (default 100), identity-deduped registration, warning on cap rejection, strong retention until `remove(_:)` |
| `Logger.emit(_:observers:)` | logs an event and notifies observers |

### HTML Document

| Type | Parameters | Description |
|---|---|---|
| `HTMLDocument` | title, body, styles, rawStyles, scripts, contentSecurityPolicy, contentSecurityPolicyExtras, includeRuntime, runtimeConfig, devMode, head, bodyAttributes, lang, preMinifiedStyles, stylesheetURL, themeStylesheetURL, inlinedComponentStyles | complete HTML document with auto-generated CSP and nonce. shipped css is minified (comments + blank lines stripped) unless `preMinifiedStyles: true` embeds the caller-provided combined sheet verbatim (used by `WebUIDocument`'s hoisted sheet) |
| `WebUIDocument` | same as HTMLDocument | HTML document with the full design system css — the record sheet (layout rules + embedded css) is minified once into `WebUIDocument.minifiedDesignStyles` and embedded verbatim on every render (`preMinifiedStyles: true`), removing the old per-render minify of ~350 kb css (~11 ms in release → <0.01 ms) |

`contentSecurityPolicyExtras` is the seam for a host that needs one more directive than
the policy it would otherwise get: its directives are **merged per name** into the
effective policy (the nonce-aware default, or `contentSecurityPolicy` when that is set),
so an extra replaces the default's directive of the same name and everything else —
including the render nonce — is carried over. restating the whole policy instead names no
nonce source, and `HTMLDocument` then suppresses the pre-paint theme prelude rather than
emit an inline script the browser refuses.

`runtimeConfig` (a `RuntimeConfig?`) changes only the boot config: with a
non-empty config the page emits a `webui-config` meta carrying it; with no config
the meta carries `{}` and the engine boots with its defaults.

`RuntimeConfig` keys: `wsUrl`, `wsReconnect`, `wsMaxReconnectDelay`,
`wsPingInterval`, `wsPongTimeout`, `maxQueueSize`, `debounceInputMs`,
`debounceMaxWaitMs`, `optimisticSettleMs`, `logLevel`, `renderToken`,
`capabilities`, and `persistence`. the
`renderToken` (a per-render id minted by the server) is echoed back with every
websocket `event`/`ping` so a server that mints tokens can route each message
to the page's router and reject stale pages from other sessions — see
`WebSocketProtocol` and the auth docs. only keys that are set are emitted;
string values are hand-escaped into safe json string literals.

`capabilities` is the grade the engine checks before fetching an island
artifact (`/__assets/webui-<name>.wasm`): a capability not granted by a page
is never fetched. it is usually not set by hand — declaring an
`IslandRegion<I>` makes `WebUIDocument` collect `I.name` out of the body and
fold it into this list (see `Island`).

`stylesheetURL` and `themeStylesheetURL` are the two sheet slots, emitted in that
order *before* the inline `<style>`: the base sheet (the design-system component css)
first, then a sheet that must win collisions — same specificity, later source order,
which is why that slot exists rather than a `<link>` in `head:` (a `head` sheet
renders *before* the base sheet and silently loses the collisions).

`body` (on both `HTMLDocument` and `WebUIDocument`) carries **`UnsafeMarkup`**, not
`String` — pass a rendered value's `.markup` (`HTMLDocument(body: view.markup)`), or
for genuinely hand-written bytes wrap them once with `UnsafeMarkup.trusted(_:)`. the
two seams below, however, deliberately take `String`: `HTMLDocument.diagnostics(body:)`
and `WebUIDocument.declaredIslandNames(in:)` are pure scans that render nothing, so
they read the rendered html directly. do not "fix" them.

`HTMLDocument.diagnostics(body:head:stylesheetURL:inlinedComponentStyles:)` answers,
purely and without logging, which wiring misconfigurations apply to a document;
`render()` logs each through the `webui.document` logger, unconditionally rather than
only in debug builds — the failure mode is silent (markup renders "fine" while
individual glyphs detonate):

| diagnostic | condition |
|---|---|
| `.headStylesheetWithoutBaseStylesheet` | `head:` carries a stylesheet link while `stylesheetURL:` is nil |
| `.frameworkMarkupWithoutStylesheet` | the body emits framework icon markup (`class="icon"`) while `stylesheetURL:` is nil |

a host that inlined the component sheet itself (`rawStyles` carries
`DesignSystemAssets.minifiedCss`) sets `inlinedComponentStyles: true` to suppress the
missing-sheet diagnostics — `WebUIDocument`'s inline mode (`stylesheetURL: nil`) does
exactly that.

### Client Mode (wasm)

client-mode pages flip with one argument:

- `ClientBoot(wasmURL:mode:config:scriptURLs:)` — the boot configuration.
  `config` carries only-set `RuntimeConfig` knobs (transport knobs stay
  js-owned; behavior knobs ride the emitted `webui-config` meta).
  `ClientBoot.defaultCSP` is the policy (`'self'` + `'wasm-unsafe-eval'` for
  capability islands, never `'unsafe-inline'` in script-src).
  `ClientBoot.defaultEngineScriptURL` is `/ui/webui-engine.js`.
- `HTMLDocument(…, clientMode: ClientBoot?)` and
  `WebUIDocument(…, clientMode: ClientBoot?)` — `.none` (default) is
  byte-identical to legacy output; a boot emits the `webui-config` meta plus the
  engine script and suppresses the inline server runtime (an explicit
  `contentSecurityPolicy` still wins; `contentSecurityPolicyExtras` extends whichever
  policy applies without losing its nonce). the wasm *client* mode this parameter
  also described was deleted; wasm is per-page capability islands now.

### CSS

| Type | Description |
|---|---|
| `CSSRule(_ selector: String, _ declarations: [CSSDeclaration])` | a single CSS rule |
| `CSSStylesheet(_ rules: [CSSRule])` | a collection of rules, renders to a `<style>` block |
| `CSSMediaQuery`, `CSSKeyframes`, `CSSFontFace` | at-rule renderers |
| `LayoutStyles` | layout sheet: `.vstack/.hstack/.zstack/.zstack > */.spacer/.scrollview/.grid` + spacing/alignment classes via `.complete` |
| `minifyCSS(_ css: String) -> String` | strips `/* */` comments, trims lines, drops blank lines — applied to shipped page css |

### Utilities

| Function | Description |
|---|---|
| `htmlEscape(_ string: String) -> String` | escape HTML special characters (&, <, >, ", ') |
| `Base64` | data-free rfc 4648 base64/base64url over `[UInt8]`: `encode`/`decode` (standard, `=` padding), `encodeURL`/`decodeURL` (url alphabet, no padding; decode tolerates missing padding, rejects invalid bytes) — replaces `Foundation.Data` base64 |
| `JSONValue` | data-free rfc 8259 json value: `parse(_ text:)` (strict; rejects trailing tokens, unescaped control chars, malformed numbers, lone surrogates, and container nesting beyond 128 via `JSONError.nestingTooDeep` — bounds the recursion depth of a wire frame), `serialize()` (compact, integral numbers without `.0`), `escapeString(_:)` — replaces `JSONEncoder`/`JSONDecoder`/`JSONSerialization` on `Data` |
| `WSIncoming(jsonText:)` / `WSIncoming(jsonBytes:)` | data-free decode of a `{"type":...}` client message (throws `WSMessageError.malformed`). `event` messages carry
`component`, `event`, `data`, and an optional `token`; `ping` carries an
optional `token` — the per-render ws binding id servers may mint and check
(absent for servers that do not use it). the 128-container nesting cap
(`JSONError.nestingTooDeep`) applies to this wire path; the Codable
conformance decodes through the underlying decoder's own bounds (the shipped
servers use the capped path) |
| `WSOutgoing.jsonText` / `jsonBytes` | compact data-free emission of a server message |
| `constantTimeEquals(_ lhs:, _ rhs:)` | constant-time equality over byte sequences (any `Sequence` of `UInt8`, e.g. `[UInt8]`) — no early exit on an equal-length input; used for MAC and token compares |
| `DesignSystemAssets.minifiedCss` | `WebUIAssets.css` minified once — what the reference servers serve on `/__assets/css` (comment-free; the raw working file with designer notes never ships). `DesignSystemAssets.prewarm()` eagerly initialises both hoisted sheets at startup |
| `ConnectionGate` | Mutex-backed admission counter for concurrent connections (`tryAcquire`/`release`/`activeCount`). the reference servers acquire it in the child channel initializer — before any request or upgrade negotiation — so bare connect-only sockets count toward `--max-connections` (default 256) and a connect-flood cannot sidestep the cap; slots return on channel close |
| `injectAttributes(into html: String, _ attributes: String) -> String` | inject attributes into the first HTML tag |
| `sanitizeURL(_ url: String) -> String?` | nil for `javascript:`, `data:`, `vbscript:` — strips c0 controls and ascii whitespace first, matching the browser's URL parser, so padded/obfuscated schemes are caught too |
| `markdownToHTML(_ markdown: String) -> String` | minimal safe markdown subset: atx headings, bullet/numbered lists, `**bold**`, `*emphasis*`, `` `code` ``, `[label](url)` (url-sanitized). input is escaped before tokenizing; unpaired delimiters render literally |
| `highlightCode(_ code: String, language: String) -> String` | safe escape-only output — an honest stub until a real lexer lands; never emits raw code |
| `inlineSVG(viewBox:width:height:_ content: String) -> String` | create inline svg element |
| `attrIf(_ name: String, _ value: String, _ condition: Bool) -> String` | conditional HTML attribute |
| `classIf(_ className: String, _ condition: Bool) -> String` | conditional CSS class |

### CSRF Protection

| Method | Description |
|---|---|
| `CSRFProtection.generateSecret() throws -> String` | 32-byte random server secret; throws on entropy failure (no prng fallback) |
| `CSRFProtection.token(for:secret:maxAge:now:) throws -> String` | HMAC-SHA256 stateless token. `maxAge` and `now` are `Epoch` (unix seconds — the framework's one time representation); `now` is an injectable argument, not a stored clock, so a test pins expiry without sleeping. throws on entropy or signing failure |
| `CSRFProtection.validate(_:for:secret:now:) -> Bool` | validate token (signature + expiration); false on any failure, including signing errors — never co-signs an empty signature |
| `CSRFProtection.expiry(of:) -> Epoch?` | the embedded expiry of a well-formed token, or `nil` when it does not decode to `formID:expiry:nonce:signature` |

### Capability Islands

pure-Swift logic that compiles into a small standalone wasm module and is
fetched lazily by a page that declares the capability.

| Type | Members | Description |
|---|---|---|
| `Island` | `static var name: String`, `static func render(_ input: String) -> String` | the capability contract: `name` wires to the grant (`/__assets/webui-<name>.wasm` is fetched only for a granted name), and `render(_:)` is the same Swift on both sides — it compiles into the wasm's `webui_render_region` export and runs server-side for the region's first-render fallback |
| `IslandRegion<I: Island>` | `init(_ input: @autoclosure () -> String)` | declares the capability and mounts the region; renders the engine's mount point (`data-webui-island="<I.name>"` + a JSON-escaped `data-webui-args` envelope carrying the input under `input`) plus the server-rendered fallback |

declaring an `IslandRegion<I>` is the whole wiring: `WebUIDocument` collects
`I.name` out of the rendered body and folds it into the emitted
`RuntimeConfig.capabilities`, so the engine's existing lazy fetch grants and
mounts the region with no manual capabilities entry. an absent artifact
degrades to the fallback markup (`data-webui-island-state="unmapped"`).

build the artifact with
`swift package --disable-sandbox plugin wasm-island --product TheirIsland` —
see `Documentation/ARCHITECTURE.md` layer 5.

## WebUIDesignSystem

### WebUIDocument

`HTMLDocument` variant that ships the design system: the shared sheet
(`designer/assets/design-system.css`, 174 `:root` custom properties, wrapped in
`@layer webui, webui.utilities`) plus `LayoutStyles.complete`, minified once into
`DesignSystemAssets.minifiedCss` and linked (or inlined) as the content-addressed
`/__assets/css.<sha256>`. the served bytes carry no comments. see
`Documentation/DESIGN_SYSTEM.md` for the cascade, the token catalog, and the
theming surface.

because every framework rule is layered, **a page's own css wins without
specificity games**: `rawStyles`, an app stylesheet, and the theme sheet are
unlayered, so they outrank the framework by cascade origin — `!important` and
selector-weight escalation are never required.

`stylesheetURL` defaults to the content-addressed design-system sheet
(`DesignSystemAssets.stylesheetURL`), so a `WebUIDocument` page is styled out of
the box; core `HTMLDocument` defaults it to nil (it takes no design-system
dependency) — a host on the core path wires both sheets itself, and gets a
logged diagnostic when it does not. `themeStylesheetURL` is the slot for a host
sheet that must win collisions against the base.

accepts `theme: WebUITheme = .standard` — a themed document appends the theme's
css (`:root` overrides + app rules, unlayered) after the design sheet.
`.standard` (the default) contributes nothing and renders byte-identical to the
unthemed document.

accepts `checkClasses: Bool = false` — when true the rendered document is
scanned against the shipped sheet and every undefined class is routed through
`HTMLClassValidator.onUndefined` (a dev-time guardrail: a typo'd class
currently renders silently unstyled). see the `HTMLClassValidator` section
below for registering inline-styled class families (e.g. `chart__*`) and
allowlisting page-scoped classes.

### HTMLClassValidator

dev-time guardrail for the string seam: answers "which classes on this html
are not defined in the shipped sheet".

| API | Role |
|---|---|
| `HTMLClassValidator.definedClasses(css:)` | every class selector the sheet declares (cached; explicit `css` bypasses the cache) |
| `HTMLClassValidator.undefinedClasses(in:extra:)` | class tokens on `class="…"` attributes that are neither in the sheet, nor matching a registered prefix, nor in `extra` |
| `HTMLClassValidator.report(html:extra:)` | run the scan and route each undefined class through `onUndefined` once; returns the report |
| `HTMLClassValidator.onUndefined` | `@Sendable (String) -> Void` hook hosts wire to their logger or a test assertion |
| `HTMLClassValidator.registerKnownPrefix(_:)` | mark a family as framework-defined (inline-styled, no sheet rules). the `chart__*` prefix is pre-registered |

### Theme

per-page (or per-scheme) custom aesthetics on top of the shipped design system,
without a fork of the framework css. the emitted theme css is **unlayered**: it
outranks the layered base sheet, and in turn loses to the app's own css.

| Type | Role |
|---|---|
| `DesignToken` | generated enum of the 174 `:root`-scoped tokens from `design-system.css` (the only custom properties a later `:root` override can restyle). **generated into the wasm-clean `WebUIDesignSystemCore` target** (`DesignTokens+Generated.swift`) so the client build can reference it without rawdog. case name = camelCased css name (`color-primary-solid` → `.colorPrimarySolid`), `rawValue` = the exact kebab name, `cssVariable` = `--<rawValue>`. component-scoped custom properties (`.btn { --btn-bg: … }`) are excluded by construction — restyle those via a theme's `rules`. |
| `ThemeMode` | `.automatic` / `.light` / `.dark`. a fixed mode emits `color-scheme:`; `.automatic` emits nothing and follows the OS. (renamed from `ColorScheme` — which is the name an app gives its *own* scheme type.) |
| `ThemePalette` | one mode's overrides: `tokens: [DesignToken: String]` + `customTokens: [String: String]` (app-invented `--name` keys). `.overlaying(_:)` merges per key. |
| `WebUITheme` | `palette`, `dark` (the dark override palette), `defaultMode`, `rules: [CSSRule]` (escape hatch, last resort), `aliases: [TokenAlias]`. `.standard` is the empty theme; `.overlaying(_:)` merges per palette; `stylesheet(scope:)` renders deterministically (declarations sorted by css name, so the bytes are stable and cacheable). |
| `ThemeScope` | `.root` (one theme on `:root`, the default) or `.attribute(id:)` (scoped to `:root[data-scheme="<id>"][data-theme="light\|dark"]`, so one page can ship every scheme). |
| `TokenAlias` | `TokenAlias("--bg", .colorBg)` — an app's own property name bound to a token; emits the indirection `--bg: var(--color-bg)`, so a token override updates every alias and a typo is a missing enum case. |
| `WebUIThemeProvider` | protocol with `static var theme: WebUITheme` plus identity (`themeID`/`themeLabel`/`themeSwatch`, all defaulted), so a hand-written conformer compiles for free. |
| `ThemeCatalog` | `static var all: [any WebUIThemeProvider.Type]` + `static var defaultTheme`, with `entries` / `stylesheet()` / `theme(for:)` rendering the whole set — what a client-side switcher renders from. |
|| `@Theme` | attached macro: turns a struct of `static let` members into a `WebUIThemeProvider`. reserved members `palette`, `dark`, `defaultMode`, `rules`, `customTokens` map to the axes of `WebUITheme`; every other `static let <name> = <value>` is a token override whose member name must be a `DesignToken` case (compile error otherwise). `@Theme(base: Other.self)` layers the declared overrides over another provider, per palette. |
|| `@Wired` | peer marker (empty expansion) on an `async` handler func returning `[FragmentUpdate]`; the enclosing `@WireGroup` member macro reads the markers and emits one `router.register(...)` per handler, in declaration order, under `wireGroup_<name>(_ router:)`. duplicate id inside a group is a compile error; non-func, non-`async`, or wrong-return are diagnostics. |
|| `@WireGroup` | member macro generating one `wireGroup_<name>(_ router:)` registrar on the host (struct, class, or extension) from the `@Wired`-annotated func members it sees. group name must match `[a-z][a-z0-9_]*`; an empty group warns. one registration per annotated handler, declaration order. |
|| `@HTMLComponent` | member macro on a `struct` that replaces the three-initializer + private `Content`-enum ceremony with one attribute declaration: one init per content case, every stored property a shared parameter (order and defaults preserved), computed properties skipped. at most one `.builder` (trailing, `@ViewBuilder`). |

```swift
import WebUI
import WebUIDesignSystem

@Theme(base: NexusBase.self)
struct Poseidon {
    static let defaultMode = ThemeMode.dark
    static let colorPrimarySolid = "#268BD2"
    static let customTokens = ["--chat-user-bubble": "#2a2a2e"]
    static let rules: [CSSRule] = [CSSRule(".chat-bubble", [CSSDeclaration("border-radius", "8px")])]
    static let aliases = [TokenAlias("--bg", .colorBg)]
}

let page = WebUIDocument(body: VStack { Text("hello") }.markup, theme: Poseidon.theme)
```

a dynamic overlay rides on top of a static theme:

```swift
let doc = WebUIDocument(
    body: VStack { Text("hello") }.markup,
    theme: Poseidon.theme.overlaying(
        WebUITheme(palette: ThemePalette(tokens: [.colorPrimarySolid: userAccent]))
    )
)
```

a scheme *set* ships as a catalog, and the catalog serializes to the client as
data (`WebUITheme`/`ThemePalette`/`ThemeEntry` are `Codable`):

```swift
enum SchemeCatalog: ThemeCatalog {
    static var all: [any WebUIThemeProvider.Type] { [Poseidon.self, …] }
    static var defaultTheme: any WebUIThemeProvider.Type { Poseidon.self }
}
```

`.standard` contributes nothing: a page themed `.standard` renders byte-identical
to an unthemed one. catalog integrity (unique ids, a default that is a member,
every `base` resolving) and the emitted scope shape are pinned by the theme
suites.

### Components

| Component | Key Parameters |
|---|---|
| `WebUIButton` | label, variant (.primary/.secondary/.outline/.ghost/.danger/.success/.warning), size (.sm/.md/.lg), disabled, loading, fullWidth, onTap (typed handler — self-wires under `id`, survives re-renders) |
| `WebUIInput` | placeholder, state (.normal/.error/.success/.warning), disabled, id, type, label, helpText |
| `WebUICard` | variant (.elevated/.outlined/.flat/.interactive), id, content |
| `WebUIBadge` | text, variant, size, dot |
| `WebUIAlert` | variant (.info/.success/.warning/.danger), title, message, dismissible, icon — close button carries `data-dismiss` |
| `WebUITabs` | tabs: [TabItem(id,label)], activeTab, id, onSelect (typed `(me, tabID)` handler — each tab self-wires under `<id>-<tabID>`; nil renders statically) |
| `WebUIAvatar` | initials, size, src, status |
| `WebUIProgress` | value (0.0–1.0), variant, showLabel, size |
| `WebUISkeleton` | variant, width, height, count |
| `WebUIToast` | variant, message, id, dismissible — close button carries `data-dismiss` |
| `WebUIModal` | title, id, content, footer — close button carries `data-dismiss` |
| `WebUITable` | headers, rows ([[any View]]), striped, hoverable, compact, responsive, wrapped, alignments, footer, emptyState, id, `sortableColumns: Set<Int>`, `hiddenColumns: Set<Int>`, `sort: (column: Int, direction: SortDirection)?`, `selectable: Bool`, rowIds, `selectedRows: Set<String>`, `expandedRows: Set<String>`, rowDetails — typed handlers `.onSort`/`.onSelectAll`/`.onSelect`/`.onToggleExpand` (routed per control) |
| `WebUIChip` | text, variant, removable, id — remove button carries `data-remove` |
| `WebUIEmptyState` | icon, title, message, action (label, id) |
| `WebUISpinner` | size, label |
| `WebUITooltip` | text, position, content |
| `WebUIStat` | label, value, size (sm/md/lg), trend + trendDirection (up/down), compare, spark ([Double] → inline svg) |
| `WebUIPagination` | page, pages, id (stable control ids), rowsPerPage (+options) — windowed `…` list, `aria-current`. typed handlers `.onPageChange`/`.onRowsPerPageChange` (routed per button/select) |
| `WebUITimeline` | events (time/title/desc/status: plain/completed/current/error), orientation (vertical/horizontal) |
| `WebUITree` | nodes (recursive id/label/icon/children), id (row ids), expanded (Set), selected — CSS open/close, server-driven selection |
| `WebUIBreadcrumb` | items (label/href), current, slash, id, collapse, maxItems — ellipsis middle, `sanitizeURL` on hrefs |
| `WebUIDescriptionList` | [(term, detail)] → `<dl class="list--desc">` |

dismiss/remove/close buttons render with `data-dismiss` / `data-remove`
markers and no auto-wiring. attach `.onDismiss { me, _ in ... }` to wire the
close button directly — `me` is an `ElementRef` to the component's own root
element (`me.remove()` removes it), no container handler or `targetClass`
matching needed. without a handler the marker renders statically and a
container `.onClick` may still read `event.data["targetId"]`/`event.data["targetClass"]`
to disambiguate (legacy pattern).

## WebUIChart

Server-rendered charts (inline SVG in a `<figure class="chart">`). see
`Documentation/CHARTS.md` for the full guide — marks, scales, selection,
theming.

```swift
import WebUIChart

Chart {
    ForEach(data) { d in
        BarMark(x: .value("Month", d.month), y: .value("Sales", d.sales))
            .foregroundStyle(by: d.product)   // series → palette slot + legend
            .stacking(.unstacked)             // .normal (stack) is the default
    }
}.markup
```

- **marks:** `BarMark`, `LineMark`, `AreaMark`, `PointMark`, `RectangleMark`,
  `RuleMark`, `SectorMark` (pie/donut via `innerRadiusRatio`), `RadarMark`
  (one closed polygon per series, needs ≥3 axes), `RadialMark` (a stroked gauge
  ring with a centred percentage).
- **plottables:** `.value("label", Int|Double|String|Date)` — strings/dates
  make the axis categorical (or formatted-numeric); `yStart`/`yEnd` ranges.
- **modifiers:** `.foregroundStyle(by:)` / `.foregroundStyle("var")`,
  `.opacity`, `.cornerRadius`, `.stacking`, `.interpolation`
  (`.linear`/`.monotone`/`.cardinal(t)`/`.catmullRom`/`.stepStart`/`.stepEnd`),
  `.symbol`, `.lineStyle`, `.annotation`, `.areaGradient(.fade("var")|…)`,
  `.tooltip("text")`.
- **chart modifiers:** `.chartTitle`, `.chartID` (stable mark ids for WS
  interactivity), `.onSelectMark { me, category in … }` (typed mark handler),
  `.chartSelection(axis:value:)` / `.chartXSelection` / `.chartYSelection`,
  `.chartXScale` / `.chartYScale`
  (`.linear(domain:)`, `.date(domain:)`, `.categorical(domain:)`),
  `.chartXDomain` / `.chartYDomain`, `.chartXAxis` / `.chartYAxis`
  (`AxisConfig`: grid, ticks, `labelFormat`), `.chartLegend(position:)`,
  `.chartForegroundStyleScale(domain:range:)`, `.chartInnerRadius`,
  `.chartAngularInset`, `.chartAccessibilityLabel`, and the layout pair
  `.chartHeight` / `.chartAspectRatio` (together they set the **design width**).
- **width:** a chart is laid out for a design width (`height × aspectRatio`,
  default `320 × 2 = 640`), renders at that width, may compress to 92% of it —
  12px text still paints 11.04px — and pans below that, so labels never paint
  under 11px at any container width. a chart contributes no intrinsic width, so
  a container that sizes to its content needs a declared width or a grid track.
  `Documentation/CHARTS.md` → *responsive layout* has the recipe.
- **polar:** all `SectorMark` (or a single `.angle` value per mark) → pie;
  `innerRadiusRatio > 0` → donut with a center total.

## WebUIIcon

Native svg iconography (inline `<svg>` + `stroke="currentColor"`). see
`Documentation/ICONS.md` for the full guide — catalog, tooling, security.

```swift
WebUIIcon(.search)                                   // aria-hidden by default
WebUIIcon(.download, size: .large, title: "Download") // role=img + aria-label
WebUIIcon(.star).iconSize(.extraLarge).foregroundColor(.danger)
WebUIIconCustom(name: "custom", body: "<path d=\"M12 2l9 10-9 10-9-10z\"/>")
```

- **catalog:** `IconName` — a generated `CaseIterable` enum (618 glyphs from
  `designer/icons/icon-manifest.json`); a typo is a compile error. `IconName.named(_:)`
  (raw-name lookup) and `IconName(emoji:)` (legacy bridge).
- **sizes:** `IconSize` `.small/.medium/.large/.extraLarge` (em multiples) and
  `.slot` (sized by the container's icon-slot css).
- **color:** rides `currentColor` — recolor with `.foregroundColor(_ token:)`.
- **custom:** `WebUIIconCustom` sanitizes caller-supplied geometry (strips
  `<script>`, `on*` handlers, `foreignObject`, `javascript:`/`data:` hrefs).

## WebUIServer

one-call serving of a no-webui page: http page routes, the framework asset
routes (stylesheet, engine, shell) with cache headers, host assets, `/ws`
upgrade, typed `Router` dispatch, ping/pong, read-idle reaping, and an
admission cap — replaces the NIO boilerplate reference hosts used to copy.

```swift
let router = Router {
    Route.page("/") { _ in
        WebUIDocument(title: "demo", body: VStack { Text("hello") }.markup)
    }
    Route.post("/login") { request in handleLogin(request: request) }
}
let server = WebUIServer(
    router: router,
    config: WebUIServerConfig(port: 9090)
)
try await server.start()                       // serves until stop() / process exit
```

- the `Router` is a typed `Route` table (`Route.get`/`Route.post`/`Route.page`,
  `PathPattern` params). `Route.page` renders its view as a whole document
  inside the render context the server establishes — component ids, handler
  registration, and a fresh CSP nonce per request, with
  `HTTPRequest.renderToken` available to echo into the page so the websocket
  frames bind back to this render. re-rendering replaces registrations
  idempotently (stable ids or auto `c0..` order both work when the tree is
  deterministic). the render-closure inits — `init(render:router:config:logger:)`
  and `init(requestRender:router:config:logger:)` — are **deprecated**: they
  keep their signatures and stand on a single-route `Router` for
  `config.pagePath`, so an existing 1.x page renders byte-identically
  (`WebUIServer.swift`).
- `Route.page<D: BufferRendering>` is generic and typed: its `content:` closure
  returns any `BufferRendering` value — a `View` *or* a whole document — in both a
  sync and an async form with the **same `content:` label**, so a trailing closure
  keeps working and the compiler disambiguates on the closure's async-ness.
  `PageResponder` is typed on `BufferRendering`. a page handler that answers
  rendered markup uses `HTTPResponse(_ markup:status:headers:cookies:)` (or
  `.html(markup)`) — `HTTPResponse.Body.html` carries **`UnsafeMarkup`**, so a bare
  `String` can no longer become a page.
- `WebUIServerConfig` tunes host/port, admission cap, read-idle seconds,
  asset cache seconds, the page path (default `/`), and `assets` — the host's
  own served files (see below).
- routes: page path + `/index.html`, `/__assets/css`,
  `/__assets/css.<sha256>` (immutable), `/ui/webui-engine.js`,
  `/ui/webui-shell.js`; then `config.assets`; 404/405 elsewhere.
  `Service-Worker-Allowed: /` + security headers on every response.
- the query string is stripped before routing, so `/__assets/css?v=9` and a
  query-bearing page url both resolve. `+` decodes to a space, `%XX` to its
  byte, and a malformed escape is preserved verbatim rather than dropped.
- `broadcast(_ updates:)` pushes fragments to every connected page with no
  inbound event to answer — streaming turns, background progress, a panel that
  changed on disk. the engine applies an update by element id, so a page that
  does not render the id ignores it. `connectedPages` reports the live count.
  a socket whose render token the server rejects is already closed, so a push
  cannot reach a stale page from a former session.
- `WebUIServer` is an actor. `stop()` closes the listener; the accept loop
  drains the connections already accepted and shuts the event loop group down
  itself, so a handler never schedules work on a stopped loop.

### host assets

`WebUIServerConfig.assets` serves files the framework does not ship — vendor
css/js, woff2 fonts, app scripts — without standing up a second http server:

```swift
let config = WebUIServerConfig(
    port: 9090,
    assets: [
        .text("/ui/app.css", appCSS, contentType: "text/css; charset=utf-8", cacheSeconds: 3600),
        .bytes("/ui/font.woff2", fontBytes, contentType: "font/woff2", cacheSeconds: 31536000),
    ]
)
```

`WebUIServerAsset.Body.bytes` keeps binary payloads off the `String` path. the
framework routes are matched first, so a host asset can neither shadow nor
disable the stylesheet, the engine, or the shell. `cacheSeconds: nil` (the
default) emits `no-store`.

`gzip:` takes a **pre-compressed** variant of the same body, negotiated exactly
like the framework's own sheet and engine: a client whose `Accept-Encoding`
allows gzip gets those bytes with `Content-Encoding: gzip`, and `Vary:
Accept-Encoding` goes out whenever a variant exists — including on the plain
response, or a shared cache would hand it to a client that never asked. the
server compresses nothing at runtime, so a host builds both forms (`gzip -c`
in its own asset tooling) and passes both:

```swift
.text("/ui/app.css", appCSS, contentType: "text/css; charset=utf-8",
      cacheSeconds: 31536000, gzip: appCSSGzip)
```

### hosting as a Service

`WebUIServerService` wraps the server for `swift-service-lifecycle`, so a
long-lived page server starts and stops inside a `ServiceGroup` instead of
owning its own process lifecycle:

```swift
let group = ServiceGroup(
    services: [WebUIServerService(server: server)],
    logger: logger
)
try await group.run()
```

a bind failure propagates out of `run()`, so a server that cannot listen fails
startup rather than reporting itself ready.

see `Sources/WebUIExample/main.swift` — the reference server is ~330 lines
of page + state + routes, with the pipeline entirely inside `WebUIServer`.

## WebUIExample

A SwiftNIO-based HTTP/WebSocket server that serves a live counter + echo page.

**Endpoints:**
- `GET /` — the page HTML
- `GET /__assets/css` — design system css (source bytes)
- `GET /__assets/js` — js runtime (source bytes)
- `WebSocket /ws` — event handling endpoint

**Port:** 9090 (configurable in source)

## WebUIAuth

authentication + sessions foundation for WebUI backends. design rationale and
threat model live in `Documentation/AUTH_SESSIONS.md`.

### Identity model

| Type | Description |
|---|---|
| `Identity` | `{ id: String, roles: Set<String> }` — `Codable`, `Hashable`, `Sendable`. `id` is the backend's stable identifier; `roles` is the role set guards branch on |
| `Role` | well-known role strings: `Role.member` (`"member"`), `Role.admin` (`"admin"`) |
| `Credential` | `{ username: String, secret: [UInt8] }` — raw password bytes, single-use |

### Sessions

| Type | Description |
|---|---|
| `AuthenticatedSession` | `{ id: [UInt8], tokenHash: [UInt8], identityID: String, csrfSeed: [UInt8], createdAt, expiresAt, lastSeenAt }` — the raw token never reaches storage, only its SHA-256 `tokenHash`. `id` is 16 random bytes |
| `SessionToken.generate()` | 32 bytes from `SecureRandom` **only** — fails loudly on entropy failure, no PRNG fallback |
| `SessionToken.hash(_:)` | SHA-256 of a token — the only form a store may persist |

### Protocols

| Protocol | Job |
|---|---|
| `AuthSessionStore` | `create` / `find(tokenHash:)` / `touch` / `invalidate(id:)` / `invalidateAll(for:)` / `listSessions(for:)` / `purgeExpired(before:)` — `AuthStoreError` = `.duplicateSession`, `.notFound`, `.malformedRecord` |

### Stores

| Store | Notes |
|---|---|
| `InMemoryAuthSessionStore` | actor-backed test double + reference semantics: primary id map, tokenHash index, per-identity reverse index |
| *(your own)* | `AuthSessionStore` is the contract for persistent stores — the core ships no database dependency |

### Cookies

| Type | Description |
|---|---|
| `HTTPCookie` | `name`/`value`/`Attributes` (`expires`, `maxAge`, `domain`, `path`, `secure`, `httpOnly`, `sameSite`). `setCookieHeaderValue()` throws on violation of the `__Host-` rules (Secure required, no Domain, `Path=/`) |
| `HTTPCookie.SameSite` | `.lax` / `.strict` / `.none` |
| `CookieParser.requestCookies(_:)` | quote-aware request-cookie parse: `$`-attributes ignored, values trimmed and unquoted |

### Password verification

| Type | Description |
|---|---|
| `Argon2Parameters` | `timeCost` / `memoryCostKiB` / `parallelism`; `Argon2Parameters.interactive` (19 MiB, t=2, p=1 — OWASP interactive) and `Argon2Parameters.recommended` (64 MiB, t=3, p=4) |
| `PasswordRecord` | `{ salt, hash, parameters }` with PHC-shaped `encodedString()` / `init(encoded:)` round-trip |
| `PasswordVerifier.hash()` / `.verify()` / `.makeSalt()` | Argon2id built on rawdog `RAW_argon2`; verify = re-hash + `constantTimeEquals` |
| `PasswordVerifier.dummyRecord()` | same-cost hash for unknown users — equalizes "user exists" vs "unknown" timing |

### Context

| Type | Description |
|---|---|
| `AuthContext` | `@TaskLocal` carrying `(session, identity?)` — set around authenticated renders and around event dispatch; `hasRole(_:)` helper. mirrors `RenderContext` mechanics |

### Hardening controls

| Type | Description |
|---|---|
| `AsyncSemaphore` | async counting semaphore for expensive verifications (the Argon2 concurrency cap). `wait()` suspends, never blocks a thread; `signal()` releases. `Mutex` (Swift `Synchronization`) guarded; waiters resume outside the lock |
| `LoginThrottle` | fixed-window attempt limiter keyed by caller strings (`"ip:…"`, `"user:…"`). `record(_:now:)` returns whether the attempt is within the window budget; `reset(_:)` clears on success; `prune(before:)` bounds memory |
| `SingleUseTokenStore` | bounded, expiring set of reserved + consumed stateless tokens; makes pre-auth CSRF tokens single-use. `reserve(_:expiresAt:key:)` budgets unsubmitted issuance per key (`maxOutstandingPerKey`, default 5) so one issuer cannot stockpile tokens and flood the store past capacity; `consume(_:expiresAt:key:)` records the token (releasing the issuer's budget) and fails closed at capacity |

## WebUIState

the application-state layer. a page is a pure function of its state, a control
mutates that state, and the host re-renders — no handler authors a fragment.

| Type | Description |
|---|---|
| `Store<State>` | one page instance's committed state. `final class` over a `Mutex` (not an actor: render is synchronous and cannot `await`). `read()`, `mutate { }` (throwing) / `commit { }` (non-throwing), monotonic `revision`, `binding`, `observe(_:session:)` |
| `StateStore<State>` | the port: `read()` / `mutate(_:)` / `revision`. synchronous by contract |
| `StatefulPage` | `associatedtype State: Sendable`, `initialState()`, `body(_ state: State) -> Body`. the body receives the only state it may see |
| `StatefulPageSession<Page>` | the render loop. `render(in:)` and `patch(in:)` take a `RenderContext` and return `PageRender` / `PagePatch`. `patch` renders, settles against the store's revision (`maxRenderPasses`, default 3), and diffs the region digest. it begins the router session itself — never wrap it in `EventRouter.begin` |
| `PagePatch` | `html`, `revision`, `changedRegions: [RegionID]`, `fragments: [FragmentUpdate]`, `isFullPage`, `passes`. `html` is always the whole page at that revision; `fragments` is the per-control bytes that moved — one entry per `data-component-id` element whose bytes changed, and empty when the wire cannot express the change (a first render, a value outside every control, a control that appeared or vanished). the fragment verdict is `fragments.isEmpty`, not `isFullPage` |
| `SessionStores` | one `Store` per `(page, session)`. `resolve(for:initial:)` returns the store plus the idle sessions the insert reaped (callers end those router sessions); `markLive` / `markClosed` / `isLive`; eviction is idle-only, so a live page is never reaped |
| `StateBinding<State>` | the typed door a render hands its controls: `revision` + `mutate(_:)` and nothing else — a binding has no html door |
| `StateRenderScope` | `@TaskLocal` binding the current render pass. `StatefulPage.binding` reads it; nil outside a state-bound render |
| `PageActions<State>` / `PageScope` | the *hosted* door: `handler(_:)` returns an `EventHandler` that commits and then renders the same session loop, so the answer to a click is the patch the mutation caused. `PageScope` is the task-local the pass installs; `StatefulPage.actions` reads it, and it is nil outside a render the host drove — which is what lets a page that also renders standalone degrade visibly instead of shipping dead controls |
| `.onClick(binding)` `.onSubmit(binding)` `.onInput(binding)` `.onChange(binding)` `.on(_:binding)` | handler sugars: `(StateBinding<State>) -> Void`. the handler mutates and returns nothing. the markup is byte-identical to `.onClick(perform:)` — only the handler body differs |
| `Mutation<State>` | a described mutation (`apply: (inout State) -> Void`), for a caller that passes intent instead of a closure |
| `StateObserver` / `PageSubscription` | `stateDidChange(revision:session:)` after a commit, and the subscription that turns it into at most one `PagePatch`, dropping out-of-order revisions |

## WebUIHost

the multi-tenant composition point: the one target that knows `WebUIServer`,
`WebUIAuth` and `WebUIState` together. `WebUIServer` has no edge to
`WebUIAuth`, and that absent edge is the compile-time proof that identity is
not the transport's job.

### Ports

| Protocol | Job |
|---|---|
| `PrincipalResolver` | `principal(for: HTTPRequest) async throws -> AuthContext?`. absent / malformed / expired / revoked credentials are `nil`, never an error; only an undeterminable answer throws |
| `PageCatalog` | `responder(for:principal:)` (guarded) and `responder(for:)` (the anonymous door). the two `nil`s are deliberately not distinguished |
| `SessionRouterTable` | `router(for:renderToken:)` → `(router, liveToken, needsRefresh)?`; `bind(_:session:renderToken:)`; `drop(session:)` ends every router the session bound |
| `RevocationBus` | `track(_:session:)` / `untrack(_:)` / `revoke(session:)` over `ConnectionToken` (an id plus a close action, so the bus never names a transport) |
| `SessionRevocation` | `endSession(tokenHash:)` — the store half of logout, paired with the bus |
| `IdentityDirectory` | `identity(for:)` — the roles a session's `identityID` carries; `DictionaryIdentityDirectory` is the fixed table |
| `RequestAuthorizer` | (`WebUIServer`) `authorize(_ request: HTTPRequest) async -> SessionKey?`. the server asks it about the page route and about the `/ws` upgrade, and stamps the answer on `HTTPRequest.principal`. non-throwing by design: a resolver failure is "no session", never a dead socket. `HostAuthorizer` is the conformance over any `PrincipalResolver` |
| `SocketLifecycleObserver` | (`WebUIServer`) `socketOpened(session:)` / `socketClosed(session:)`, once at each end on every exit path, and never at all for a connection that failed to upgrade. `SessionLivenessObserver` is the conformance that keeps `SessionStores`' liveness table honest |

### Types

| Type | Description |
|---|---|
| `AuthenticatedHost` | `struct` façade over resolver + catalog + table + revocation + sessions + the per-session state layer (`pages`, and `stores` as its registry). a `Responder` (so it drops into a `Router` route); `dispatch(_:session:renderToken:) -> EventDispatch`; `store(for:initial:)`; `signOut(_:)` / `signOut(for:)`; `sessionCookie(token:maxAge:)`. `secureCookies` is opt-in `false` for a loopback demo |
| `EventDispatch` | `outcome: HandlerOutcome` + `refreshedToken: RenderKey?`. `isRefused` is the `.fail(code: "token")` case — the transport closes the socket on it |
| `CookieSessionResolver` | `PrincipalResolver` + `SessionRevocation`: cookie (base64url, 32 bytes) → `SessionToken.hash` → store → `AuthContext`. also `sessionCookie(...)` / `clearingCookie(...)` |
| `AuthenticatedCatalog` | `[Page]` + `loginPath` + the table every render binds into. matching is `PathPattern` specificity; an anonymous request for a known page gets a `303` to the login path |
| `StaticCatalog` | exact-path table that ignores the principal — the public-page half |
| `Page` / `PageRequest` / `RenderedPage` | the declared/resolved split. `Page` is `Sendable` and holds no router, token or identity; `PageRequest.render(on:_:)` renders one pass under the right `RenderContext` and returns the `RenderedPage` the catalog binds |
| `RouterTable` | `final class` + `Mutex`. per session, `maxRendersPerSession` recent render tokens (default 8) each bound to the router its pass registered into, plus a bounded forward chain: an evicted token resolves to the token that replaced it and reports `needsRefresh` |
| `SocketRevocationBus` | `actor`: session → live connections; `revoke` drains the map before closing, so a re-entrant `untrack` finds nothing |
| `ConnectionToken` | `id` + `close: @Sendable () -> Void`; `next(close:)` draws a process-unique id |
| `SessionKey` / `RenderKey` | the two routing keys (in `WebUICore`): a session's token hash and one render token |
| `SessionCookie` | `typealias` for `HTTPCookie` |
| `AuthenticatedHostService` | the whole product as a `Service`: the server, the host's four ports, the per-session state layer and an `IdleSessionReaper` in one `ServiceGroup`, started and stopped together. the primary init takes the ports (`resolver:routers:revocation:sessions:stores:loginPath:cookieName:secureCookies:config:shutdownGrace:logger:routes:`) and builds the host, the catalog and the server — `routes` receives the `SessionPages` so a page value is never built before the store it renders is reachable — and wires `HostAuthorizer` + `SessionLivenessObserver` into the server config. `init(host:server:config:)` hosts a composition assembled elsewhere, which is the door an app needs when it serves routes of its own (a login form) beside the host's pages |
| `SessionPages` | the per-session render table: one `Store` per session (via `SessionStores`), one `HostedPage` (loop, and therefore the `RenderBaseline`) per session and page, and the `EventRouter` every pass registers into. `page(_:at:title:requiresRole:document:)` declares a page; `render(_:for:document:)` renders the session's own store; `store(for:initial:)` is the door a test or a background job reaches a session's state through. the server must be handed `events` (`WebUIServer.init(router:eventRouter:…)`), or a rendered page's controls are unreachable from its socket |
| `IdleSessionReaper` / `LifecycleClock` | a `Service` that ticks `SessionStores.reapIdle()` and drops each reaped session's routers. the interval is a dependency and the *sleeping* is one (`LifecycleClock`, production conformer `ContinuousLifecycleClock`), so a test drives the same loop with no real time. cleanup is the last thing `run()` does |

## WebUIAuthExample

a login-gated interactive demo on :9091 (sign in with `admin` / `password`),
built on `WebUIHost` + `WebUIState` + `WebUIServer`. it is the framework's worked
case for **the composition**: an authenticated, multi-tenant, stateful app is a
`StatefulPage` per screen plus one `AuthenticatedHostService`, and the app owns
its login ceremony and nothing else. **315 lines**, down from 741 — and the 309
lines of hand-rolled NIO transport the 741 still carried are gone, along with
the hand-rolled cookie parsing and `Set-Cookie` writing.

the file's five sections, measured:

| section | lines | what it is |
|---|---|---|
| the login screen | 40 | a scoped `.login*` stylesheet and the runtime-free sign-in document |
| the dashboard | 60 | one `StatefulPage`: `State` + `body(_:)`, every control a `PageActions` handler |
| the app | 105 | the composition — ports, the service, the route table, the page declaration, the document |
| ceremony | 77 | login CSRF mint/reserve/consume, two throttle budgets, one Argon2id verify, logout |
| entry point | 22 | `@main`, the kdf pool, the three flags |

demonstrates: a runtime-free login page (native POST, synchronizer CSRF,
hardened CSP), single-use login CSRF tokens with a per-issuer outstanding
budget, per-account submit + global mint throttles, a global Argon2id
concurrency cap on a dedicated `NIOThreadPool`, `SessionToken` + in-memory store
+ cookie issuance, `CookieSessionResolver`, `AuthenticatedCatalog` with one
authenticated page, `SessionPages` (one `Store` and one render loop per session,
so two signed-in people patch independently), a `StatefulPage` dashboard whose
controls are mutations shipped as fragments — the counter's value lives *inside*
the `data-component-id` element, so a click ships that control's bytes and not
the page — `HostAuthorizer` and `SessionLivenessObserver` wired by the service,
`AuthenticatedHost.signOut` (sockets, handler table, page state, session record,
cleared cookie), `IdleSessionReaper` on its own clock, an accept-time connection
gate (`--max-connections`, answered `503` + `Retry-After` at capacity), and
`Cache-Control: no-store` + `nosniff` + `X-Frame-Options` on every response —
the last four all the server's, not the app's.

**Endpoints:**
- `GET /login` — static login page (no JS runtime); mints and reserves a CSRF token
- `POST /login` — urlencoded credentials + single-use CSRF → `303` + `Set-Cookie`;
  `429` under throttle
- `GET /` — authenticated dashboard, else `303` to `/login` (from the catalog)
- `POST /logout` — CSRF-protected; `AuthenticatedHost.signOut` drops the socket,
  the handler table and the store record, and clears the cookie (`GET` → 405)
- `GET /__assets/css*`, `/ui/webui-engine.js`, `/ui/webui-shell.js` — the
  framework's routes, served by `WebUIServer`
- `WebSocket /ws` — a frame is admitted only under a live render token

**Port:** 9091

**Flags:** `--port`, `--argon2-workers` (kdf pool, default 2),
`--max-connections` (default 256).

**What the app still writes, and why.** the login ceremony is application code
because `WebUIHost` has no auth flow — nothing in the framework signs anyone in.
and two seams the demo pays for by hand:

- **no extra-route door on `AuthenticatedHostService`.** its primary init builds
  the route table from the declared pages, so an app with a login form assembles
  the host and the server itself and uses `init(host:server:config:)`. the demo
  does exactly that, and hands the server `pages.events` — a page rendered into
  a fresh `EventRouter` ships controls the server can never dispatch.
- **no principal-aware initial state.** `SessionPages.render` seeds a session's
  store from `StatefulPage.initialState()`, which cannot see the request, so the
  demo seeds the store first (`SessionPages.store(for:initial:)`, built from the
  resolved principal) and then lets the loop render it.

the framework's own gaps on this path are recorded in `ARCHITECTURE.md` ("what
these products do not yet carry").

## WebUIBuild

the host-side build library the asset toolkit is made of: deterministic gzip, the
generated-source emitter, and the manifest. host-only by construction — it may import
Foundation, and the client build never links it. `Documentation/ASSETS.md` is the full
article (the two recipes, the manifest reference, the measured constraints that fix the
shape); this is the surface map.

```swift
// a consumer's tool: one call between the render and the file
let receipt = try WebUIAssetBuilder.emit(
    shipped: sheet, typeName: "MySheet",
    options: .init(minify: true, prose: .check, contentType: "text/css; charset=utf-8"),
    to: output
)
// a target's manifest: every entry becomes a WebUIShippedAsset conformance
let receipts = try WebUIAssetBuilder.embed(
    manifest: try WebUIAssetManifest.load(from: manifestURL), to: generatedURL
)
```

- `gzip(_ data: Data) -> Data?`, `gzip(_ text: String) -> Data?` — deterministic
  `gzip -n -9 -c`; `nil` when the build host has no working `gzip`, in which case the caller
  ships the raw bytes. the payload round-trips through a temporary file, never a two-pipe
  dance (which deadlocks once output outgrows the pipe buffer).
- `WebUIAssetBuilder.emit(shipped:typeName:options:to:) -> Emitted` — one payload in, one
  `WebUIShippedAsset` conformance named `typeName` out. the payload rides base64: no escaping
  can silently change bytes, and a byte literal is slow for the type checker at asset sizes.
- `WebUIAssetBuilder.Options` — `minify: Bool` (the framework's own `minifyCSS`),
  `prose: ProsePolicy` (`.off` | `.check`, the guard over the payload *as it will ship*),
  `contentType: String` (required; also decides the prose grammar).
- `Emitted` — the build's receipt: `typeName`, `bytes`, `gzipBytes: Int?`, `stamp`. for a
  directory bag the stamp is a build record (the digest of the sorted name+bytes stream),
  not a url address.
- `WebUIAssetManifest.load(from:)` — validated loading of `Assets/webui-assets.json`
  (`WebUIAssetManifest.Entry.Kind`: `file` | `text` | `directory`; optional `ceilingBytes` /
  `ceilingGzipBytes` pins, enforced during `embed`). unknown keys, unknown kinds, missing
  required fields, non-utf-8 text payloads and missing paths fail naming the entry.
- `ProsePolicy`, `ProseFinding` (the public re-exposure of the package-level guard's
  findings: `line` + `text`), and `WebUIBuildError` (`invalidTypeName`, `proseWouldShip`,
  `malformedManifest`, `missingAsset`, `overCeiling` — every case's `description` names the
  entry a build should fix).

### the toolkit's other halves

- `WebUIShippedAsset` (`WebUICore`) — the protocol generated code conforms to:
  `contentType`, `stamp` (the first 12 hex of the sha256 of `body`), `body: [UInt8]`,
  `gzip: [UInt8]?`. foundation-free, because generated code must conform without linking a
  server, the view dsl or a runtime.
- `WebUIAsset` (`WebUIServer`) — one value owning bytes, content type, variant and cache
  policy: `url` is the bare path plus `?v=<12 hex>`, `registration` is the bare path with a
  year-long `immutable` cache and the variant attached. `WebUIAsset(_ shipped:path:)` takes a
  generated conformance. registering the *stamped* path answers 404 — pinned as a test.
- `WebUIServerAsset.immutable` (defaulted `false`) — appends `, immutable` to the host
  asset's cache policy.
- `ThemeSheet.gzip: [UInt8]?` (`WebUIDesignSystem`) — the catalog sheet's optional
  pre-compressed variant; its route now negotiates (`Content-Encoding` + `Vary`) like every
  other asset route, while the url stays `/__assets/theme.<sha256>`.
- `WebUIEmbedPlugin` — the build-tool plugin: `<target>/Assets/webui-assets.json` in, one
  generated file out, every referenced file declared as an input. attach it and
  `exclude: ["Assets"]` the target so swiftpm stops warning about files it does not compile.
