# WASM Implementation Plan — no-webui client render core in the page

_status: proposed. this document is the execution companion to
`Documentation/WASM_TRAJECTORY.md` (the design of record; cited here as **W§n**).
it turns the trajectory's Phase 0–6 into sequenced, verified, bite-sized work. no
code has changed and nothing is committed by this document. execution begins when
tanner approves; phases 0–1 are the gate before any further phase can start._

_scope contract: D1–D5 (W§0.1) and the trajectory thesis are non-negotiable
inputs — official Swift Wasm SDK only, zero third-party dependencies, hand-rolled
narrow bridge, server authority (D4), keep-if-they-survive for `@TaskLocal` and
swift-log (D3). every phase states a deliverable, acceptance criteria, and a
fallback so a stalled phase is visible, never silent._

---

## 0. goal, architecture, tech stack

**Goal.** make the `no-webui` javascript runtime non-static: compile the `WebUI`
render core + `EventRouter` with the official Swift Wasm SDK, run it in the page as
`app.wasm`, and reduce `webui-runtime.js` to transport + mechanical DOM plus a ~150
line bridge chamber. the server stays authority, persistence, and SSR first paint.

**Architecture.** one render core, two hosts. the same `View`/`EventRouter`/
`JSONValue` sources compile natively (NIO SSR/API server) and to `wasm32` (the
in-page renderer). the client holds its own `EventRouter`, view tree, and (for
local datasets) data; delegated events cross a hand-rolled `[UInt8]` JSONValue
bridge (W§3.2); async handlers run through a host pump on the Swift runtime's own
job FIFO (W§3.3). server-mode bytes, string pins, and security invariants never
change.

**Tech stack.** Swift 6.4 (this host, `swiftlang-6.4.0.34.1`, macOS 27.0) +
official Wasm SDKs `swift-6.4.0-RELEASE_wasm` (full) and `_wasm-embedded`;
WasmKit (`swift run --swift-sdk`) for host-side verification; the existing gate
stack (`smoke`/`fullstack-smoke`/`browser-smoke`). zero new dependencies.

---

## 1. verified context and assumptions

facts below were verified against this checkout and swift.org on 2026-09-15.

### 1.1 host + SDK facts

| fact | source |
|---|---|
| host runs Swift 6.4 (`swiftlang-6.4.0.34.1`, target `arm64-apple-macosx27.0.0`) | `swift --version` on this host |
| `swift sdk` subcommand exists; **no Swift SDKs installed yet** | `swift sdk list` → "No Swift SDKs are currently installed" |
| install command and checksum for the 6.4 wasm SDK bundle | swift.org "Getting Started with Swift SDKs for WebAssembly" (fetched 2026-09-15): |
| two SDK IDs installed by the bundle: `swift-6.4.0-RELEASE_wasm` (full) and `swift-6.4.0-RELEASE_wasm-embedded` | same article |
| build: `swift build --swift-sdk swift-6.4.0-RELEASE_wasm`; run via WasmKit: `swift run --swift-sdk …` | same article (block 3/4/5) |
| reactor note: the full-SDK binary is a WASI command (`_start` initializes then returns; never `proc_exit`); exports do the work | swift wasm execution model (skill + build output inspection) |

the exact install step (P0-T1):

```bash
swift sdk install https://download.swift.org/swift-6.4.0-release/wasm-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz --checksum f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d
```

### 1.2 the "20× faster" claim, verified

the user's 20× figure is the Swift 6.4 WebAssembly milestone; the swift.org 6.4
release blog states the verified number:

> "WebAssembly bridging through JavaScriptKit up to 40 times faster" — "safe
> bridging up to 40 times faster than earlier dynamic bridging. the Wasm SDK is
> available from the Install Swift page of Swift.org, so compiling Swift for the
> browser requires no extra setup beyond adding the SDK."

two implications for this plan, stated plainly:

1. the 40× is a **JavaScriptKit interop optimization** (static typed bridging vs
   the old `JSValue`-boxing dynamic path). no-webui excludes JavaScriptKit by D1,
   and its hand-rolled bridge is already static and narrow — so the speedup does
   not transfer directly, and it is **not a reason to adopt JSKit**. it does
   validate the trajectory's Route-B bet: static, narrow, typed bridging is the
   fast shape.
2. what actually matters for us from 6.4: the **official SDK ships from swift.org**
   and installs against the Xcode toolchain with one command; **Embedded Swift
   gains existential types and richer error handling** (relevant to the P6 size
   diet); Foundation/`FileManager` WASI support improved (not used by the
   no-Foundation core).

### 1.3 repo baseline (this checkout)

| fact | source |
|---|---|
| `Package.swift`: tools `6.0`; WebUI depends on `Logging`, `RAW`, `RAW_sha256`, `RAW_hmac` | `Package.swift:57-69` |
| `WebUI` sources: 23 `.swift` files; `Crypto.swift` imports `Security`/`Glibc`/`RAW*` + a `SecRandomCopyBytes` path (server-only); `Utilities.swift:298` uses `UUID()`; most other files are Foundation-typed string/characterset work | `search_files` over `Sources/WebUI` |
| asset pipeline: `Plugins/WebUIAssetPlugin` reads `designer/assets/design-system.css` + `webui-runtime.js`, runs `WebUIAssetTool`, writes `Assets+Generated.swift` under `.build/` (gitignored) | `Plugins/WebUIAssetPlugin/WebUIAssetPlugin.swift` |
| assets: `designer/assets/` has `design-system.css`, `webui-runtime.js`, `split-controller.js` | `ls designer/assets/` |
| gates: `smoke`/`fullstack-smoke` host the smoke server (`.build` lock held for the whole run; `--disable-sandbox` required); `browser-smoke.mjs` drives real DOM via playwright (cannot run in a plugin sandbox) | `AGENTS.md` |
| docs live in `Documentation/*.md`; the auth implementation plan lives at `Documentation/IMPLEMENTATION_PLAN.md` (house precedent for plans) | repo listing |
| gate baseline today: `swift test` = 567 tests / 62 suites; smoke pins exactly 24 `data-component-id` attributes | `AGENTS.md` |

