# API Reference

## WebUI

### View Protocol

| Protocol | Requirement | Notes |
|---|---|---|
| `View` | `func render() -> String` | pure function, no side effects, `Sendable` |
| `View` | `func render(into buffer: inout HTMLBuffer)` | *defaulted* requirement: writes into a shared render buffer; the default falls back to `render()`, so a view that implements only `render()` renders byte-identically |
| `ViewModifier` | `func apply(to html: String) -> String` | wraps rendered html with attributes or styles |
| `ViewModifier` | `func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer)` | *defaulted* requirement: applies the modifier through the buffer; the default applies to `content.render()` |
| `ModifiedView<Content: View, M: ViewModifier>` | `View` | type-preserving wrapper returned by every modifier |
| `EmptyView` | `View` | renders nothing |

the buffer route is the framework's own render path, not yet consumer API:
`HTMLBuffer` is a `public` *type* — a protocol requirement is implicitly as
visible as its protocol, and the requirements name it — while **every member
stays `package`**. a consumer can see the type in a signature but cannot
construct or write through one; the members open up with the 2.0 flip, when
`render(into:)` becomes the requirement and `render()` a deprecated
convenience (`STABILITY.md`). both additions are additive in the 1.x sense:
an existing conformer keeps compiling and rendering identically.

### ViewBuilder

`@resultBuilder` used by every container closure. single-expression blocks preserve
the concrete view type; multi-view blocks produce `[any View]`.

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
| `ForEach<Data: RandomAccessCollection>` | — | renders each element; no wrapper |
| `Group` | — | renders children without a wrapper |
| `WebUIIcon(_ name:, size:, title:)` | escaped title | inline svg from the generated `IconName` catalog; `currentColor` |
| `WebUIIconCustom(name:body:size:title:)` | sanitized body | caller-supplied svg geometry (see the WebUIIcon section) |

every attribute parameter (`id`, `class`, `name`, `for`, `data-status`,
`Form.method`, …) is html-escaped before emission. url-valued parameters
(`Link.href`, `Image.src`, `Form.action`) pass through `sanitizeURL` first.

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
| `EventData` | `{ component: String, event: String, data: [String: String] }` — `click` data carries `targetId` and `targetClass` of the clicked element |
| `EventHandler` | `@Sendable (EventData) async -> [FragmentUpdate]` |
| `EventRouter` | routes events to registered handlers. `maxHandlers: Int` (default 10,000), `handlerCount: Int`. one router per render pass — call `reset()` before rendering a fresh page |
| `RenderContext` | `@TaskLocal` context providing component ID generation, element ID minting, and handler registration |
| `ComponentID` | hashable/codable string wrapper for component ids |
| `ElementRef.stable(_:)` | framework-facing factory for a ref to an element with a caller-chosen stable id (minted by typed component handlers for their root). callers should keep receiving refs rather than fabricating them |
| `ElementRef` | typed handle to a rendered element minted by the framework. `remove()` → empty-html fragment (the runtime removes the element), `replace(with:)` → outerHTML swap, `update(view)` → re-render from a `View`. no caller-supplied ids |
| `Dismissible` | protocol for views with a dismiss/remove affordance. `.onDismiss { me, _ in }` wires the close button to a routed component and receives the root `ElementRef` |
| `FragmentUpdate` | `{ id: String, html: String }` — DOM patch instruction. `html: ""` removes the element (pinned contract, see `JS_RUNTIME.md` patcher) |
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
| `HTMLDocument` | title, body, styles, rawStyles, scripts, contentSecurityPolicy, includeRuntime, runtimeConfig, devMode, head, bodyAttributes, lang, preMinifiedStyles | complete HTML document with auto-generated CSP and nonce. shipped css is minified (comments + blank lines stripped) unless `preMinifiedStyles: true` embeds the caller-provided combined sheet verbatim (used by `WebUIDocument`'s hoisted sheet) |
| `WebUIDocument` | same as HTMLDocument | HTML document with the full design system css — the record sheet (layout rules + embedded css) is minified once into `WebUIDocument.minifiedDesignStyles` and embedded verbatim on every render (`preMinifiedStyles: true`), removing the old per-render minify of ~300 kb css (~11 ms in release → <0.01 ms) |

`runtimeConfig` (a `RuntimeConfig?`) changes only the runtime bootstrap: with a
non-empty config the page emits `WebUIRuntime.init({...})`; with no config the
default `WebUIRuntime.init();` is emitted byte-for-byte.

`RuntimeConfig` keys: `wsUrl`, `wsReconnect`, `wsMaxReconnectDelay`,
`wsPingInterval`, `wsPongTimeout`, `maxQueueSize`, `debounceInputMs`,
`debounceMaxWaitMs`, `optimisticSettleMs`, `logLevel`, and `renderToken`. the
`renderToken` (a per-render id minted by the server) is echoed back with every
websocket `event`/`ping` so a server that mints tokens can route each message
to the page's router and reject stale pages from other sessions — see
`WebSocketProtocol` and the auth docs. only keys that are set are emitted;
string values are hand-escaped into safe json string literals.

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
  `contentSecurityPolicy` still wins). the wasm *client* mode this parameter
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
| `CSRFProtection.token(for:secret:maxAge:) throws -> String` | HMAC-SHA256 stateless token; throws on signing failure |
| `CSRFProtection.validate(_:for:secret:) -> Bool` | validate token (signature + expiration); false on any failure, including signing errors |

