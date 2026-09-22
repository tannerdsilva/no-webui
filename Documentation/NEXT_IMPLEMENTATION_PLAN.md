# next architecture implementation plan

> **for hermes:** execute phase-by-phase; each task is a small, verifiable step.
> this plan is the companion to `NEXT_ARCHITECTURE.md` (d1–d8) and replaces the
> wasm-only default direction of `WASM_BOOTSTRAP.md` / `WASM_TRAJECTORY.md` phase 5.

**goal:** move no-webui to the engine-first architecture — a ~30 kb engine as the
default client, wasm as lazy capability islands — with the frozen consumer surface
and every security invariant intact.

**architecture:** server stays authoring + authority (ssr, `EventRouter`, `/ws`,
`FragmentUpdate`); the engine (framework-owned js, ~30 kb) captures events on the
existing `data-component-id`/`data-event` contract, applies optimistic + server
patches, preserves scroll/focus, and adds full keyboard parity; wasm islands
(same compiled swift, embedded tier, kB-scale) load lazily by capability and
degrade to ssr+engine when absent. see `NEXT_ARCHITECTURE.md` layer b/c for the
diagram and `section 5` for the ux budget.

**tech stack:** swift 6.4 (+ official wasm sdk via swiftly for islands), swift-nio,
swift-log, the in-repo asset/icon/wasm plugins, node + playwright only as the
verification driver (no ci — owner rule).

**constraints (living):**
- zero third-party deps (the official swift wasm sdk is a tool, not a dependency).
- no comments in shipped web assets — the engine, css, and generated html are
  comment-free; the first law applies.
- no ci gates; close every phase with the in-repo ladder:
  `swift build` → `swift test` → `swift package --disable-sandbox plugin smoke` →
  `plugin fullstack-smoke` → `node designer/browser-smoke.mjs`.
- token-only values in new css; no raw px/hex; both themes audited.
- never touch the frozen consumer surface (`View`, `render()`, modifiers,
  components, `FragmentUpdate`) — additive optional params only (see risks r1).

## phase map

| phase | goal | exit gate |
|---|---|---|
| p0 | engine exists, boots as an opt-in alternate mode | ladder green in both modes |
| p1 | engine is the default for server-rendered pages; a11y parity | ladder green + keyboard probes |
| p2 | capability islands (build, lazy load, degrade) | per-capability gates + 404-degrade probe |
| p3 | optional: server-side tree diff (spike first) | spike results + ladder green |
| p4 | progressive capabilities: service worker, offline, view transitions | browser smoke in both themes |
| p5 | sunset monolith default; docs/skills rewrite | full ladder + size/ux audit recorded |

---

## p0 — baseline: the engine as an alternate boot

goal: ship the engine and prove it drives the existing smoke page end-to-end while
the wasm boot keeps working. no behavior flips yet.

### task 0.1 — engine asset skeleton

- create `designer/assets/webui-engine.js` — iife, no comments, ~30 kb target:
  `WebUIEngine.init({wsUrl, renderToken, debounceMs, reconnectMs, settleMs})`;
  internally: `capture` (delegated listener, `data-component-id`+`data-event`
  filter, `targetId`/`targetClass` on click), `transport` (ws `/ws`, ping/pong,
  reconnect + backoff, render-token echo), `applyUpdates` (fragment replace +
  sanitize via detached-subtree parse-strip, `me.remove()` empty-fragment branch),
  `open`/`close` lifecycle, `console`-silent error handling.
- verify immediately: open `designer/previews/designer-preview.html`-style page or
  a minimal served page with the engine script and confirm no console errors.
- rule: replicate the runtime's byte discipline — no comments, no trailing
  whitespace on wire; lint by `grep -c '//'` in the asset at build time (add to
  `WebUIAssetPlugin.swift` check or a `designer/` script).

### task 0.2 — asset registration

- modify `Plugins/WebUIAssetPlugin/WebUIAssetPlugin.swift`: include
  `webui-engine.js` in the asset scan list (it currently produces
  `Assets+Generated.swift` entries for css + js; add the engine like
  `webui-runtime.js` was handled).
- run `swift build`; confirm `Assets+Generated.swift` now exposes the engine bytes
  (e.g. `WebUIAssets.engine`) — locate the generated file under
  `.build/plugins/outputs/no-webui/WebUI/destination/…`.