### 1.4 the two facts that shape the whole plan

1. **the wasm product cannot be built by a build-tool plugin.** the asset plugin
   runs tools on the host triple under the package's `.build` lock; a nested
   `swift build --swift-sdk …` inside the plugin would dead-lock and is
   sandbox-denied. therefore the wasm binary is produced by a **separate, explicit
   invocation** (`swift build --swift-sdk swift-6.4.0-RELEASE_wasm --product
   WebUIClient`), and the asset plugin **consumes** the built `.wasm` as a third
   input (same read-a-file→embed pattern as css/js). missing `.wasm` → plugin
   warns + emits empty bytes (the existing degraded-path precedent). gates that
   need wasm run the wasm build **before** the plugin/command invocation starts.

2. **the crypto plane must leave the wasm build.** `WebUI` depends on the `RAW*`
   products and `Crypto.swift` uses `Security`/`Glibc` — none of that can (or
   should, per D4) exist in the client. the trajectory's own Phase 0 audit item
   ("confirm the crypto products are not pulled into the client target; if they
   are, isolate them") becomes a concrete module split (P0-T5): a wasm-clean
   `WebUICore` target underneath `WebUI`, with `@_exported import WebUICore` so
   `import WebUI` consumers see an unchanged public surface.

### 1.5 import-surface requirement (what a full-SDK wasm module actually needs from JS)

a full-stdlib `wasip1` Swift binary imports, in addition to the bridge's own
chamber imports: the Swift runtime hooks (`env.swift_task_enqueueGlobal_hook`,
and the small `swift_jobs`/`swift_tsan`/`swift_task` instantiation set) and a
minimal WASI subset (`clock_time_get`, `fd_write`, `proc_exit`, `random_get`,
…). the stale assumption that the import object is just `env: {setInnerHTML…}`
is wrong. the chamber must therefore also supply a **hand-rolled minimal WASI
adapter + runtime import stubs** (~40 LOC of dumb JS — browser platform APIs, not
an npm WASI shim, so D1 is untouched). P1-T2 enumerates the exact import list
from the built binary and pins it.

---

## 2. design decisions this plan pins

| decision | this plan | rationale |
|---|---|---|
| A1 | `WebUICore` split (wasm-clean render/routing/codec/css/token/icon subset; crypto/admission/document-assembly stay in `WebUI`; `@_exported import` keeps the public surface byte-identical) | the wasm build links only wasm-clean code; D4 anatomy; the only way to keep `WebUI`'s name and consumer surface untouched |
| A2 | wasm binary produced by a separate `swift build --swift-sdk … --product WebUIClient`; asset plugin consumes it as an input; gates build it first | the `.build`-lock + sandbox reality (fact 1.4.1) |
| A3 | the chamber is a **new comment-free asset** `designer/assets/webui-client.js` implementing: the 8 bridge imports + Swift runtime hook + minimal hand-rolled WASI adapter | D1 (hand-rolled interop, house pattern), first law (comment-free distributed assets) |
| A4 | `WebUIClientRuntime` (wasm-clean library: executor hook, pump, handleEvent, state) + `WebUIClient` (executable → `app.wasm`) + `WebUIClientTests` (pure-logic, runs under `swift test --swift-sdk` via WasmKit; fallback P1-T0-b) | testability: unit logic on the host/wasmkit, DOM paths in browser-smoke |
| A5 | `EventData.data` widens `[String: String]` → `JSONValue` as **one breaking-seam commit at the top of Phase 3** (wire bytes unchanged; Swift typing widens) | W§2.1.5; house "one commit across protocol + servers + pins" rule |
| A6 | `clientMode` stays **opt-in per page** indefinitely; server mode remains the byte-of-truth | trajectory §5.2 Q5 lean; cheapest + safest default |
| A7 | telemetry reuses the existing `state` message now; a dedicated low-frequency ws message is deferred unless Phase 3 measurement shows noise | trajectory §5.2 Q6 lean |
| A8 | the full-stdlib wasm binary is a **reactor-style command**: `_start` initializes the runtime + executor hook and returns (no `proc_exit`); all work happens in exported `webui_*` entries | browser hosting reality; one pin test |

non-decisions (explicitly out): JavaScriptKit/BridgeJS (that's where the 40×
lives; not ours), npm WASI shims, client-side Argon2/throttling, `#if os(WASI)`
in any app-facing API (internal shims only, W§3.8).

---

## 3. sequencing map

```
P0 (decisions locked + subset audit) ──[gate: audit table + D3 resolved + webuiclient hello builds]──▶ P1 (prove the compile)
P1 ──[gate: byte-identity + wasm served + integrity pin]──▶ P2 (client EventRouter → local search vertical)
P2 ──[gate: vertical green on existing typed-handler API; server-mode pins untouched]──▶ P3 (state, sync, offline)
P3 ──[gate: offline reconcile + revocation demotion]──▶ P4 (graduated adoption: clientMode boot + chamber + docs)
P4 ──[gate: one-arg flip/revert; pins green]──▶ P5 (client-first features) ──▶ P6 (size diet & distribution)
```

P0 and P1 are blocking gates; P4's docs task can start in parallel with P3 (flagged
below). per-phase "done means" run order (top to bottom, no gate skipped):