## WebUIDesignSystem

### WebUIDocument

`HTMLDocument` variant that ships `LayoutStyles.complete` plus the full
`WebUIAssets.css` (the nexus design system, 169 `:root` CSS custom properties).
the css is minified at render time, so served pages carry no comments and no
blank lines. see `Documentation/DESIGN_SYSTEM.md` for the complete token and
component catalog.

accepts `theme: WebUITheme = .standard` — a themed document appends the
theme's css (`:root` overrides + app rules) after the design sheet, so later
source order wins the cascade for every token the components resolve through
`var(--…)`. `.standard` (the default) contributes nothing and renders
byte-identical to the unthemed document.

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

per-page custom aesthetics on top of the shipped design system, without a
fork of the framework css.

| Type | Role |
|---|---|
| `DesignToken` | generated enum of the 169 `:root`-scoped tokens from `design-system.css` (the only custom properties a later `:root` override can restyle). **generated into the wasm-clean `WebUIDesignSystemCore` target** (`DesignTokens+Generated.swift`) so the client build can reference it without rawdog. case name = camelCased css name (`color-primary-solid` → `.colorPrimarySolid`), `rawValue` = the exact kebab name, `cssVariable` = `--<rawValue>`. component-scoped custom properties (`.btn { --btn-bg: … }`) are excluded by construction — restyle those via theme `rules`. |
| `ColorScheme` | `.automatic` / `.light` / `.dark`. a fixed scheme declares `color-scheme:` on `:root`; `.dark` is the dark-first choice. |
| `WebUITheme` | value type in `WebUIDesignSystemCore` (wasm-clean, re-exported via `WebUIDesignSystem`): `tokens: [DesignToken: String]`, `customTokens: [String: String]` (app-invented `--name` keys), `scheme: ColorScheme`, `rules: [CSSRule]`. `.standard` is the empty theme; `.overlaying(_:)` layers a partial theme (dynamic accent) over a static one; `stylesheet()` renders deterministically (color-scheme, then tokens sorted by css name, then rules). |
| `WebUIThemeProvider` | protocol with `static var theme: WebUITheme`. the default yields `.standard`, so hand-written conformers compile for free. |
| `@Theme` | attached macro: turns a struct of `static let` members into a `WebUIThemeProvider`. reserved members `scheme`, `rules`, `customTokens` map to the three non-token axes; every other `static let <name> = <value>` is a token override whose member name must be a `DesignToken` case (compiler-validated at the expansion site). |

```swift
import WebUIDesignSystem

@Theme
struct NexusDark {
    static let scheme = ColorScheme.dark
    static let colorPrimarySolid = "#6c8cff"
    static let colorBg = "#101014"
    static let customTokens = ["--chat-user-bubble": "#2a2a2e"]
    static let rules: [CSSRule] = [.chatBubble, .streamDots]
}

let page = WebUIDocument(body: body, theme: NexusDark.theme)
```

