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
`[String: JSONValue]` during the wasm migration — see
`WASM_TRAJECTORY.md` for why).

the canonical list of what may not change in a minor/patch is known as the
**frozen surface**.

## the frozen surface

the frozen surface is the consumer-facing API of the library products
(`WebUI`, `WebUIDesignSystem`, `WebUIAuth`, `WebUIChart`). it is enforced by
**`Tests/WebUITests/APISurfaceTests.swift`**: every public initializer is
referenced at compile time (a signature change fails the build) and every
component's render contract — class/role/aria/escaping markers — is
asserted. `Tests/WebUITests/ChartTests.swift` pins the chart product, the
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
  `WebUISpinner`, `WebUIProgress`, `WebUISkeleton`, `WebUIModal`,
  `WebUIToast`, `WebUITooltip`, `WebUITimeline`, `WebUIBreadcrumb`,
  `WebUIStat`, `WebUIPagination`, `WebUIAlert`, `WebUIChip`,
  `WebUIDescriptionList`, `WebUIReasoningBlock`, `WebUIToolStep`,
  `WebUITurnSummary`, and the shell set (`WebUISidebar`,
  `WebUISegmentedControl`, `WebUISearchField`, `WebUIListView`,
  `WebUIListItem`, `WebUIComposer`, `WebUIPanel`, `WebUISelect`).
- document/assembly: `WebUIDocument` (title/body/`includeRuntime`/
  `runtimeConfig`/`contentSecurityPolicy`/`theme`/`rawStyles`/`clientMode`),
  `RuntimeConfig`, `WebUITheme`, `@Theme`, `DesignToken`.
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

## what is not stable (yet) — honest limits

these are real, documented constraints. depending on them as if they were
frozen surface is a mistake:

1. **session caps are a deployment policy.** `WebUIAuth`'s `AuthSessionStore`
   holds every live session until expiry; hosts that cap per-identity
   sessions must do so at login (`listSessions` / `invalidateAll` — see
   `ASSEMBLY.md`).
2. **the wasm client is not the default runtime anymore; it is a partial
   mirror.** the engine (`webui-engine.js`, the next-architecture default
   client for server-rendered pages, see `NEXT_ARCHITECTURE.md` d2) carries
   the full browser-mode keyboard surface — tree Enter/Space, composer
   enter-to-send, modal Escape-to-dismiss — plus modal focus trapping and
   focus return. the wasm `WebUIClient` remains available via an explicit
   `ClientBoot(flavor: .wasm, …)` (applet/client-mode pages) and keeps its
   own limitations: it does **not** mirror the keyboard affordances, and its
   `sources/WebUIClientRuntime` does not render the server's views. the boot
   flip rides the `clientMode` experimental-surface carve-out — page-contract
   pins are test-internal and were retargeted with the flip.
3. **modal focus management is engine-owned.** initial focus into a
   `WebUIModal` is still server-driven (the caller renders the modal open
   with the intended focus within its own markup); trapping and focus return
   for the engine path are implemented and probed in
   `designer/browser-smoke.mjs` (Escape probe). the wasm client path keeps
   none of this (see #2).
4. **`WebUIChart` pins live in `ChartTests`** and follow the same epoch, but
   charts are the youngest surface — treat them as the least battle-tested.
5. **phase 6 of the wasm trajectory** (size diet + per-SKU distribution) is
   post-1.0 scope; it changes distribution and payload size, never the
   frozen surface.
6. **the deprecation rule is a process rule, not a machine rule.** there is
   no CI or lint that can verify "one full minor before removal"; it is
   enforced by review against this document and the changelog. the in-repo
   enforcement (tests, byte-identity pins) guarantees the *current* epoch's
   surface, not the *transition* between epochs.
7. **the applet harness is pre-2.0.** `WASM_APPLET_HARNESS.md` is the target
   contract (applet regions, renderer registry, expanded import surface,
   v2 message shapes). the v1 wire/ABI pinned by this 1.0.0 epoch remains
   authoritative until the 2.0 epoch cut — the harness lands behind
   `clientMode` so the JS-runtime path and its pins stay untouched.

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

> **note (post-deletion):** the wasm monolith client (`WebUIClientRuntime`,
> `WebUIClient`, the chamber + content-addressed artifact) has been deleted. the
> engine is the client runtime; wasm survives only as capability islands. any
> reference to the client boot below is historical.