```text
swift build
swift test
swift build --swift-sdk swift-6.4.0-RELEASE_wasm --product WebUIClient        [P1+]
swift run  --swift-sdk swift-6.4.0-RELEASE_wasm --product WebUIClient --verify-render   [P1+]
swift package --disable-sandbox plugin smoke
swift package --disable-sandbox plugin fullstack-smoke
node designer/browser-smoke.mjs
swift package plugin showcase --allow-writing-to-package-directory             [on doc/asset drift]
```

lock discipline: never run a gate while `serve` is up; the wasm build is a
separate invocation and must complete **before** the smoke/fullstack plugins are
invoked.

---

## 4. phases

### Phase 0 — decisions locked + subset audit (0–1 wk)

_deliverable: wasm SDK installed, audit table filled, D3 resolved with the user,
`WebUICore` split in place, `WebUIClient` hello target builds with the official
SDK. records: `Documentation/WASM_SUBSET_AUDIT.md` (the table) + decision-log
updates in `WASM_TRAJECTORY.md`._

**P0-T1 — install the wasm SDKs.**

* objective: both official SDKs available for cross-compile.
* files: none (host environment).
* steps:
  1. verify the checksum from swift.org (if swift.org shows a new one, use it —
     never force).
  2. `swift sdk install https://download.swift.org/swift-6.4.0-release/wasm-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz --checksum f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d`
* verify: `swift sdk list` shows exactly `swift-6.4.0-RELEASE_wasm` and
  `swift-6.4.0-RELEASE_wasm-embedded`.
* fallback: if checksum mismatches, re-fetch it from the swift.org article; never
  install unverified bytes.

**P0-T2 — hello-wasm probe (prove the toolchain before touching the package).**

* objective: a zero-risk first cross-compile outside the repo.
* steps: `mkdir -p /tmp/wasmprobe && cd /tmp/wasmprobe && swift package init --type executable`, write the `#if os(WASI)` hello from the swift.org article, then
  `swift build --swift-sdk swift-6.4.0-RELEASE_wasm` and
  `swift run --swift-sdk swift-6.4.0-RELEASE_wasm`.
* verify: "Hello from WASI!" via WasmKit; then repeat with `_wasm-embedded`.

**P0-T3 — `WebUICore` split (isolate the crypto plane).**

* objective: a wasm-clean library target under `WebUI` with an unchanged consumer
  surface.
* files:
  * modify `Package.swift`: add `.target(name: "WebUICore", dependencies:
    [.product(name: "Logging", …)])` (logging pending P0-T4) and make `WebUI`
    depend on `WebUICore` + the server-only files; add `@_exported import
    WebUICore` in a `WebUI/WebUICoreExport.swift` shim.
  * move (git mv, no renames inside files) to `Sources/WebUICore/`:
    `View.swift`, `ViewBuilder.swift`, `Primitives.swift`, `Layouts.swift`,
    `Modifiers.swift`, `ModifiedView.swift`, `EventHandling.swift`,
    `Dismissible.swift`, `Observable.swift`, `JSONValue.swift`,
    `WebSocketProtocol.swift`, `CSSRule.swift`, `CSSMinify.swift`, `Tokens.swift`,
    `Icon.swift`, `Base64.swift`, `RuntimeConfig.swift`.
  * stay in `WebUI/` (server-only): `Crypto.swift`, `ConnectionGate.swift`,
    `ConstantTime.swift`, `HTMLDocument.swift`, `WebUIRuntime.swift`.
  * split `Utilities.swift`: wasm-clean half (htmlEscape, injectAttributes,
    markdownToHTML, highlightCode, inlineSVG, sanitizeURL, attrIf/classIf) into
    `WebUICore/Utilities.swift`; server half (CSRFProtection/CSRFError + the
    `UUID()` helper at `Utilities.swift:298`) becomes `WebUI/CSRF.swift`.
* verify: `swift build` 0 warnings 0 errors; `swift test` = 567 tests / 62 suites
  green (public surface unchanged because of the export shim).
* note: files that `import Logging` land in WebUICore only after P0-T4 resolves
  swift-log; if the D3 throw-out applies, the in-package `LogFunnel` lives in
  WebUICore and `EventRouter(logger:)`/`ObserverList(logger:)` take the funnel
  type (one breaking param change, accepted).

**P0-T4 — subset audit table and D3 resolution.**

* objective: fill the trajectory §4 Phase 0 checklist with real build results, and
  resolve D3 with the user.
* files: create `Documentation/WASM_SUBSET_AUDIT.md`; update the decision table in
  `Documentation/WASM_TRAJECTORY.md`.
* steps:
  1. build `WebUICore` with `_wasm` and with `_wasm-embedded`
     (`swift build --swift-sdk … --target WebUICore` — worst first, embedded
     decides).
  2. record per checklist item: String core / `JSONValue`+`[UInt8]` /
     `Synchronization.Mutex` / `@TaskLocal` (RenderContext) / `_Concurrency`
     (`Task`, `withTaskGroup`) / swift-log / rawdog-not-pulled.
  3. present the table to the user; the two D3 contingent pins get a verdict:
     keep, or throw out with the specified fallback (W§2.1.6 ambient context /
     W§2.1.16 `LogFunnel`).
* verify: table is filled with pass/fail/fallback, no empty cells; D3 verdicts
  recorded in the decision log.
