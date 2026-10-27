# Stability Policy

the stability contract of the no-webui toolkit. read this before depending
on the package or publishing a release: it states what "stable" means, what
is pinned, and what is explicitly not.

## versioning

the package follows **semantic versioning** for its public API:

- **major (1.0 → 2.0)** — any breaking change to the consumer-facing surface
  (a public initializer, parameter, default, emitted markup contract, or
  runtime protocol change). consumers upgrading majors must expect migration.
- **minor (1.0 → 1.1)** — additive surface only: new components, new
  parameters with defaults, new modifiers, new tokens. existing call sites
  keep compiling and rendering identically.
- **patch (1.0.0 → 1.0.1)** — fixes that do not change the public contract.

the stability epoch begins at **1.0.0**. before that (`0.x`) the project is
in active design and the API is allowed to churn (it already has: the
`EventData.data` payload was widened from `[String: String]` to
`[String: JSONValue]` during the wasm migration; the doc that argued that change
has since been deleted, and `CHANGELOG.md` records it).

the canonical list of what may not change in a minor/patch is known as the
**frozen surface**.

## the frozen surface

the frozen surface is the consumer-facing API of the library products
(`WebUI`, `WebUIDesignSystem`, `WebUIAuth`, `WebUIChart`, `WebUIServer`,
`WebUIState`, `WebUIHost`) and the modules a consumer reaches through their
`@_exported` cores (`WebUICore`, `WebUIDesignSystemCore`, `WebUISharedCore`)
and direct imports (`WebUIState`, `WebUIHost` are products, not re-exports).
it is enforced by **two
mechanisms**, and only what a mechanism demonstrably checks is claimed here as
checked:

**the generated pin list.** `Documentation/frozen-surface.symbols` is a
generated, member-level enumeration of the frozen surface: every declared
public init, method, property, subscript, enum case, typealias and macro in
the eleven modules, emitted by the real toolchain tool
`swift-symbolgraph-extract` (there is no `swift package api` verb, despite the
earlier plan's claim — `swift package --help` has none, and the external
`swift-package-tool` binary enumerates top-level declarations only).
`Tests/WebUITests/FrozenSurfaceTests.swift` re-extracts the built products on
every `swift test` and **fails, naming each added and removed symbol**, when
the committed list and the fresh extraction diverge — so a public symbol
absent from the list fails the build, and so does a symbol in the list that
left the tree. the list is generated, not hand-maintained: intentionally
moving the surface means regenerating it (`FROZEN_SURFACE_EMIT=1 swift test
--filter FrozenSurfaceTests` rewrites the file in place) and committing the
regeneration in the same commit as the api change that forced it, justified
there. re-measured 2026-10-27: 5040 symbols across 11 modules.
compiler-synthesized members are excluded — a synthesized `==` is generated,
not a declared contract, and including it would make the list churn on every
equatable addition.

