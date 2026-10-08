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
(`WebUI`, `WebUIDesignSystem`, `WebUIAuth`, `WebUIChart`). it is enforced by
**`Tests/WebUITests/APISurfaceTests.swift`**: every public initializer is
referenced at compile time (a signature change fails the build) and every
component's render contract — class/role/aria/escaping markers — is
asserted. not every frozen name is pinned *here*, though — some are pinned by
another suite or by the demo page that renders them: `WebUIMenubar` is
constructed only in `WebUISmokeTest` and `WebUIBlocks`, `ClientBoot` in
`EngineBootTests`/`CSPExtrasTests`, `DesignSystemAssets` in `ThemeSheetTests`
and the deployment-integrity suites. equivalent as a build-time guard, which is
what the promise needs, though a demo-page pin catches a signature break and not
a marker break. a full count of pin coverage is measured in *measured
consumption* below.
`Tests/WebUITests/ChartTests.swift` pins the chart product, the
`WebUIAuth` signatures are pinned by the same suite's `authSurfacePins`
(behavior by the `WebUIAuthTests` suites), and the wire/runtime contracts
are pinned by `WebUIClientTests` + `DeploymentIntegrityTests`.

the frozen surface is:

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
  client-runtime suites and the byte-identity asset tests.

### measured consumption (re-measured 2026-10-08)

the frozen list above is a **promise**, not a usage report. a survey of every
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
freezes them, and that is now a one-line edit to the list above.

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
   in `designer/browser-smoke.mjs`.
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
   enforcement (tests, byte-identity pins) guarantees the *current* epoch's
   surface, not the *transition* between epochs.
7. **the applet harness is pre-2.0.** the harness's design doc
   (`WASM_APPLET_HARNESS.md`) was deleted with the wasm-era docs; the target
   contract — applet regions, renderer registry, expanded import surface, v2
   message shapes — is described in `NEXT_ARCHITECTURE.md` §2c–§2d. the v1
   wire/ABI pinned by this 1.0.0 epoch remains
   authoritative until the 2.0 epoch cut — the harness lands as an island
   capability, so the engine path and its pins stay untouched.

## change discipline

- every public-surface change lands with (a) a test in `APISurfaceTests`
  (signature + render marker), (b) `Documentation/DESIGN_SYSTEM.md` /
  `API.md` updates, (c) a `CHANGELOG.md` entry under `[unreleased]`, and
  where a component's look changes, (d) a browser check in **both** themes
  via the showcase/preview route.
- security fixes always land as patches **within** the current minor.
- no CI in this repo's gate story: the verification ladder is
  `swift build` → `swift test` → `swift package --disable-sandbox plugin
  smoke` → `plugin fullstack-smoke` → `node designer/browser-smoke.mjs`,
  each self-contained and runnable by one human.