* fallback (trajectory's): if only core strings+Mutex+JSONValue survive, the
  architecture still holds — sync-equivalent handlers, ambient context, funnel.

**P0-T5 — `WebUIClient` + `WebUIClientRuntime` skeletons.**

* objective: a `WebUIClient` executable that cross-compiles for wasm and a runtime
  library its tests can link.
* files:
  * `Package.swift`: `.target` `WebUIClientRuntime` (depends `WebUICore`),
    `.executableTarget` `WebUIClient` (depends `WebUIClientRuntime`),
    `.testTarget` `WebUIClientTests` (depends `WebUIClientRuntime`, `WebUICore`).
  * `Sources/WebUIClientRuntime/ClientExecutor.swift` — imports only the Swift
    runtime entry points; empty hook placeholder in P0, filled in P2-T1.
  * `Sources/WebUIClient/main.swift` — `@main` reactor stub: initialize, return
    (never `proc_exit`), a `--verify-render` flag path (P1).
  * `Tests/WebUIClientTests/` — one smoke `@Test` that imports and renders
    `Text("hello")` via `WebUICore` and asserts the string.
* verify: `swift build --swift-sdk swift-6.4.0-RELEASE_wasm --product WebUIClient`
  links `WebUIClient.wasm`; `swift test --swift-sdk swift-6.4.0-RELEASE_wasm
  --target WebUIClientTests` runs the smoke test via WasmKit (fallback P1-T0-b if
  the runner has gaps).

**P0 acceptance.** SDK installed and probed; audit table filled; D3 resolved with
the user; `WebUICore` split green (host tree = 567/62); `WebUIClient` hello builds
and runs under WasmKit; decision log updated.

---

### Phase 1 — prove the compile (1 wk)

_deliverable: the smoke page's body renders **inside wasm** and matches SSR
byte-for-byte; `.wasm` served as a static asset through the house asset pipeline;
integrity pin added; a client-mode probe page in the gates. records:
`Documentation/WASM_BOOTSTRAP.md` (import surface + reactor shape notes)._

**P1-T0 — (a) shared smoke page view; (b) test-runner fallback probe.**

* (a) extract the `WebUISmokeTest` page body into a shared, wasm-clean target
  `WebUISmokeShared` (a thin view file both the server and the client render; no
  duplicate code): `Sources/WebUISmokeShared/SmokePage.swift`, body identical to
  the current page. verify: smoke server renders the same bytes as before (pin
  24 `data-component-id`, page-signature checks unchanged).
* (b) if `swift test --swift-sdk` does not drive the wasm test product on this
  toolchain, adopt the deterministic fallback for all wasm unit tests: the
  `WebUIClient` executable gains `--verify <name>` modes printing pass/fail as
  `swift run --swift-sdk` stdout, asserted by the gate. record which route is
  live in `WASM_BOOTSTRAP.md`.

**P1-T1 — render the smoke page in wasm, byte-identical to SSR.**

* objective: `webui_render_page() -> framePtr` export (a **P1 gateway hook only** —
  retired once hydration gates are stable; the permanent export table is exactly
  the trajectory §3.2 set) renders the shared smoke body; `--verify-render` prints
  it for host comparison.
* files: `Sources/WebUIClient/ClientBoot.swift` (the `@_expose(wasm)` export
  table: `webui_init`, `webui_handle_event`, `webui_frame_ptr`,
  `webui_frame_len`, `webui_pump`, `webui_boot_done`; `webui_render_page` gated
  out at P2),
  `Sources/WebUIClient/SmokePageGo.swift` (entry calling `SmokePage().render()`).
* steps: render inside the `RenderContext` (per P0 D3 verdict) exactly as the
  server does; serialize the string into the wasm-owned frame buffer.
* verify: diff `swift run --swift-sdk swift-6.4.0-RELEASE_wasm --product
  WebUIClient --verify-render` against `swift run WebUISmokeTest` (same state) →
  **empty diff**. a `WebUIClientTests` case asserts the byte-identity too.
* fallback (blocker-level, from the trajectory): if the render core does not jump
  to wasm on the official SDK, stop and report the exact diagnostic — do **not**
  paper over with JSKit; the trajectory is conditioned on the official SDK.

**P1-T2 — import-surface enumeration + hand-rolled runtime/WASI adapter.**

* objective: know exactly what the chamber must provide at instantiation.
* steps:
  1. `wasm-objdump -x .build/<wasm-triple>/debug/WebUIClient.wasm` (or
     `llvm-objdump`) and enumerate all `import` module/field pairs into
     `Documentation/WASM_BOOTSTRAP.md` (expect: `env.swift_task_enqueueGlobal_hook`
     + `env.swift_*` runtime set, `wasi_snapshot_preview1.*` subset,
     `swift_jobs`/`swift_tsan`/`swift_task` instantiation imports, plus the
     chamber's own 8).
  2. implement the minimal adapter in the chamber stub:
     `clock_time_get`→`performance.now()*1e6`, `fd_write`→console,
     `proc_exit`→record+stop, `random_get`→`crypto.getRandomValues`.
* verify: a pin test (or gate assertion) parses the current `.wasm` and asserts
  the import set is **exactly** the documented set — growth is a deliberate change.

**P1-T3 — serve `.wasm` + chamber through the asset pipeline.**

* objective: `WebUIAssets.wasm: [UInt8]` + `WebUIAssets.client: String` generated
  by the house asset tool; server serves both.
* files:
  * `Plugins/WebUIAssetPlugin/WebUIAssetPlugin.swift` — resolve the built
    product path (scan `.build/*/debug/WebUIClient.wasm`); missing → warning +
    empty bytes (existing degraded precedent); add `--wasm-input` + `--client-input`.
  * `Sources/WebUIAssetTool/*` — emit `WebUIAssets.wasm`, `WebUIAssets.client`
    (chamber source, comment-free) alongside css/js constants.
  * `Sources/WebUI/WebUIAssets+Wasm.swift` — public accessors.
  * `WebUISmokeTest` server — `GET /ui/app.wasm` (bytes, correct content-type,
    `Cache-Control: no-store`) and `GET /ui/webui-client.js` (chamber) — mirroring
    `/ui/styles.css`/`/ui/scripts.js` routing.
* verify: curl both routes; the served `.wasm` bytes equal the built file; asset
  integrity pin (below) green.

**P1-T4 — wasm-integrity pin + CSP pre-check.**

* objective: the embedded product can't drift; client-mode CSP shape proven.
* files:
  * `Tests/WebUIClientTests/WasmIntegrityTests.swift` — parse the embedded bytes:
    magic `\0asm`, version 1, a section walk stays in-bounds; assert non-empty
    when a `.wasm` is present.
  * `Tests/WebUITests/HTMLDocumentCSPTests.swift` — add the trajectory's CSP pin:
    client-mode documents emit `script-src 'self' 'nonce-…' 'wasm-unsafe-eval'`;
    server-mode CSP is byte-unchanged (the `'wasm-unsafe-eval'` keyword is
    verified against MDN `script-src`, W§1.2 fact table).
* verify: both suites green; a browser probe (P1-T5) confirms no `EvalError` at
  `WebAssembly.instantiate` under the client CSP.

**P1-T5 — gates: client-mode probe page.**

* objective: each gate proves the wasm loads and its render matches SSR.
* files: `Plugins/WebUISmokePlugin/*` and `Plugins/WebUIFullstackSmokePlugin/*`
  grow a client-mode page probe (page loads, chamber instantiates, `webui_render_page`
  result equals the SSR div via DOM comparison); `designer/browser-smoke.mjs` adds
  a client-mode probe driving real Chromium.
* steps: gates build the wasm product first (their `--disable-sandbox` invocation
  sequence starts with `swift build --swift-sdk … --product WebUIClient`), then
  run the existing checks plus the probe.
* verify: `smoke`, `fullstack-smoke`, and `browser-smoke` all green with the probe
  on; screenshot captured to `.smoke/`.

**P1 acceptance.** client-computed HTML byte-identical to SSR (empty diff, pinned
in tests and gates); `.wasm` served as a static asset; integrity pin green; CSP
pin green; all server-mode pins and byte gates untouched; `swift build`+`swift
test` green.

---

### Phase 2 — client EventRouter → the "local search" vertical (2–3 wks)

_deliverable: router/context/`controlAttributes` resident in wasm; the pump
installed; `webui_handle_event` live; `WebUITable` + `.onInput` local search runs
entirely client-side through the **existing** typed-handler API; `Chart.onSelectMark`
client routing as the second proof. records: `Documentation/WASM_CLIENT.md`._

**P2-T1 — executor pump in wasm.**

* objective: async handlers make progress inside the page, zero API change.
* files: `Sources/WebUIClientRuntime/ClientExecutor.swift` — install
  `swift_task_enqueueGlobal_hook` (capture jobs into an in-wasm FIFO, never run),
  implement `webui_pump() -> Bool` (drain under a per-call budget, return whether
  more jobs remain), per trajectory W§3.3.
* verify: a `WebUIClientTests` case spawns `Task`s/`TaskGroup`s and pumps until
  the FIFO drains, asserting ordering and completion — run under WasmKit.
* fallback: if `_Concurrency` is absent on the chosen SDK (P0 audit), route
  through the trajectory's sync-equivalent path (W§3.3), documented in
  `WASM_CLIENT.md`.

**P2-T2 — resident router + `webui_handle_event`.**

* objective: delegated events dispatch through an in-wasm `EventRouter` and return
  fragments.
* files: `Sources/WebUIClientRuntime/ClientRuntime.swift` — decode JSONValue
  `EventData` from the frame bytes (W§2.1.6), route through the client-resident
  router (one router per page load — house rule), run the handler via the pump,
  render+collect `[FragmentUpdate]`, serialize to the frame; ambient
  `RenderContext` (D3 verdict) with `controlAttributes` stable-id semantics
  unchanged.
* verify: wasm unit test: register a handler, synthesize an `EventData`, invoke
  the export path, assert the returned fragments; the same test twice proves
  stable-id re-emission across a re-render (routing survives patches).

**P2-T3 — local search vertical (the payoff).**

* objective: rows shipped once, filtered + re-rendered in wasm, WebSocket silent
  on the hot path.
* files: `Sources/WebUIClient/SearchPage.swift` (the vertical's page: `WebUITable`
  over a client-resident dataset, `.onInput` handler filtering in Swift);
  smoke/gate pages gain the component; `designer/browser-smoke.mjs` drives it.
* steps: boot envelope carries `{state, rows}` once (W§3.4.3); JS debounces
  input (unchanged), chamber marshals `{event, targetId, value}`, wasm filters,
  renders the rows fragment, `setInnerHTML`.
* verify: browser probe types into the search field and asserts rows update **with
  zero WS frames on the hot path** (`routeWebSocket` frame counter); the rendered
  table matches what `--verify-render` produced from the same state.

**P2-T4 — full bridge import set live.**

* objective: all 8 chamber imports wired with pointer/length discipline (W§3.2):
  `setInnerHTML`, `removeElement`, `getElementValue`, `setElementValue`,
  `setCustomValidity`, `wsSend`, `now`, `log`.
* files: `designer/assets/webui-client.js` (chamber, comment-free);
  `Sources/WebUIClientRuntime/Imports.swift` (the Swift-side import protocol).
* verify: boundary tests on the chamber (over-long/zero pointers,
  id/html round-trips); `removeElement` empties the pinned
  empty-fragment-removes-element path (`ElementRef.remove()`).

**P2-T5 — chart client routing (second proof).**

* objective: `Chart.onSelectMark` routes through the in-page router; hover/select
  round trips die.
* files: `Sources/WebUIClient/ChartPage.swift`; mark pipeline (`resolvedMarks`)
  runs client-side once the mark spec + domains ship in the boot envelope
  (server-side SSR chart stays byte-identical, W§2.3.1).
* verify: browser probe clicks a mark, asserts the selection fragment patches
  locally with WS silent; SSR chart string pins untouched.
* (trim rule: if P2-T3 consumed the phase budget, P2-T5 moves to P5 — it is a
  second proof, not a gate.)

**P2-T6 — CSP pin + gates.**

* objective: client-mode CSP is pinned in tests and the vertical is green end to
  end. assemble the P1-T4 CSP test with the live client page; extend
  `fullstack-smoke` client probe with a local-search interaction; confirm the
  existing 24-`data-component-id` smoke pin and every server-mode string pin are
  untouched.
* verify: `swift build`, `swift test`, wasm build, `smoke`, `fullstack-smoke`,
  `browser-smoke` green, in that order.

**P2 acceptance.** table sort/filter/select/expand + pagination run client-side
through the existing typed-handler API (zero new strings at call sites);
fragment byte-identity gate green; server-mode pins untouched; `'wasm-unsafe-eval'`
pin present; gates green.

---

### Phase 3 — state, sync, offline (2 wks)

_deliverable: `ClientStateStore` (protocol + in-memory, house pattern); offline
rendering + seq reconciliation; observability bridge; `authState` mirror with a
revocation demotion test. records: `Documentation/WASM_STATE.md`._

**P3-T1 — the one breaking seam: `EventData.data` → `JSONValue`.**

* objective: widen the payload type once, contained (W§2.1.5).
* files: `Sources/WebUICore/EventHandling.swift`, `WebSocketProtocol.swift`
  decode paths, `Modifiers.swift` emission, and every server's `EventData` use
  (`WebUIExample`, `WebUIAuthExample`, `WebUISmokeTest`) — one commit, wire bytes
  unchanged (the JS envelope already sends JSON).
* verify: all host tests green; `fullstack-smoke` (which exercises real events)
  green; the `WSIncoming` decode round-trip tests updated to JSONValue and
  re-pinned.

**P3-T2 — `ClientStateStore` protocol + in-memory backend.**

* objective: client state behind a store protocol (the `AuthSessionStore` shape),
  wasm-owned.
* files: `Sources/WebUIClientRuntime/ClientStateStore.swift` (+ `InMemoryClientStateStore`).
* verify: wasm unit tests for get/set/subscribe lifecycle and the prototype-key
  deny (mirrors JS StateStore) via the in-page Swift store.

**P3-T3 — persistence backend behind chamber imports (deferrable).**

* objective: `localStorage`/`IndexedDB` backend (a chamber-import-backed store,
  not a dependency).
* files: `designer/assets/webui-client.js` (storage imports), `WebUIClientRuntime`
  backend conformer.
* verify: a browser probe reloads a page and asserts state survived.
* fallback (trajectory's): if the persistence bridge grows beyond mechanical,
  ship in-memory only — offline without persistence is still a win; revisit later.

**P3-T4 — offline render + reconcile.**

* objective: the app keeps rendering offline; on reopen, queued sync flushes and
  authoritative `update(seq:)` replays reconcile local state without
  duplicate/out-of-order patches.
* files: `Sources/WebUIClientRuntime/ClientSyncCoordinator.swift` — renderToken
  intact through the queue, `seq` monotonicity assertions on replay (W§3.4.5).
* verify: `WebUIClientTests` sequence test (offline events → reconnect → replay →
  monotone seq, no dupes); a browser probe with a silenced WS proves local
  interactions keep working, then a reopen reconciles.
* note: stale-page protection is unchanged — unknown/missing renderToken →
  `redirect:/login` + socket close (W§3.4.6).

**P3-T5 — observability bridge.**

* objective: wasm `Logger`/`LogFunnel` events fan out to server observers over the
  existing WS (low-frequency; reuses the `ObservableEvent` Codable shape).
* files: `Sources/WebUIClientRuntime/ObservabilityBridge.swift`; chamber forwards
  bytes via `wsSend` (no JS logic).
* verify: a parity test asserts a wasm-emitted `eventHandled` reaches a server
  observer the same way a server-mode emission does.

**P3-T6 — `authState` mirror + revocation demotion.**

* objective: client boot receives a non-secret session-presence/roles envelope;
  server-directed revocation demotes the mirror immediately.
* files: `Sources/WebUIClientRuntime/AuthMirror.swift`; boot envelope wiring in
  `ClientBoot.swift`.
* verify: a test (per trajectory W§3.4.6) drives server revocation and asserts the
  wasm mirror flips to anonymous before the next UI decision.

**P3 acceptance.** offline interactivity + reconcile (seq assertion green); a
revocation demotion test green; telemetry fan-out reaches server observers; the
breaking seam shipped as exactly one commit with pins updated.

---

### Phase 4 — graduated adoption (approved 2026-09-16 by tanner; executed with scope D included)

_deliverable: the `clientMode` adoption surface on `HTMLDocument`/`WebUIDocument`,
framework-rendered client pages, the design-system/chart compiling into the client,
the chamber transport seam, and the full documentation pass._

**approved decisions:** scope D in (WebUIDesignSystemCore split + chart wasm) —
the assessment's #2 gap; `ClientBoot` is caller-supplied wasmURL + `WebUIBoot`
helpers (framework emits, servers serve); the `.client` emission carries the
`webui-wasm` meta contract (the ABI baked into emitted documents); docs incl.
`AGENTS.md` in scope under this sign-off.

**executed workstreams** (commits `1fb052d`, `107b454`, `4cdc302`, `d5e33de`):

- **A — ClientBoot + clientMode:** `Sources/WebUI/ClientBoot.swift`
  (`wasmURL`/`mode`/`config`/`scriptURLs`; emits the `webui-wasm` meta +
  external scripts + only-set `webui-config` meta); `HTMLDocument(clientMode:)`
  and `WebUIDocument(clientMode:)` default `.none` byte-identical, `.client`
  swaps in the client csp and suppresses the inline server runtime; explicit
  csp still wins. knob split (w§2.1.11): transport knobs stay js-owned,
  behavior knobs channel through `webui-config`.
- **C — asset/route formalization:** `Sources/WebUI/WebUIBoot.swift` (wasm
  product locator + `RAW_sha256` hash); the smoke demo pages now render through
  the framework emission (no hand-assembled head/meta/csp); the hashed
  immutable route stays.
- **D — design system + chart in the client:** `WebUIDesignSystemCore`
  (components over `WebUICore`; verified no server/token/macro refs);
  `WebUIDesignSystem` re-exports via `@_exported` (surface byte-identical;
  theme + `@Theme` + WebUIDocument stay server-side — the theme layer is a p5
  refinement, `DesignToken` is a server-generated asset); `WebUIChart` depends
  on `WebUICore` directly; the local-search vertical is upgraded to
  `WebUITable` with a typed `.onSort` handler — sort+filters client-side,
  websocket silent (browser-probe proven).
- **B — chamber seam:** `wsSend` → `holder.transport.send` (transport wiring is
  the app's job); boot glue reads `webui-config`; renderToken echoes on
  forwarded events; boundary probe (non-component clicks no-op).

**P4 acceptance.** a page flips `clientMode` with one argument (`.none`
bit-identical, `.client` one arg); design-system + chart compile into the wasm
client; all server-mode pins/bytes gates green; gates: smoke 24/24, fullstack
26/26, browser 22/22 (framework-rendered pages); host 613 tests / 73 suites.
docs per `Documentation/` map; `AGENTS.md` updated (wasm build/gates, count
613/73).

**out of scope (unchanged):** size diet (p6), client-first features (p5),
offline/settle semantics (p3). the dev-mode `/ui/app.wasm` route is a stub note:
the framework emits `ClientBoot.defaultScriptURLs` (`/ui/…`) but hosts serving
under other prefixes pass their own (the demo servers use `/__assets/…`).

---

### Phase 5 — client-first features (the "flexible runtime" payoff)

**P5-T1 — optimistic predictions computed in wasm.** prediction closures run in
wasm from current client state; rollback re-renders from last-acknowledged state;
`data-optimistic` stays for server mode; `settleMs` becomes the wasm
state-retention knob (W§2.1.5). files: `Modifiers.swift` (OptimisticClickModifier
client branch), `WebUIClientRuntime` settle coordinator; verify: the existing
optimistic gates plus a browser probe that arms, then confirms, then rolls back —
all three legs, with WS silent on the arming leg.

**P5-T2 — client-side form validation.** a `Validator` result builder on `Form`
(pure closures, both hosts); wasm sets `setCustomValidity`/`reportValidity` via
the bridge; server re-validates on submit — same code, authority intact (W§2.1.3).
native POST rule preserved bit-for-bit.

**P5-T3 — local search/index over shipped datasets.** trie/prefix structures in
Swift over client-resident rows; no server on the hot path (W§3.4.3 payoff).

**P5-T4 — fully client-side sorting/selection/paging with server authority
override.** the typed-handler surface unchanged; server mode remains for datasets
that must stay server-side.

**P5-T5 — URL policy single-sourced in Swift.** `sanitizeURL` executes in wasm
before any patch/navigation issued from client code; the JS copy is retained only
as the mechanical pre-pass on untrusted socket data; one shared fixture table (the
obfuscation payload table from `references/web-framework-hardening-audit.md`)
driven against **both** sides in CI (W§2.1.14).

**P5 acceptance.** each feature demonstrable with the WebSocket silent on the hot
path; the local-search capability shipped; form validation latency ~0 with server
authority intact; the shared URL fixture green on both hosts.

---

### Phase 6 — size diet & distribution (per SKU)

**P6-T1 — embedded Swift subset evaluation.** build `WebUICore` with
`_wasm-embedded`; record which features survive (the trajectory §4 Phase 6 table);
if a core feature blocks, isolate behind a shim (internal only — never `#if
os(WASI)` in app-facing API, W§3.8).

**P6-T2 — tiered client products.** full-stdlib wasm (`swift-6.4.0-RELEASE_wasm`,
MB raw / ~300–700 KB gzipped) for internal/session apps; embedded wasm (kB) for
public/first-run SKUs; documentation states the feature/size trade-off per tier;
a representative page renders in each tier; no feature silently degrades.

**P6-T3 — (optional, postpone-able) WASI edge runtime.** serving the same binary
at the edge under a WASI runtime; recorded as a design note, not promised.

**P6 acceptance.** both tiers render a representative page; docs carry the
trade-off table; the embedded tier's feature delta is explicit and approved.

---

## 5. cross-cutting test & gate matrix

| layer | how | where |
|---|---|---|
| host unit (all modes) | Swift Testing, `swift test` (567/62 baseline, never regresses) | `Tests/WebUITests`, `WebUIAuthTests`, `WebUIDesignSystemMacroTests` |
| wasm unit (pure logic) | Swift Testing under `swift test --swift-sdk swift-6.4.0-RELEASE_wasm` (fallback: `--verify` modes via WasmKit, P1-T0-b) | `Tests/WebUIClientTests` |
| byte-identity / hydration | SSR vs wasm `--verify-render` diff (empty) in tests and gates | P1-T1, P2-T3 |
| asset integrity | magic `\0asm` + version + section walk on `WebUIAssets.wasm` | P1-T4, `WebUIClientTests` |
| CSP | `'wasm-unsafe-eval'` only on client-mode pages; server-mode bytes unchanged | P1-T4, `HTMLDocumentCSPTests` |
| import-surface pin | `.wasm` import list must equal the documented set | P1-T2 |
| live WS | `fullstack-smoke` (+ client-mode probes) | plugins |
| real DOM | `browser-smoke.mjs` (local search, optimistic arm/confirm/rollback, scroll survival, screenshot to `.smoke/`) | designer/ |
| static artifact | `showcase` regeneration, committed whole | plugin |

per-phase "done means" run order (section 3) is the only accepted definition of
green. `swift build --target X` is never trusted for product binaries (house
pitfall) — gates use the full `swift build` / wasm `--product` invocations; check
for stale port-squatting servers with `lsof` before blaming a fresh build.

---

## 6. documentation map

| change | doc |
|---|---|
| D3 verdicts, audit table | `WASM_SUBSET_AUDIT.md` (new), `WASM_TRAJECTORY.md` decision log |
| import surface, reactor shape, test-runner route | `WASM_BOOTSTRAP.md` (new) |
| client router/pump/state/sync | `WASM_CLIENT.md` (new) + `WASM_STATE.md` (new) |
| three-mode matrix, bridge ABI, pump | `ARCHITECTURE.md` |
| public surface additions (`ClientBoot`, `clientMode`, `renderFragment`, `ClientStateStore`, widening) | `API.md` |
| runtime re-seat + chamber | `JS_RUNTIME.md` |
| asset pipeline wasm pass, gate run order, "build wasm before gates" | `AGENTS.md` |
| css/tokens | unchanged (host-agnostic) |

docs update in the same commit as the API change they describe (documentation
discipline). in-the-moment analysis stays in the conversation, never in permanent
docs.

---

## 7. risks, trade-offs, and fallbacks

trajectory's risk register (W§4.1) is the load-bearing list and is not restated;
additions specific to this execution:

| risk | likelihood | impact | mitigation / fallback |
|---|---|---|---|
| `swift test --swift-sdk` runner gaps on this toolchain | med | low | P1-T0-b `--verify` modes via `swift run --swift-sdk` (WasmKit), asserted by gates |
| stale `.wasm` served (two-invocation build vs plugin embed) | med | med | asset plugin's input-files change detection + integrity pin (magic/section) + gates build wasm first |
| `.build` lock from a nested build inside a plugin | med | high | hard rule: wasm build is a separate invocation that completes before any plugin/command invocation; never a nested build |
| hand-rolled WASI/runtime adapter drifts from the real import set | med | med | P1-T2 import-surface pin (fail on undocumented imports) |
| `@TaskLocal`/swift-log/`_Concurrency` verdicts land on the throw-out path | med | low | D3 fallbacks fully specified (W§2.1.6 ambient context, W§2.1.16 `LogFunnel`, W§3.3 sync-equivalent) before any API is touched |
| full-SDK wasm size for public SKUs | med | med | P6 tiering (embedded kB product); measure at P1, decide with data |
| JSKit 40× headline invites scope creep | low | med | pinned in section 1.2: static narrow bridging is the shape; JSKit stays out (D1) |
| Swift 6.4 new warnings (`#NoUseUnstructuredThrowingTask` on unused throwing `Task {}`, SE-0493 `defer`-async) bite during port | low | low | treat as normal warnings-on-upgrade; use structured `withTaskGroup`/typed results per first law |

trade-off already implicit: byte-embedding the wasm into `WebUIAssets.wasm` grows
the server binary by the wasm size (MB) even for pages that never use client mode;
acceptable for internal apps (trajectory §5.2 Q4 says measure — P1-T3 measures and
records the number in `WASM_BOOTSTRAP.md`).

---

## 8. open questions → decision points

the trajectory's §5.2 open questions, mapped to where they get answered:

1. `@TaskLocal` on wasm (full vs embedded) → **P0-T4** (D3, with user).
2. swift-log on wasm → **P0-T4** (D3, with user).
3. `_Concurrency` on embedded → **P0-T4** + re-checked at **P6-T1** (sync-equivalent
   fallback W§3.3).
4. byte-embed size for internal apps → measured at **P1-T3**, tiered at **P6-T2**.
5. `clientMode` default → **opt-in forever** (A6); re-litigable at P4 docs with data.
6. telemetry channel → **reuse `state` now** (A7); dedicated message only if P3
   measurement shows noise.

---

## 9. execution handoff

when approved, each phase executes task-by-task in this plan's order with the
per-phase "done means" run order as the only definition of green, and every task
closes only on verified output. phase gates P0 and P1 are blockers for everything
after them. the plan's decisions A1–A8 are the defaults; any of their reversal
points (D3 verdicts, P2-T5 trim) are surfaced to the user before acting, never
silently changed.