a dynamic overlay rides on top of a static theme:

```swift
let doc = WebUIDocument(
    body: body,
    theme: NexusDark.theme.overlaying(WebUITheme(tokens: [.colorPrimarySolid: userAccent]))
)
```

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
| `WebUITable` | headers, rows ([[any View]]), striped, hoverable, compact, wrapped, responsive, alignments, footer, emptyState, id, rowIds, sortable, selected, expanded, rowDetails — typed handlers `.onSort`/`.onSelectAll`/`.onSelect`/`.onToggleExpand` (routed per control) |
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
}.render()
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

one-call serving of a no-webui page: http page route, the framework asset
routes (stylesheet, engine, shell) with cache headers, host assets, `/ws`
upgrade, `EventRouter` dispatch, ping/pong, read-idle reaping, and an
admission cap — replaces the NIO boilerplate reference hosts used to copy.

```swift
let router = EventRouter()
let server = WebUIServer(
    render: { renderPage(router: router) },   // fresh document per request (new nonce)
    router: router,
    config: WebUIServerConfig(port: 9090)
)
try await server.start()                       // serves until stop() / process exit
```

- `render` is called per request (fresh CSP nonce each time — the documented
  best practice) and registers handlers into the same `router`; re-rendering
  replaces registrations idempotently (stable ids or auto `c0..` order both
  work when the tree is deterministic). the request-aware
  `WebUIServer(requestRender:router:config:logger:)` instead receives a
  `WebUIServerRequest` (`path` + decoded `query`), which is what a deep link
  like `/index.html?s=<id>` needs.
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

see `Sources/WebUIExample/main.swift` — the reference server is now ~100
lines of page + state, with the pipeline entirely inside `WebUIServer`.

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

## WebUIAuthExample

A SwiftNIO-based login-gated interactive demo on :9091 (sign in with `admin` /
`password`). demonstrates the auth stack end to end: runtime-free login page
(native POST, synchronizer CSRF, hardened CSP, `X-Frame-Options`), single-use
login CSRF tokens, per-IP + per-account login throttles, a global Argon2id
concurrency cap on a dedicated `NIOThreadPool` (never the event loop),
dummy-hash equalization, `SessionToken` + in-memory session store + cookie
issuance, the interactive dashboard (counter / progress / echo / optimistic
reset) under `AuthContext`, a per-session interactive router keyed by a
**per-render ws token** (every `event`/`ping` carries it; unknown tokens get a
redirect + close — a stale page from another session cannot drive the
session's router), a **session-gated** WebSocket upgrade (foreign/no-origin/
no-session refusals answer `403`), a per-session connection registry that
**closes every live socket on logout**, per-event + ping liveness enforcement,
an accept-time connection gate (`--max-connections`, default 256), a top-level
120 s read-idle reaper (plain http + websockets), awaited terminal-write
responses, `Cache-Control: no-store` + `nosniff` + `X-Frame-Options` on every
response, the minified design sheet on `/__assets/css`, a 60-second
maintenance sweep (sessions, routers, throttle windows, token store), and
CSRF-protected POST logout.

**Endpoints:**
- `GET /login` — static login page (no JS runtime); mints a fresh CSRF token
- `POST /login` — urlencoded credentials + single-use CSRF → `303` + `Set-Cookie`;
  `429` under throttle
- `GET /` — authenticated dashboard, else `303` to `/login`
- `POST /logout` — CSRF-protected logout → `303` + cookie clear + live-socket
  teardown (`GET` → 405)
- `GET /__assets/css` / `GET /__assets/js` — minified design sheet + runtime
- `WebSocket /ws` — valid-session same-origin interactive events only

**Port:** 9091

**Flags:** `--port`, `--event-loops` (nio group size, default core count),
`--argon2-workers` (kdf pool, default 2), `--max-connections` (default 256) —
tuned for small hosts (a 2 gb / 4-core box).

not a deployment template: session caps per user and per-session state
containers are deferred (see the plan); the Argon2 cap, sweep, and render-token
binding described above are shipped.
