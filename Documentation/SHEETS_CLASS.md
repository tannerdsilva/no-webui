# sheets-class target — capability gap analysis and phased path

_status: proposal (not executed) · 2026-10-02 · companion to `NEXT_ARCHITECTURE.md`
(engine-first, d1–d8) and `NEXT_IMPLEMENTATION_PLAN.md` (p0–p5); cross-references
`STABILITY.md` (#7, the applet harness) and the `CHANGELOG.md` unreleased block
(fragment ops)._

> cause this document exists: the engine-first restart settles *what the default
> client is*. it does not answer *what the framework must grow so a sheets-class
> application — an interactive grid with local-first editing, hundreds of
> thousands of cells, and collaboration — is buildable with it*. this is that gap
> analysis, measured against the tree as it stands (2026-10-02) and phased as
> framework work. no phase is a promise; s0 gates everything after it.

## 1. verdict

the direction is right and stays: server authority + a framework-owned engine +
lazy wasm capability islands is the same split a sheets-class product uses — the
server owns the document and the truth, the client owns the hot rect. the gap is
that **nothing today owns the hot path**:

1. every interaction round-trips `/ws`; typing is debounced 300 ms trailing /
   1 s max-wait by design, and optimistic prediction is render-time and
   value-independent — it cannot predict text.
2. there is no scale-rendering strategy for grids: `WebUITable` renders every row
   server-side, the demo re-emits the whole table per interaction, and there are
   zero virtualization primitives in the tree.
3. there is no data/compute layer (no formula engine, no formats, no document
   store) and no collaboration or offline-document machinery.
4. the island ABI is a one-shot region renderer — islands cannot host a hot path
   today even in principle (stub host imports, no event stream in,
   sanitize-per-render out).

items 1–3 are framework work of known shape; item 4 gates the first milestone of
the sheets arc. §5 answers the timing question — go to wasm when the budget is
structurally below rtt, not one interaction earlier.

one piece landed *in support of* this: the fragment envelope already carries
patch ops (`replace` / `append` / `text`), queued application, and
collapse-to-newest semantics (`CHANGELOG.md` unreleased;
`Sources/WebUICore/WebSocketProtocol.swift:10-54`;
`designer/assets/webui-engine.js:732-752`). a cell write is now expressible as a
`text` op — a characterData write, zero element churn. a grid still lacks the
server-side diffing and the row/range ops, not the envelope.

## 2. measured today (evidence)

| measurement | number | evidence |
|---|---|---|
| engine (the default client runtime) | 52,433 B raw, 1,579 lines; on every page | `wc -c designer/assets/webui-engine.js` |
| fragment ops | `replace` (default, absent on the wire) / `append` / `text`; queued, last-write-wins collapse; unknown ops warn and skip | `Sources/WebUICore/WebSocketProtocol.swift:10-54`; `webui-engine.js:681-752` |
| island call abi | json in ≤ 65,536 B, html out (frame buffer 262,144 B), synchronous, one region per call | `webui-engine.js:1331`; `Sources/WebUIValidateIsland/Main.swift:17-18` |
| island host imports | every declared import stubbed to `function () { return 0; }` | `webui-engine.js:1295-1304` |
| island event wiring | `input` only, via `data-island-input` → full region re-render | `webui-engine.js:1395-1410` |
| island capability gate | fetch-time only; the `capabilities` / `persistence` config seams are no-ops on the engine path | `webui-engine.js:1384`; `Sources/WebUICore/RuntimeConfig.swift:20-28` |
| shipped island (validate) | 164,447 B stripped — the kB tier landed (336× from the 52.8 mb full-sdk build) | `NEXT_IMPLEMENTATION_PLAN.md` (p2 measured outcome) |
| table rendering | server-rendered; a sort/select/expand re-emits the whole table as one fragment (`me.update(...)`) | `Sources/WebUIDesignSystemCore/WebUIComponents.swift:832,903-909,976-980` |
| table cost (measured) | 29–47 B per cell simple, 196 B per cell rich; 71–143 B per simple row, 825 B per rich row | measured 2026-10-02 on `designer/previews/showcase.html` (14 tables) |
| virtualization primitives | none (`(?i)virtual` over `Sources/` = 0 hits) | measured 2026-10-02 |
| input debounce defaults | 300 ms trailing, 1,000 ms max-wait; `change`/`blur`/`submit` immediate | `Documentation/JS_RUNTIME.md:62-68`; `RuntimeConfig.swift:10-11` |
| key events on the wire | `key` + `ctrlKey` / `shiftKey` / `altKey` / `metaKey` | `webui-engine.js:516-525` |
| ime composition / clipboard / range selection / undo | absent (one harness-era `clipboard` mention, unwired) | grep `composition\|clipboard\|undo` over `Sources/` + engine, 2026-10-02 |
| handler ceiling | 10,000 handlers per `EventRouter` | `AGENTS.md` |
| app-data persistence | none (auth sessions in-memory; the store is protocol-driven, backend-provided — the lmdb store left the package 2026-09) | `AGENTS.md`; `Documentation/README.md:13` |
| offline | service worker caches the shell (engine + css + `/__assets`); data reconcile deferred | `designer/assets/webui-shell.js:1-53`; `NEXT_ARCHITECTURE.md` §5 |
| collaboration | per-session ws + render-token binding; `broadcast(_:)` exists; no ot/crdt, no presence | `Sources/WebUIServer/WebUIServer.swift:421` |
| desktop packaging | nothing in-tree | grep `WKWebView\|desktop\|pwa`, 2026-10-02 |

arithmetic from the measured cell costs (not itself a measurement): a 100k-cell
sheet ≈ 3–20 mb of html in the full-render model, plus at least a node per cell;
1,000 rows ≈ 0.07–0.8 mb per full-table interaction. the current model re-sends
and re-parses that per interaction.

## 3. the gaps

| # | gap | today | needed | first proof |
|---|---|---|---|---|
| g1 | hot-path ownership | every interaction crosses `/ws`; typing floor = 300 ms debounce + rtt; optimistic cannot predict text | client-owned edit buffer + commit protocol; keystroke echo < 50 ms | s0: echo latency through the ws path, one number |
| g2 | grid rendering + patch granularity | whole-table fragment per interaction; ops exist (`text`/`append`) but no server-side diff, no row/range/move/remove ops, no windowing | viewport windowing (~1–2k dom nodes, or canvas) + cell/row-range patches or island-owned render | s0: patch bytes/frames offline vs diff on a 1,000-row table |
| g3 | edit & keyboard model | form-grade inputs; modifiers reach the server; no ime, clipboard, range selection, or undo | grid keyboard grammar, range model, tsv/system clipboard, commit semantics, undo stack | grammar spec + probe: 10k cells navigable, zero round trips |
| g4 | data + compute | no formula engine, dependency graph, formats, or sparse cell model | `SheetCore` in the foundation-free subset — the same swift server-side and island-side | parity tests: one calc suite, native + wasm |
| g5 | collaboration | no ot/crdt/presence | document sync protocol with convergence + presence | two-client convergence probe |
| g6 | persistence/offline | shell cache only; reconcile deferred | durable document store + offline dirty model (island-scoped indexeddb) | kill-network edit → reload → converge |
| g7 | desktop packaging | none | webview shell (wkwebview) + local server app; menus/files/shortcuts; signing | shell spike opening a local document |
| g8 | island abi v2 (enabler) | one-shot renderer; stub imports; input-only; fetch-time gate | host import surface (events, frames, render surface), incremental output, capability-gated apis, worker/sab offload retained island-internal | abi doc + stateful probe island (state across events, incremental render) |

note: g1–g3 also pay off for ordinary apps (large tables, chat streams, editors)
— they are not sheets-only work.

## 4. sheet ux budget (targets; filled from s0 measurements)

| metric | target | today |
|---|---|---|
| keystroke echo in a cell | < 50 ms | 300 ms debounce + rtt (form-grade) |
| scroll / selection | 60 fps (16.7 ms frame) | n/a (no grid) |
| click → visible response | same-turn | same-turn for coarse, value-independent transitions only |
| open a 100k-cell sheet | < 1.5 s, no full re-render per interaction | not viable (full-render model) |
| offline edit → reconnect converge | no loss | not implemented |

## 5. the wasm decision point

criterion: build on wasm when the budget is **structurally below rtt** or the
client must own state — per-keystroke echo, per-frame scroll/selection, offline
edit, local recalc preview — and not one interaction earlier. chrome (toolbars,
menus, dialogs, sidebars) stays server-rendered + engine; the server-authority
model is right for it.

prerequisite — islands cannot host a hot path today:

- imports are stubs: a grid island cannot receive an event, schedule a frame, or
  obtain a surface (`webui-engine.js:1295-1304`);
- output is sanitized html re-mounted per render — no incremental frames;
- the only wired event is `input`, and it re-renders the whole region;
- the capability gate is fetch-time only, and `capabilities` / `persistence` are
  unwired on the engine path; `STABILITY.md` #7 records the harness v2 contract
  (expanded import surface, renderer registry) as pre-2.0, its design doc deleted
  with the wasm-era docs.

sequence:

0. **(no wasm)** virtualized grid spike + cell/row patch granularity on the
   server-authoritative path, and *measure*. this is the p3 spike
   (`NEXT_IMPLEMENTATION_PLAN.md`) with a forcing function, and it lands reusable
   value either way: a `WebUIDataGrid`-shaped primitive (or engine-side
   windowing) and evidence about diffing against the ops that already exist.
1. decide from the numbers. if the budgets fail on the ws path (typing at wan
   rtt will), the abi is the next milestone; if dom windowing + diff meets the
   target budgets, the island can wait.
2. **abi v2 + stateful probe island** — host import surface, incremental output
   frames, capability-gated imports; the probe keeps state across events and
   renders incrementally. this is the true "start of complex ux on wasm".
3. grid island (`WebUISheet` family): viewport, selection, edit buffer, local
   recalc; sync over the existing `/ws` with render-token discipline; degrade
   path = s0's server-rendered grid.

don'ts:

- do not resurrect the monolith (55 mb fetched per page to do what a 29 kb
  runtime did, and it could not render server views — `NEXT_ARCHITECTURE.md:9-18`);
  the island tier is its correctly-scoped successor (validate at 164,447 B).
- do not move general tables, menus, dialogs, or settings into wasm.
- do not grow the frozen consumer surface except additively (a component +
  capability, per `STABILITY.md`).

## 6. what "upgrading the framework" means

| layer | treatment | why |
|---|---|---|
| server core (event router, fragment envelope, csp/nonce, auth, security invariants) | keep | this half is right; patches stay server-authored |
| engine | grow: patch diffing/granularity (ops landed 2026-10-02), local-echo primitive, composition (ime) delivery, clipboard helpers, keyboard-grammar seams | the hot path needs granular patches and local echo before any wasm exists |
| island abi | grow: v2 (imports + incremental frames + gating) + a public swift island-authoring surface (additive) | the enabler for g8; keeps "the consumer never writes js" true |
| shared core | grow: `SheetCore` (sparse cells, formulas, recalc, formats) in the foundation-free subset | the same swift server-side and island-side = logic parity by construction |
| persistence / sync | grow: document store behind a host protocol + sync protocol (ot/crdt) + offline queue | g5/g6 |
| delivery | grow: island routes and content-addressing exist; add grid-scale budget checks to the asset tooling | "no mandatory binary on any page" stays true |
| desktop | add: one reference webview-shell app | g7; thin, framework-agnostic |
| frozen consumer surface | unchanged; additive only | `STABILITY.md` epoch rules |

## 7. phased ladder (in-repo gates only; no ci)

| phase | goal | exit gate |
|---|---|---|
| s0 | measure: patch-cost spike on a 1,000-row table (whole-fragment vs `text`/diff ops); echo-latency probe; fill the budget table | spike report + numbers recorded in this doc; the in-repo ladder green |
| s1 | abi v2 + stateful probe island; `SheetCore` skeleton (parse/eval/recalc) with native + wasm parity tests | island gate (`wasm-island` + browser-smoke); `swift test` |
| s2 | grid island (or dom-windowed grid, per s0): viewport, selection, edit buffer, local recalc; degrade path to the server-rendered grid | browser probes: 60 fps scroll, < 50 ms echo, no-island degrade |
| s3 | document layer: store behind a protocol + reference impl; row/range patch ops; undo/redo; clipboard | fullstack probes; two-tab consistency |
| s4 | collaboration + offline: sync protocol, presence, offline queue + reconcile | two-client convergence probe; kill-network probe |
| s5 | desktop shell reference app (wkwebview + local server); packaging notes | shell smoke: open, edit, save a local document |

s0 gates everything after it. s3's durability and s4's sync are separable from
the grid — they can be reordered if an app needs them first, and the grid's hot
path does not depend on them.

## 8. risks — argued honestly

1. **"this is the wasm monolith again."** no — it is scoping. the monolith was
   55 mb fetched on every page; islands are built per capability, fetched only
   when declared, and degrade to ssr+engine (validate: 164,447 B). the grid
   island is the same tier, and s0's server-rendered grid remains the fallback.
2. **"liveview-class eventing cannot do a sheet."** the eventing is not the
   problem — the ownership is. liveview-class stacks ship top-tier ux; none ships
   a large grid without a local renderer. islands are this framework's only
   in-philosophy home for local rendering, so the honest statement is: the sheets
   arc requires abi v2, and s0's numbers decide when it starts.
3. **"dom windowing might make the island unnecessary."** possibly — and s0 is
   designed to find out (ag-grid-class windowing is ~1–2k nodes). canvas buys
   scale but costs a11y and theming discipline (tokens would need
   `getComputedStyle` reads); decide after the spike, not before.
4. **"the foundation-free subset will fight calc."** it will tax it: the island
   build is the scalar-clean stdlib (no `Character(...)` canonicalization, no
   `String(decoding:as:)`), so number/date formatting is hand-rolled.
   `WebUISharedCore` shows the pattern (json, escaping, validation at 164 kb);
   budget the formatting work explicitly in s1.
5. **"two runtimes double the test surface."** inherited from
   `NEXT_ARCHITECTURE.md` risk 2 and mitigated the same way: the island abi stays
   narrow and the base path stays single; every phase closes on the existing
   in-repo ladder.

## 9. decision log (to lock with the owner)

| # | decision | owner | status |
|---|---|---|---|
| d9 | sheets-class is an accepted growth target for the framework (a direction, not a promise) | user | proposed |
| d10 | the grid hot path goes client-side only after s0 measurements; the sequence is measure → abi → island | design | proposed |
| d11 | island abi v2 = stateful islands (host imports + incremental frames, capability-gated), additive, degrade preserved | design | proposed |
| d12 | `SheetCore` lives in the foundation-free subset; server and island run the same calc swift | design | proposed |
| d13 | patch granularity (server diff vs island-owned render) chosen by the s0 spike, not by preference | design | open |
| d14 | desktop = webview shell + local server; no new runtime, no new language | design | proposed |
| d15 | no ci; the in-repo ladder only | user | stays locked |

## appendix — source measurements (2026-10-02, this machine)

- `wc -c designer/assets/webui-engine.js` → 52,433 B, 1,579 lines.
- showcase table census (python over `designer/previews/showcase.html`): 14
  tables; simple rows 71–143 B (29–47 B/cell), the rich routed table 825 B
  per row (196 B/cell).
- greps: `(?i)virtual` over `Sources/` = 0; `composition` over the engine = 0;
  `clipboard` = one unwired harness-era mention (`RuntimeConfig.swift:22`);
  `WKWebView|desktop|pwa` over visible docs = 0.
- fragment ops landed in `f794267` / probed in `61b8bdd` (2026-10-02).