the typed-builder arc is the limit's clearest worked case, measured: `ForEach`
gained a `Content: View` parameter and swapped its result builder, and the
regeneration moved **31 added, 0 removed** lines — every one of them a *new*
public type (`ElementBuilder`, `TupleView`, `OptionalView`, `EitherView`,
`RepeatedView`, `ElementGroup`). the signature change itself moved nothing;
only `Tests/WebUITests/ForEachElementShapeTests.swift` (the compile-time pin on
the element's concrete type) sees it.

a stated limit of this pin: it is **name/label-keyed, not type-keyed**. a
parameter's type is part of the emitted signature label, but the canonicalization
keys each line by its name — W4 proved that changing a parameter *type* (`body:
String` → `body: UnsafeMarkup`) moves **zero** pin lines. the pin therefore cannot
detect the arc's own type tightening: it enumerates that a public symbol exists and
keeps its name, not that its parameter types are unchanged. a type change still
breaks a consumer at compile time, but the frozen-surface gate will not flag it —
that is exactly what the compile-time reference pins and the surface suites are
for.

**the compile-time reference pins.** `Tests/WebUITests/APISurfaceTests.swift`
(the W1-era suite, hand-maintained) references the primitives, layouts,
modifiers, event modifiers, design-system components, auth surface and
document assembly at compile time and asserts their render markers. it pins
**none** of the wave-2–5 surface — `StyleSheet`, `DesignTheme`,
`TokenOverrides`, `Island`, `ErrorBoundary`, `HTTPRequest`, `Router`,
`WebUIStrings`, `Aria`, `CascadeLayer`, `UnsafeMarkup` all have zero mentions
there (measured, not assumed). those are pinned by the generated list above
and by their own suites: `StyleSheetTests`, `ThemeProtocolTests`,
`IslandTests`, `ErrorBoundaryTests`, `RouterTests`, `LocalizationTests`,
`A11yTests`, `CascadeLayerTests`, the `authSurfacePins` in `APISurfaceTests`,
the `WebUIAuthTests` suites, `ChartTests` for the chart product, and the
wire/runtime contracts in `WebUIClientTests` + `DeploymentIntegrityTests`.
where a type is constructed only by a demo page (`WebUIMenubar` in
`WebUISmokeTest`/`WebUIBlocks`, `ClientBoot` in `EngineBootTests`/
`CSPExtrasTests`, `DesignSystemAssets` in `ThemeSheetTests`), that pin catches
a signature break but not a marker break — a demo-page construction compiles
or it does not, and no marker is asserted there.

the frozen surface is:

- the render protocol: `BufferRendering` and its public `markup: UnsafeMarkup`
  materializer. `View`, `HTMLDocument`, `WebUIDocument` and `CSSStylesheet` all
  refine it, so `.markup` is the one public door to a rendered value, and
  `HTMLDocument.body`/`WebUIDocument.body` carry `UnsafeMarkup`.
- view primitives: `Text`, `Raw`, `Div`, `Span`, `Button`, `Input`,
  `TextArea`, `Image`, `Form`, `Label`, `Heading`, `Link`, `Paragraph`,
  `Section`, `Navigation`, `Header`, `Main`, `Footer`, `UnorderedList`,
  `OrderedList`, `ForEach`, `Spacer`, `EmptyView`, `ZStack`.
- layout: `VStack`, `HStack`, `ScrollView`, `Grid`.
- view modifiers: `padding` (`Int` and `SpaceToken`), `margin`, `font`,
  `fontFamily`, `textAlign`, `backgroundColor`, `foregroundColor`
  (`String` and `ColorToken`), `width`, `height`, `maxWidth`, `minWidth`,
  `minHeight`, `fill`, `stretch`, `style`, `border`, `cornerRadius`,
  `showIf`, `id`, `class`, `attribute`, and the event modifiers
  (`.onClick`/`.onSubmit`/`.onInput`/`.onChange`/`onOptimisticClick` …).
- components: `WebUIButton`, `WebUIInput`, `WebUIBadge`, `WebUIAvatar`,
  `WebUICard`, `WebUITabs`, `WebUITree`, `WebUITable`, `WebUIEmptyState`,
  `WebUIProgress`, `WebUISkeleton`, `WebUIModal`,
  `WebUIToast`, `WebUITimeline`, `WebUIBreadcrumb`,
  `WebUIStat`, `WebUIPagination`, `WebUIAlert`,
  `WebUIDescriptionList`, and the shell set (`WebUISidebar`,
  `WebUISegmentedControl`, `WebUISearchField`, `WebUIListView`,
  `WebUIListItem`, `WebUIComposer`, `WebUIPanel`).
- components that joined the promise because a shipped page already renders
  them, so their shape is a de-facto contract whether or not it was declared
  one: `WebUISidebarItem` (named in `WebUISidebar`'s own signature),
  `WebUIField`, `WebUIMenubar`, `WebUIMenu`, `WebUIActivityFeed`,
  `WebUIAspectRatio`, `WebUICircularProgress`, `WebUIBanner`,
  `WebUIToggleGroup`, `WebUISeparator`, `WebUIKbd`, `WebUIInputGroup`,
  `WebUIMarker`, `WebUIAttachment`, `WebUINavbar`, `WebUIItem`.
- document/assembly: `WebUIDocument` (title/body/`includeRuntime`/
  `runtimeConfig`/`contentSecurityPolicy`/`theme`/`rawStyles`/`clientMode`),
  `RuntimeConfig`, `ClientBoot` (the engine boot + `csp(nonce:)`),
  `DesignSystemAssets` (the content-addressed sheet url, hash and prewarm).
- the theming surface: `WebUITheme`, `ThemeMode`, `ThemePalette`, `ThemeScope`,
  `TokenAlias`, `WebUIThemeProvider`, `ThemeCatalog` / `ThemeEntry`, the `@Theme`
  macro, and the generated `DesignToken` vocabulary.
- the `WebUIAuth` surface: `SessionToken`, `CSRFProtection`,
  `PasswordVerifier` / `Argon2Parameters` / `PasswordRecord`, `LoginThrottle`,
  `SingleUseTokenStore`, `AsyncSemaphore`, `CookieParser` / `HTTPCookie`,
  `Identity` / `Role` / `AuthContext`, `AuthenticatedSession`, and the
  `AuthSessionStore` protocol.
- the assets: `designer/assets/design-system.css` tokens
  (`--space-*`, `--color-*`, `--font-size-*`, `--radius-*`, `--shadow-*`,
  `--z-*`, `--transition-*`) and the emitted class vocabulary
  (`.button`, `.card`, `.input`, … — no-prefix, and `br-` only as keyframe
  names), pinned by `DeploymentIntegrityTests` / `DesignTokenIntegrityTests`.
- the runtime contract: the delegated-event protocol (`data-component-id` /
  `data-event`), the websocket message shapes (`WSIncoming`/`WSOutgoing`),
  and the fragment patch semantics (`FragmentUpdate`, replace-by-id,
  optimistic rollback, input/scroll/focus restoration) — pinned by the
  client-runtime suites and the served-bytes gates (`smoke`'s asset-byte
  checks and the showcase byte-count pin).

### measured consumption (re-measured 2026-10-10)

the frozen list in the two paragraphs above is the *shape* contract, and the
generated pin enforces it mechanically. this survey is the *usage* report — it
separates what is exercised from what merely exists, because the generated
list pins a name whether or not anything renders it. a survey of every
top-level `public` declaration in `Sources/` — non-comment mentions outside the
declaring file, partitioned by consumer class (library product target / demo
app / `Tests/`) — found three sets. re-measure before trusting the counts.

**exercised (the list above).** every decl in the frozen list is rendered by a
library target or a demo page. the 16 that had been outside it were measured
into it on 2026-10-08, with these mention counts in
`WebUIShowcaseContent/ShowcasePage.swift`: `WebUIMenu` 10 · `WebUIActivityFeed`
8 · `WebUIAspectRatio` 7 · `WebUICircularProgress` · `WebUIBanner` ·
`WebUIToggleGroup` · `WebUISeparator` · `WebUIKbd` (6 each) · `WebUIInputGroup`
5 · `WebUIAttachment` · `WebUINavbar` · `WebUIItem` (4 each) · `WebUIMarker` 3.
`WebUISidebarItem`, `WebUIField` and `WebUIMenubar` render in `WebUIBlocks`
rather than the showcase (`WebUIMenubar` also on the smoke page), and
`WebUISidebarItem` is named in the frozen `WebUISidebar`'s own signature — a
frozen type cannot honestly promise a shape while leaving its parameter type
free to change.

**shipped but unproven — review on first use (7).** no library target and no
demo page renders these; the `APISurfaceTests` pin is their only exerciser. they
are deliberately **outside** the frozen list: a shape nothing exercises has not
earned a promise, and binding a release to an unvalidated shape costs more than
it buys. treat any new use as a design review — the first real consumer is what
freezes them, and that is now a one-line edit to the list above. note that the
generated pin list *does* capture their current shape — it enumerates every
public symbol of the eight modules, proven or not — but that is a record, not a
promise: redesigning one in a minor means regenerating the list, and no gate
argues against it. the semver promise applies to the frozen list, not to the
record.

| name | why it is unproven |
|---|---|
| `WebUISelect` | one mention repo-wide (its own pin); `Select` (primitives) and `WebUIComboBox` cover the demos |
| `WebUISpinner` | no non-test renderer; `WebUIProgress` and `WebUICircularProgress` carry the loading demos |
| `WebUITooltip` | no non-test renderer |
| `WebUIChip` | no non-test renderer; `WebUITag` restates it with a parallel variant enum |
| `WebUIReasoningBlock` · `WebUIToolStep` · `WebUITurnSummary` | the agent-turn trio ships with no page that renders it |

two further types stay **inside** the frozen list although nothing renders them
by name, because they are consumed *structurally* and their shape is
load-bearing: `EmptyView` (the `ViewBuilder` sentinel every empty branch
produces) and `Argon2Parameters` (the config type in the frozen
`PasswordVerifier`'s signature).

**the long tail — deliberately outside (92).** `WebUIExtrasLongTail.swift` and
`WebUIExtrasForm.swift` declare 92 public components between them (measured, not
estimated). membership of
those files is *not* the criterion — two of their types (`WebUIField`,
`WebUIMenubar`) sit in the frozen list above precisely because a shipped page
renders them, leaving 90 of the tail outside. the rule is coverage: a type with
a renderer is a contract, a type
without one is a draft, whichever file it lives in.

outside the frozen surface (free to change in any release): example
apps (`WebUIExample`, `WebUIAuthExample`, `WebUIShowcaseServer`), plugin
verbs, docs, and internal target layout.

## the showcase byte pin

the showcase artifact — the page `swift run WebUIShowcase --generate` writes —
renders at exactly **168671 bytes** at this epoch. that number is now enforced
in-repo: `Tests/WebUITests/ShowcaseWiringTests.swift` renders the artifact
in-process through the same path the generator uses (`RenderContext.$current`
snapshot + `WebUIDocument(title:body:includeRuntime:false)`) and
`showcaseArtifactByteCountIsPinned` asserts its byte count against the single
constant `showcaseBytePin` (in that file — the value lives in exactly one
place). before this gate existed the number lived only in the gitignored plan,
so nothing could ever fail on drift; now a drifted count fails `swift test`
with the measured and pinned values.

the gate asserts the byte **count**, never a hash of the raw bytes. the raw
bytes are not stable run-to-run: `JSONValue.serialize()` emits object keys by
direct `Dictionary` iteration and swift dictionary order is randomized per
process, so a raw-bytes hash would be flaky. the *count* is deterministic
(modulo a legitimate change), which is the machine-checkable claim; the *order*
of the bytes is not a stability contract. "byte-identical HTML for unchanged
source" is therefore only ever true in the weak sense — identical byte count
and identical markup under a stable process — never as a hash-verifiable
promise.

when does the pin legitimately move? a change that adds or removes bytes in
the rendered page (a new component on the showcase, a reworded default since
fixed, an attribute gained) moves it. the rule is the same one the generated
surface follows: update the single constant `showcaseBytePin` in the same
commit as the change, justify the move in the commit message, and re-measure
the new count from `swift run WebUIShowcase --generate` rather than guessing.
a move that *isn't* deliberate (an accidental reword, a byte added by a
component refactor) is a regression, not a pin to update. the gate proved
non-vacuous at landing: the corrupted-constant run fails with "showcase
artifact drifted: 168671 bytes, pinned 168672".

## migration notes for consumers of 0.x

- `EventData.data` is `[String: JSONValue]`, **not** `[String: String]`.
  a 0.x consumer reading `data["id"] as? String` must read
  `event.string("id")` (or `event.number(...)` for numbers). the wire bytes
  are unchanged — only the Swift-facing payload type moved.
- component interiors pad through their `__body` element (`.card__body`,
  `.panel__body`, `.list__body`, `.modal__body`): if a container ever renders
  content flush against its rounded box, wrap the children in the `__body`
  element instead of padding the container.

## deprecation

before a frozen-surface member may be removed, it must ship a deprecation
across **one full minor release**: a public `@available(*, deprecated, …)`
marking (or a docs note for markup contracts) plus a changelog entry naming
the replacement. removal lands in the next **major**.

### removals that were never functional (unreleased)

three chart symbols were removed outright rather than deprecated —
`ChartScrollAxes`, `.chartScrollableAxes(_:)`, `.chartXVisibleDomain(_:)` and
their `ChartConfig` storage. they shipped with **no reader anywhere**: no
renderer, no client runtime, no css rule, no docs entry. grep `Sources/` and
`designer/assets/` for `scrollAxes` / `visibleDomain` and nothing matches — the
only mentions left are this note and the changelog entry. every call was
therefore already a no-op, so the
consumer impact is a compile error on a call that did nothing; the replacement
for the intent is the plot's pan behaviour (`.chart__plot`) or a declared design
width (`.chartHeight` / `.chartAspectRatio`). this is a corrective, not a
deprecation cycle — say so here rather than silently breaking a promise.

## what is not stable (yet) — honest limits

these are real, documented constraints. depending on them as if they were
frozen surface is a mistake:

> **note (post-deletion):** the wasm monolith client (`WebUIClientRuntime`,
> `WebUIClient`, the chamber + content-addressed artifact) has been deleted. the
> engine is the client runtime; wasm survives only as capability islands. where a
> numbered item below refers to the client boot, it is historical — it is kept
> because the *limits* it names are still worth knowing, not because the path
> exists.

1. **session caps are a deployment policy.** `WebUIAuth`'s `AuthSessionStore`
   holds every live session until expiry; hosts that cap per-identity
   sessions must do so at login (`listSessions` / `invalidateAll` — see
   `ASSEMBLY.md`).
2. **there is no wasm client runtime.** the monolith client was deleted; the
   engine (`webui-engine.js`, the next-architecture default client for
   server-rendered pages, see `NEXT_ARCHITECTURE.md` d2) is the only client
   runtime, and wasm survives as per-capability islands. `ClientBoot(flavor: .wasm, …)`
   does not exist — a page that used it does not compile, which is the honest
   failure mode rather than a silent downgrade. the engine carries the full
   browser-mode keyboard surface — tree Enter/Space, composer enter-to-send,
   modal Escape-to-dismiss — plus modal focus trapping and focus return, probed
   in `designer/browser-smoke.mjs`. the capability-island authoring contract —
   including the resizable (client-re-render) door — is `Documentation/ISLANDS.md`;
   `ResizableIsland` and `ResizableIslandRegion` are additive surface in the
   frozen list, and the probe region in the smoke page is their live example.
   the typed door — `TypedIsland`/`TypedResizableIsland` and their regions, plus
   the `IslandEnvelope` frame — is additive surface too (+14 symbols in the
   frozen list), with `Documentation/ISLANDS.md` §3b as its contract and the
   `#island-chart` smoke region as the live example.
3. **modal focus management is engine-owned.** initial focus into a
   `WebUIModal` is still server-driven (the caller renders the modal open
   with the intended focus within its own markup); trapping and focus return
   are implemented and probed in
   `designer/browser-smoke.mjs` (Escape probe). the deleted wasm path kept
   none of this.
4. **`WebUIChart` pins live in `ChartTests`** and follow the same epoch, but
   charts are the youngest surface — treat them as the least battle-tested. the
   width/label contract has a second pin outside the unit suite:
   `designer/chart-mobile-audit.mjs` (six viewports × two themes; painted text
   ≥ 11px *and* the visible fraction of every plot).
5. **the wasm size/distribution trajectory is closed.** the monolith it
   described (size diet, per-SKU distribution) was deleted, so nothing here is
   post-1.0 scope any more. its replacement — islands, built per capability by
   the `wasm-island` verb — is described in `NEXT_ARCHITECTURE.md` §2c–§2d.
6. **the deprecation rule is a process rule, not a machine rule.** there is
   no CI or lint that can verify "one full minor before removal"; it is
   enforced by review against this document and the changelog. the in-repo
   enforcement (tests, the generated surface, the showcase byte-count pin)
   guarantees the *current* epoch's surface, not the *transition* between
   epochs. what *is* mechanical now is the removal act itself: deleting a
   public symbol from one of the eight modules fails the frozen-surface gate
   until the list is regenerated in a committing change — the timing rule
   ("one full minor of deprecation first") is the part that stays
   review-enforced.
7. **the applet harness is pre-2.0.** the harness's design doc
   (`WASM_APPLET_HARNESS.md`) was deleted with the wasm-era docs; the target
   contract — applet regions, renderer registry, expanded import surface, v2
   message shapes — is described in `NEXT_ARCHITECTURE.md` §2c–§2d. the v1
   wire/ABI pinned by this 1.0.0 epoch remains
   authoritative until the 2.0 epoch cut — the harness lands as an island
   capability, so the engine path and its pins stay untouched.
8. **error boundaries catch failures, not traps.** `ErrorBoundary` and
   `WebUIServerConfig.onRenderFailure` catch *failures* — a handler that
   throws and a render that throws, both surfaced as ordinary swift errors
   through the typed router. they do not catch swift *traps* (`precondition`,
   a force unwrap, an out-of-bounds index): a trap terminates the process and
   **no layer of this framework can intercept it in-process** — catching one
   would require the process isolation that is explicitly out of scope
   (restarting the page in a child process). keeping the two apart is the
   point of the boundary; pretending a boundary contains a trap would be a
   false guarantee. handler and render failures degrade gracefully (fallback
   markup, a 500 with the host's error page); traps take the process down —
   that is the contract.
9. **numeric/date formatting is host-side (w4.5).** `WebUIStrings` is the
   framework's own rendered strings — labels, aria names, default
   placeholders, toolbar chrome — resolved through the render context
   (`RenderContext.localized`, see `Localization.swift`): a page sets
   strings/locale/direction once (on the context, or declared on
   `WebUIDocument`, whose `locale` feeds `<html lang>` and whose `direction`
   feeds `<html dir>`) and every component in the pass reads the same
   catalog. a host overrides any subset; everything it omits keeps the
   english default, and the english defaults are pinned by the showcase byte
   gate (`showcaseArtifactByteCountIsPinned`) — a reworded default is a
   regression, not a pin to update.
   anything *formatted* — dates, times, numbers, currencies, plurals,
   weekday/month names — is deliberately outside the catalog: the framework
   renders strings, formatting belongs to the host, and no formatter ships.
   initializer default strings (a field's placeholder, a rail's title) keep
   their declared value at the call site rather than being re-resolved per
   render; a host localizing one passes the catalog's value explicitly.

## change discipline

- every public-surface change lands with (a) a test — in `APISurfaceTests`
  for the assembled W1-era surface, in the owning surface's suite otherwise —
  plus, for any change touching one of the eight frozen modules, a
  **regenerated** `Documentation/frozen-surface.symbols` (the gate names what
  regenerating restores), (b) `Documentation/DESIGN_SYSTEM.md` / `API.md`
  updates, (c) a `CHANGELOG.md` entry under `[unreleased]`, and where a
  component's look changes, (d) a browser check in **both** themes via the
  showcase/preview route.
- a change that moves the showcase's byte count updates the single
  `showcaseBytePin` constant **in the same commit**, justified there; a change
  that does not move it must not touch the constant.
- security fixes always land as patches **within** the current minor.
- no CI in this repo's gate story: the verification ladder is
  `swift build` → `swift test` (which includes the frozen-surface gate and the
  showcase byte pin) → `swift package --disable-sandbox plugin
  smoke` → `plugin fullstack-smoke` → `node designer/browser-smoke.mjs`,
  each self-contained and runnable by one human.
