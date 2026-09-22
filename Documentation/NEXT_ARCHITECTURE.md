# next architecture — clean-slate client/server restart proposal

_status: proposal (not executed) · 2026-09-22 · supersedes the wasm-only client runtime
direction of `WASM_BOOTSTRAP.md` / `WASM_TRAJECTORY.md` phase 5 for the default path;
the wasm machinery they describe is not lost — it is repackaged as capability islands
(see d3).

> cause this document exists: the wasm-only client was measured, not just argued. the
> shipped chamber fetches and instantiates the 55 mb module unconditionally on every
> app-mode page (`designer/assets/webui-client.js` boot → `fetch(opts.wasmUrl)`), then
> the module admits — in a comment on the wire — that it *cannot* render the server's
> views: "the server stays the page renderer … mount only module-owned
> `data-webui-applet` regions, and wire the /ws authority channel". the browser user
> therefore pays ~12 mb brotli + instantiate for what a 29 kb runtime did; and the
> developer's escape hatch for anything outside the blessed component set is
> un-type-checked html-string building. this proposal fixes the consumer cost and the
> developer substrate at the same time, without breaking the frozen surface.

## 1. principles (what the clean slate is for)

1. **author in swift; the web is a delivery surface.** this stays. the consumer never
   writes (or reads) javascript — including framework glue; the runtime is a shipped
   asset, an implementation detail, like every successful web framework's (liveview's
   morphdom, rails' turbo, svelte's compiler runtime).
2. **the server is authority.** persistence, auth, throttling, and render correctness
   live server-side (respects the locked decision d4 of `WASM_TRAJECTORY.md`). the
   client is a fast, honest servant.
3. **zero third-party dependencies.** unchanged — swift (incl. the official swift wasm
   sdk, an apple/ospo tool, not a dependency per the existing rule), stdlib, swift-log.
4. **security invariants never weaken.** csp+nonce, sanitization, csrf, escaping,
   caps, bounded wire parsing — all as documented in `AGENTS.md` (invariant list
   applies to the new engine too: it patches only trusted server bytes + sanitized
   island output).
5. **no capability ships when it isn't used.** progressive enhancement is the default
   posture: every feature (wasm island, offline, worker offload) is opt-in per page and
   degrades to the base path when absent.
6. **the frozen consumer surface does not change.** `View`, `render() -> String`,
   modifiers, components, `FragmentUpdate` — the public contract and its pins
   (`APISurfaceTests.swift`) keep passing. everything below is internal.

## 2. target architecture

```
┌──────────────────────────── HTTP SERVER (your app) ────────────────────────────┐
│  View Tree (structs) ─→ HTMLDocument ─→ SSR HTML (first paint, semantic)        │
│        │                                   │                                     │
│  EventRouter ←── /ws authority ←── ────────┘  (capture → optimistic → patch)    │
│        │            │                                                            │
│  FragmentUpdate / patch ops ──→ engine apply (scroll/focus/a11y survive)        │
└────────┬──────────────────────────────┬──────────────────────────────────────────┘
         │                              │
   ┌─────▼──────────────────┐   ┌──────▼───────────────────────────┐
   │ base client: the engine │   │ wasm capability islands (lazy)   │
   │ ~30 KB js, deterministic,│   │ webui-validate / -search /      │
   │ no deps, shipped asset   │   │ -chart / -offline … kB-tier     │
   └─────────────────────────┘   │ same compiled swift, per-SKU     │
                                 └──────────────────────────────────┘
```

### layer a — authoring (unchanged for the consumer)

`View { func render() -> String }` stays the public contract. internally, nothing
forces a rewrite: the restart does **not** introduce a view IR as a gate. an internal
`Element` tree is added only where it pays (see p3, optional): tree diffing for patch
minimization, and a typed contract for wasm islands to avoid string marshaling in hot
paths (charts, virtualized lists). it never leaks into the public api.

### layer b — the engine (new base client runtime)

a single framework-owned javascript module (~30 kb raw / ~10 kb gz), deterministic,
dependency-free, shipped as a content-addressed asset. it replaces **both** the retired
`webui-runtime.js` and today's `webui-client.js` chamber (35.6 kb) + `webui-worker.js`
(11 kb) as the default:

- event capture on the existing contract: `data-component-id` + `data-event`, with
  `targetId`/`targetClass` on every click; the engine delivers exactly the events a
  component declares (no hover/press noise) — same rules as today.