### task 0.3 — boot option

- modify `Sources/WebUI/ClientBoot.swift`: add `public enum Flavor { case engine,
  wasm }` + `Flavor` param to `init` (default `.wasm` keeps today's behavior);
  `headMarkup()` emits, for `.engine`: `<meta name="webui-config" content="…">`
  first (config-meta ordering gotcha), then `<script nonce src="/ui/webui-engine.js">`.
  the existing `webui-wasm` meta + chamber/boot scripts stay for `.wasm`.
- add a render-contract test in `Tests/WebUITests/` pinning the compound markers
  for both flavors (e.g. `webui-config` meta + `webui-engine.js` script url;
  `webui-wasm` meta + `webui-client.js` url) — never a bare word.

### task 0.4 — serving route

- extend `Sources/WebUI/WebUIBoot.swift` (and the asset route builders in
  `WebUIExample/main.swift`, `Sources/WebUISmokeTest/main.swift`,
  `Sources/WebUIShowcaseServer/main.swift`): serve `/ui/webui-engine.js` from
  `WebUIAssets.engine`, immutable + content-type `text/javascript`.
- gate: `swift build` then `swift package --disable-sandbox plugin smoke` — the
  smoke byte-integrity check must now also verify the engine route (extend
  `Plugins/WebUISmokePlugin/WebUISmokePlugin.swift`).

### task 0.5 — engine-mode gate drives

- parametrize `designer/browser-smoke.mjs` (env `WEBUI_BOOT=engine|wasm`): for
  `engine`, assert the counter reaches `2` via the `/ws` proxy path, echo round
  trip, optimistic patch + rollback, scroll survival — the same probes the wasm
  mode runs; note the probe currently targets `window.WebUIClient._getInstance()`
  and must switch to `WebUIEngine._getInstance()` in engine mode.
- same for `designer/fullstack-smoke.mjs` (env switch; the ws envelope is
  unchanged so server-side asserts are untouched).
- exit: `swift build`, `swift test`, `plugin smoke`, `plugin fullstack-smoke`,
  `node designer/browser-smoke.mjs` (both modes) all green. commit per task.

---

## p1 — flip the default + a11y parity

goal: server-rendered pages boot the engine by default; the monolith becomes the
opt-in; keyboard/focus gaps from `STABILITY.md` #2–3 close.

### task 1.1 — default flip

- `ClientBoot` default `Flavor = .engine`; `.wasm` remains for pages that declare
  applets or pass `clientMode: ClientBoot(wasmURL:…)` explicitly
- update pins: `Tests/WebUITests/` render-contract tests that assert the
  `webui-wasm` meta now assert the engine markers; the fullstack-smoke bootstrap
  check retargets from `webui-wasm` meta to the engine script/meta.
- `Sources/WebUISmokeTest/main.swift` (`WebUISmokePlugin` page) keeps an
  explicit `ClientBoot(wasmURL:…, flavor: .wasm)` route so the wasm path stays
  gate-covered (byte-identity + applet mount) — this is the 24-`data-component-id`
  count page; do not change its interactive surface, only its boot.

### task 1.2 — optimistic + fragment save/restore in the engine

- port from the chamber/runtime: `data-optimistic` json-array → apply same-turn →
  rollback after `settleMs` (5 s default, `RuntimeConfig.optimisticSettleMs`);
  patch-time save/restore of `scrollTop`/`scrollLeft`/`value`/`checked`/
  `caret`/non-form `[tabindex]` focus.
- tests: `designer/browser-smoke.mjs` engine-mode optimistic probe (wasm mode has
  one; replicate); a `WebUIClientTests`-level unit if the logic is extracted
  (engine is js — verification is browser-level; keep the probes in `.mjs`).

### task 1.3 — keyboard parity

- implement in the engine: tree row Enter/Space activation, composer
  enter-to-send (`WebUIComposer` submit path), modal Escape-to-dismiss +
  focus trap + focus return, global keys above the `data-event` filter (the
  declared-event filter must not swallow Escape — see skill gotcha).
- probes in `designer/browser-smoke.mjs`: keyboard-driven counter increment (tab
  to button, Enter), Escape closes a `WebUIModal` and focus returns to the opener.
- `STABILITY.md` #2/#3 update: mark resolved (engine path) with the test row.

### task 1.4 — both-theme audit

- `node designer/browser-smoke.mjs` screenshots (light + dark) to `.smoke/`; use
  the playwright audit recipe (`emulateMedia({colorScheme:'dark'})`); assert dark
  bg flips (`rgb(6,9,16)`), no console errors from your origin, and the smoke
  page interactive count still 24 (`WebUISmokePlugin.swift` expectation).
- exit: full ladder green, screenshots reviewed, no console errors.

---

## p2 — capability islands

goal: same-swift logic moves into small lazy modules; pages that don't declare a
capability never fetch wasm.

**measured outcome (p2 landed):** the full-stdlib-sdk island
(`WebUIValidateIsland`, pure swift, `-Osize`, stripped) is **52.8 mb** — every
standalone module re-links the sdk's ICU/full-stdlib tables, so the
"kB-scale island" target is not met by the full-stdlib sdk. the embedded sdk
(`swift-6.4.0-RELEASE_wasm-embedded`) **cannot compile the dependency graph**:
`swift-log` is not embedded-compatible (`'description' has been explicitly
marked unavailable`). the kB-tier is blocked until island targets drop the
`Logging` edge (an embedded-clean log shim for `WebUICore`) — recorded as the
phase-6 follow-up, not achievable here.

### task 2.1 — island build verb

- new command plugin `WebUIIslandPlugin` (`verb: wasm-island`, model on
  `Plugins/WebUIWasmClientPlugin/WebUIWasmClientPlugin.swift`): cross-build a
  named product with the official wasm sdk via the swiftly shim into an isolated
  `.build/wasm-island-scratch` root (never the package `.build` — deadlock), then
  copy the stripped artifact (default `--no-strip` flag retained as in
  `wasm-client`) to `.build/out/Products/…/<product>.wasm`.
- register in `Package.swift` products/plugins sections; verify by building a
  trivial island product and confirming the artifact lands + hashes.

### task 2.2 — island products (reuse what exists)

- `WebUIClientRuntime` already ships the logic (`ClientFieldValidator`,
  `ClientPrefixIndex`, `ClientStateStore`, `ClientSyncCoordinator`) — package as
  thin executable products:
  - `WebUIValidateIsland` — exports `webui_render_region`/`webui_validate` for
    `data-webui-island="validate"`;
  - `WebUISearchIsland` — local search over a region;
  - `WebUIChartIsland` — client-side chart re-render (hot path) after p3 if
    measured; initially only validate + search.
- constrain each to the foundation-free core subset (already true for
  `WebUIClientRuntime`); confirm size is kB-scale (target < 100 kb each).

### task 2.3 — capability manifest + lazy loader

- `RuntimeConfig.capabilities` (existing seam) rides `webui-config`; the engine
  reads it and lazily fetches `/__assets/webui-<name>.<sha>.wasm` only for
  declared capabilities (meta order gotcha: config meta before script).
- `Sources/WebUI/WebUIBoot.swift` gains `islandURL(name:hash:)`; islands hash
  through `WebUIWasmTool` (generalize the tool from the single client artifact to
  per-name artifacts) and `WebUIWasmPlugin` emits per-island `present` carriers.
- landing: fetch → instantiate (`WebAssembly.instantiate`) → validate export
  surface → render region → sanitize (reuse the runtime's detached-subtree
  strip) → mount + stamp `data-webui-applet-state` (rename docs to `island`).

### task 2.4 — degrade path

- absent/404 module: warn once in console, page stays fully interactive via
  ssr+engine (`data-webui-island-state="unmapped"`), no error surface.
- probe: serve a page declaring `validate` capability without the artifact;
  assert no console error, no wasm fetch, and the region falls back.

### task 2.5 — first island e2e

- `WebUISmokeTest` page gains a `validate` island region; test: client-side
  validation marks an invalid field without a round trip; the same validator
  logic passes server-side tests (`WebUIClientTests` unchanged = parity).
- exit: `wasm-island` build green per island; `swift test`, `plugin smoke`,
  `plugin fullstack-smoke`, `browser-smoke` green; island fetch count asserted
  via network capture (only when declared).

---

## p3 — optional: server-side tree diff (spike first)

- spike (no commitment): on `WebUISmokeTest` routes, render the page twice and
  derive a diff (string- or token-level) against the previous render per socket;
  measure bytes/frames saved vs whole-fragment replace on the counter/echo/table
  routes.
- only if measurable (>30% patch bytes on the table route): introduce an internal
  `Element` IR in `Sources/WebUICore/` (value-type node tree; `render()` becomes a
  projection — public surface unchanged by construction) + per-connection
  render cache; `FragmentUpdate` gains an additive `ops` array (old `html` field
  stays the fallback; wire stays byte-compatible per d5).
- if the spike shows <30%: record the number in the doc and close p3 as no-op
  (yagni; the fragment envelope is simpler and already survives scroll/focus).

## p4 — progressive capability

- p4.1 service worker: `designer/assets/webui-shell.js` — cache-first for
  engine/css/shell, network for islands; registered only when the page declares
  `offline`. engine exposes `_registerShell()`; degrade: no sw → no change.
- p4.2 offline: `WebUIOfflineIsland` wraps `ClientSyncCoordinator` +
  `ClientStorePersistence` (indexeddb); reconcile on reconnect; server remains
  authority (d4) — island is advisory gating only.
- p4.3 motion: engine hooks `document.startViewTransition` (fallback: no-op) when
  not reduced-motion; design-system.css gains a `::view-transition` group so card
  swaps animate on the 300 ms ease system; `@media (prefers-reduced-motion)`
  disables.

## p5 — sunset

- p5.1 default removal: `WebUIAssets.client`/`.clientBoot` routes and the
  `WebUIClient.wasm` default boot removed; `WebUIWasmPlugin` hard-fail softened
  to per-island existence checks (islands only); `WebUIClient` product retained if
  applet consumers exist, else deleted after `Documentation/wasm-*` docs are
  archived.
- p5.2 docs rewrite: `Documentation/ARCHITECTURE.md` (new diagram + engine/island
  layers), `STABILITY.md` (resolved gaps; new known limits — e.g. engine-only
  bootstrap, island build requires swiftly shim), `API.md`/`GETTING_STARTED.md`
  (boot flavors), `AGENTS.md` (plugin table: `wasm-island`; serving contract:
  engine route; first law: engine is js — no comments), `README.md`, and the
  `webui-design-system` skill + `references/wasm-only-delivery.md` →
  `references/engine-delivery.md` (document contract now engine-first; serving
  routes `/ui/webui-engine.js`, capability meta, island routes).
- p5.3 cleanup: delete `designer/assets/webui-client.js`/`webui-worker.js` +
  stale boot scripts if no gate references them; remove the wire comment
  `// the server stays the page renderer…`; `webui-runtime.js` deletion if still
  present at this point; run `WebUIIconTool`/`WebUIAssetTool` lints.
- p5.4 ux audit recorded: playwright light+dark on `WebUIExample` and showcase;
  record transfer sizes (engine ~10 kb gz, css ~40 kb gz), fcp, tti, interaction
  latency, keyboard walk, contrast check; append the numbers as a table in
  `NEXT_ARCHITECTURE.md` §5. exit: full ladder green; no `data-webui-applet`
  references outside islands; no console errors.

---

## risks & open questions

- **r1 (epoch):** flipping the default boot changes the page contract (meta +
  scripts) that render-contract tests pin. compile-time pins are unaffected
  (additive init params), and the contract pins are test-internal — but confirm
  with the owner whether the default-flip needs an epoch line before p1 (the
  wasm migration itself skirted this via the "experimental surface" carve-out).
- **r2 (a11y):** engine keyboard parity must match the *prior* js runtime
  behaviors exactly (tree/composer already existed in `webui-runtime.js`); modal
  trap + focus return are new — treat as designed behavior with its own tests.
- **r3 (wasm toolchain):** islands keep the swiftly-shim requirement; per-island
  builds are fast but the dev-only cost remains — document it once in
  `AGENTS.md`; never auto-run the build (owner rule: explicit command only).
- **r4 (concurrency):** user edits this repo concurrently — check mtime/diff
  before blaming a failing gate; never start a gate while `serve` is up (`.build`
  lock).
- **r5 (scope creep):** p3 is explicitly conditional; p4 only after p1–p2 land.
  the value ordering is p0→p1 (consumer fix) then p2 (dev parity) — everything
  after is polish, not gate.