- optimistic apply: render-time `data-optimistic` predictions applied same-turn,
  rollback after `optimisticSettleMs` if the server never confirms (already modeled in
  the framework; ported into the engine).
- transport: `/ws` authority, ping/pong, reconnect with backoff, render-token
  echo (the binding invariant is preserved).
- patch apply: `FragmentUpdate` replacements, sanitized fragment subtrees,
  scroll/focus/selection survival (the fragment save/restore work carries over).
- **keyboard + focus (closes a documented gap):** tree enter/space, composer
  enter-to-send, modal escape-to-dismiss, modal focus trap + focus return. the wasm
  `ClientRuntime` never mirrored these (`STABILITY.md` #2–3); the engine makes them
  unconditional, so the gap disappears instead of staying "planned".
- motion hooks: `view-transition` integration + the 300 ms ease system, with
  `prefers-reduced-motion` respected, purely additive over the css.

zero consumer-facing api — consumers never import, call, or read it. it is a runtime,
not a language.

### layer c — wasm capability islands (where wasm actually levels up)

wasm stops being "the client" and becomes a **per-capability library**: small
embedded-tier modules of the same compiled swift, built per island (the foundation-
free core already exists; embedded tier is kB-scale per `WASM_TRAJECTORY.md` §
"tiered client products"). examples: `webui-validate`, `webui-search`, `webui-format`,
`webui-chart`, `webui-offline`.

- a page declares capabilities in its meta (`.capabilities`), the engine fetches the
  matching content-addressed modules **lazily** and only when present.
- absent module → the page is fully server-rendered + engine-driven; zero loss.
- region contract inherited from the applet harness: `<div data-webui-island=…>` →
  module renders → sanitized → mounted; `data-webui-applet-state` probing stays.
- worker offload (cross-origin-isolated pages), the sab mailbox, binary frames
  (`[0x64][kind]…`), and indexeddb persistence survive as **island-internal**
  mechanisms — they were good engineering, they were just mis-scoped as the
  everything-runtime.
- parity claim scoped honestly: islands guarantee **logic** parity by construction
  (same swift, same tests). **ui** rendering is not required to be client equal —
  the server owns rendering; islands own hot re-render + logic. this is the
  inversion of the old d2 thesis, and it matches what the module could actually do.

### layer d — delivery

- shell: html + css (minified, csp nonce per render) + engine — cacheable and
  immutable via content addresses; brotli everywhere (`Content-Encoding: br` +
  `Vary: Accept-Encoding`, per `WASM_BOOTSTRAP.md` wire-compression note).
- wasm: islands content-addressed + immutable; no default 55 mb fetch — ever.
- service worker (opt-in capability): shell caching + background reconcile, through
  through the existing applet harness machinery — the `clientMode` isolation headers
  are only needed by pages that actually take the worker path.

## 3. what dies, what is mothballed

| artifact | treatment | note |
|---|---|---|
| `webui-client.js` (35.6 kb chamber) | replaced by the engine | its event proxy was the whole reason the monolith stayed on every page |
| `webui-worker.js` (11 kb) | merged into engine/worker-island path | offload stays, scoped to islands |
| `WebUIClient.wasm` (~55 mb) as default boot | dropped from the default path | kept only if applet consumers remain, otherwise deleted; `WebUIWasmPlugin` hard-fail softened to a per-capability existence check |
| `webui-runtime.js` (29 kb) | already retired; do not resurrect wholesale | the engine's feature set is a superset in the places that matter (optimistic, a11y, scroll/focus) |
| server core, `EventRouter`, `FragmentUpdate`, csp/nonce, security invariants | kept | this half is right |

## 4. phased migration (in-repo gates only; no ci)

- **p0 (baseline):** engine ships as `engineMode` alternate boot; both boots answer
  the existing gates (`plugin smoke`, `plugin fullstack-smoke`,
  `node designer/browser-smoke.mjs`); no behavior change for wasm pages.
- **p1 (flip default):** engine is the default for server-rendered pages; the
  monolith path remains for applet/client pages. port optimistic, scroll/focus
  survival, and the keyboard/focus affordances into the engine; add engine-path
  tests for each gap item from `STABILITY.md` #2–3.
- **p2 (islands):** per-capability embedded builds via a `wasm-island` plugin verb
  (reusing the isolated scratch-root trick); capability manifest in document meta;
  lazy fetch + degrade path; island gates per capability.
- **p3 (optional diff):** internal `Element` tree + server-side connection cache for
  minimal patch ops, additive to `FragmentUpdate` (superset field, negotiated; the
  frozen envelope stays byte-compatible). only if measured patch bytes/frames
  matter.
- **p4 (progressive capability):** service-worker shell + offline reconcile island;
  view-transition hooks.
- **p5 (sunset):** remove the monolith default; update `ARCHITECTURE.md`,
  `STABILITY.md`, skills, and the consumer docs to the new reality.

## 5. ux budget (measured 2026-09-22, headless chromium on loopback)

| metric | target | measured today |
|---|---|---|
| first contentful paint (4g) | < 1 s | domcontentloaded + load ≈ 19 ms on loopback (fcp untracked under headless paint entries) |
| time-to-interactive | engine byte loaded | engine instance + `/ws` connected ≈ 38 ms after nav start |
| critical-path javascript | ~30 kb raw / ~10 kb gz | engine 37.4 kb raw (host gzip/brotli is a serving concern — the 9090 example server does not compress; gzipped ≈ 10 kb) |
| page shell bytes | — | sample page: 310 kb raw incl. inline minified design css (~40 kb gz); island artifact 164 kb (embedded sdk, stripped) |
| interaction latency | optimistic same-turn; server confirm | same-turn prediction + confirm over `/ws` (measured by browser-smoke probes) |
| keyboard parity | full (tree enter/space, escape-dismiss, focus trap + return) | implemented + probed in `designer/browser-smoke.mjs` (engine path) |
| offline | opt-in island; reconcile on reconnect | offline capability → service-worker shell (cache-first engine/css + `/__assets`, network-first navs); engine reconnects on `online`. indexeddb sync reconcile is deferred (needs the worker/bridge machinery — see p4 note in `NEXT_IMPLEMENTATION_PLAN.md`) |
| contrast | wcag aa | guarded by `DeploymentIntegrityTests` wcag-ratio assertions (≥ 4.5:1) |
| wasm on the default page | none | none — `meta[name="webui-wasm"]` absent on the engine default page |

## 6. risks — argued honestly (the skeptic's case)

1. **"this is going back to webui-runtime.js."** yes and no. the engine keeps the
   good parts of the old runtime and closes its gaps (optimistic apply, scroll/focus
   survival, keyboard parity were all *post*-runtime work), and it gains the island
   path the old runtime never had. but the honest framing: this accepts the
   liveview-class architecture — which *has* shipped top-tier ux at web scale — over
   a wasm-only architecture that no ui framework has shipped at scale (tokamak
   remains a niche/research project). the burden of proof sat with wasm; it did not
   deliver it.
2. **"two runtime paths = double the test surface."** mitigated: the island abi is
   narrow (region render + declared capability imports — the applet contract), and
   the base path is single. gates are in-repo per owner rule.
3. **"you lose deterministic same-language rendering."** the 90% case never had it — the
   module cannot render server views (its own comment). islands restore it exactly
   where it pays. nothing that worked is lost.
4. **"swift wasm toolchain pain remains."** yes — the swiftly-shim + scratch-root
   build stays, but it becomes per-island and small (kb-scale, fast builds) instead
   of one 55 mb monolith.
5. **"the design-system css is already 327 kb."** served minified with brotli it is
   ~40 kb gz; per-sku token pruning is a later optimization, not architectural.
6. **"the engine is still javascript."** — by design. consumer never writes or reads
   it; it ships with the framework and is versioned with it. the old sin was
   treating *framework-owned runtime code* as equivalent to *writing the app in js*.

## 7. decision log (to lock with the owner)

| # | decision | owner | status |
|---|---|---|---|
| d1 | frozen consumer surface (view/render/modifiers/components/fragmentupdate) unchanged; restart is internal | design | proposed |
| d2 | base client = single framework-owned engine (~30 kb), optimistic + scroll/focus + full keyboard parity; no consumer js | design | proposed |
| d3 | wasm = capability islands (embedded tier, lazy, optional); monolith dropped from default; worker/sab/binary-frames/idb become island-internal | design | proposed |
| d4 | server remains authority; islands advisory only | user | stays locked |
| d5 | parity scoped to **logic** (same swift); ui rendering stays server-owned | design | proposed |
| d6 | shell + engine + css cacheable/immutable/brotli; no mandatory binary on any page | design | proposed |
| d7 | no ci gates; in-repo ladder only | user | stays locked |
| d8 | p3 diff protocol only if measured payoff on patch bytes | design | open |
