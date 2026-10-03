# lane B — d0 results (benches + build tooling)

_commit: t0.1 `c4f5fff` (WebUIBench) · t0.2 `554f1d2` (harness) · t0.4 budget re-pin (this unit) · base `d9c6cf6` (tree re-verified at that sha; engine bytes are the shipped `webui-engine.js` at base, untouched by lane B)._

## what landed

| task | deliverable | green |
|---|---|---|
| t0.1 | `Sources/WebUIBench/` — raw-NIO host, four stress fixtures (`/bench/feed /bench/grid /bench/dashboard /bench/editor`) + `/bench/feed?windowed=1[&ops=1]`; port `--port` else `WEBUI_BENCH_PORT` else 9130; charset=utf-8 on every text response | `swift build` + interaction smoke (6/6) |
| t0.2 | `designer/continuum-bench.mjs` — the six metric recipes of parent §3 (scrollFPS, echoLatency, patchCost, mutationCensus, tti, withThrottle); CLI `--bench <feed\|grid\|dashboard\|editor\|windowed> [--items/--rows/--cols/--series/--points] [--repeat N]`; writes `.bench/<bench>-<scale>[-throttled].json`; non-zero exit on failed precondition; `.bench/` gitignored | all five benches PASS loopback **and** throttled |
| t0.3 | windowing experiment on `/bench/feed?windowed=1`: naive (one whole-region `replace` per scroll step) vs ops variant (stable container + `append` entering rows + empty-fragment remove for leaving rows); scroll-delivery mechanism recorded (below); two probe scripts `designer/probes/b-*.mjs` | `b-windowed-smoke.mjs` + the `windowed` bench PASS both rungs |
| t0.4 | this record + the deliberate shipped-surface budget re-pin (below) | `swift package plugin budget` PASS |

## measured "today" (d0, this machine; bench host `.build/debug/WebUIBench`)

throttle per parent §3 recipe 6: CDP `Network.emulateNetworkConditions {latency: 80 ms, 10 Mb/s down, 5 Mb/s up}` — rtt is the binding constraint; bandwidth chosen so a 1.5 MB full-region update still completes in a sane window (a 100 kb/s link would make the throttled feed unmeasurable, which is itself a finding).

| metric | loopback | throttled (80 ms rtt) |
|---|---|---|
| tti · feed@10k | 102 ms | 709 ms |
| tti · grid 500×10 | 43 ms | 784 ms |
| tti · dashboard 8×100 | 97 ms | 762 ms |
| tti · editor | 23 ms | 756 ms |
| scroll fps · feed 10k full-render | p95 **62.4 ms**, 99.5 % frames > 16.7 ms | p95 61.5 ms, 99.5 % over |
| echo settled (debounce + rtt) · editor | **311 ms** | 368 ms |
| append-100 · replace | **1,501,978 B** recv / 46 ms rt | 1,562,778 B / 1,342 ms rt |
| append-100 · op (`append` ×100) | **19,531 B** recv / 33 ms rt | 19,531 B / 29 ms rt |
| grid sort · whole-table replace | 81,920 B / 32 ms | 81,920 B / 86 ms |
| dashboard tick · wall replace | 278,399 B / 67 ms | 278,402 B / 293 ms |
| editor commit | 182 B | 232 B (echo input debounce dominates: 300 ms) |
| mutation census: append-100 replace | **1** childList (the whole-region swap) | same |
| mutation census: append-100 op | **100** childList (100 appends), 0 char/attr | same |
| mutation census: grid sort | 1 childList | 1 |
| mutation census: dash tick | 1 childList | 1 |
| window step (60-row window @10k) naive | 8,694 B recv, 1 childList | 8,694 B, 7 ms |
| window step (60-row window @10k) ops | **2,191 B** recv, 20 childList | 2,191 B, 3 ms |

notes:

- the append-100 replace number is the honest wall: one interaction re-sends the **entire live list** (10,100 rows ≈ 1.5 MB) — 77× the op variant's 19.5 kB, and at 80 ms rtt it adds ~1.3 s of transfer. cost ∝ region, exactly as §0 premises.
- scroll fps at 10k full-DOM nodes is ~4 fps (p95 62 ms), i.e. the "60 fps / p95 ≤ 20 ms" budget is missed by >3× on **today's** full-render model — the windowing case is real, not aspirational.
- mutation census documents the mechanism: replace = one childList (whole region destroyed and rebuilt — even the observer attached inside it dies); ops = one childList per appended row. the observer must sit on a stable ancestor to count a replace at all.
- echo settled 311–368 ms ≈ 300 ms trailing debounce + (0 or 80 ms) rtt — the §3 budget's "keystroke echo < 50 ms at 80 ms rtt" is today 6–7× over, solely from the server round-trip model (no local echo).

## t0.3 — the windowing experiment and the scroll-delivery finding

mechanism used (recorded per parent §5 t0.3): **page-side scroll observer + routed click on today's engine.** today's engine has no scroll-event delivery (`webui-engine.js` `EVENT_TYPES` lacks `scroll`; there is no `onScroll` modifier), and lane B cannot add engine surface (lane E owns the engine). so the windowed page ships an external same-origin script (`/ui/bench-window.js`, allowed by `script-src 'self'`) that observes `#feed-window` scroll in the capture phase (survives the naive variant's whole-region replaces, which destroy element-attached listeners) and dispatches a routed click on the hidden `#feed-window-next` control. that is plan option (a)-lighter: the *delivery* of scroll is page-authored for the fixture; the *round trip* it feeds is today's real wire.

round-trip cost of one window step (observer click → server → fragment): **≈ 0.7 ms loopback, 3–7 ms at 80 ms rtt** for both variants — the click path itself is cheap. the cost is not the round trip but the **payload**: the naive variant re-sends 8,694 B (the whole 60-row window) per step vs 2,191 B for the ops variant (10 `append` + 10 empty-remove), a **4× byte reduction per step** with exactly-20 vs exactly-1 childList mutations.

the finding d1 needs: **windowing must be engine- or island-local.** a server-orchestrated window (even with ops) cannot reach sustained 60 fps scroll: every step is a full event→server→fragment round trip, and at the naive payload size the transfer alone busts the frame budget on any real rtt (see throttled replace +1.3 s). engine-local windowing (t1.4) or the island path (d2) is where the 60-row slice must live; the d0 number that says so is scroll p95 **62 ms on 10k full-render nodes**, plus the window-step byte asymmetry.

## stop/go verdict (parent §7-C)

adjudicated for the orchestrator at i1.

1. **§7-C-1: d0 kills the island track's necessity? NO.** server-orchestrated windows (naive *and* op) both leave the feed at 62 ms p95 scroll frames on the full-render base, and the throttled append-replace takes 1.3 s. the landed ops reduce *bytes* (19.5 kB vs 1.5 MB) but do not fix *latency* (each interaction is still a full round trip). **keep d1 (pays alone: ops + echo + inventory) and d2/d3 (windowing placement).**
2. **§7-C-2: d0 kills dom windowing? NO.** the ops window step is 2,191 B/3 ms at 80 ms rtt — engine-local dom windowing is clearly inside reach of the 20 ms p95 frame budget. no canvas promotion warranted on this evidence.
3. **loopback self-deception (the gate):** every number above has a throttled twin; no budget got a loopback-only green. echo settled, tti, and replace rt all move materially under 80 ms rtt.
4. **budget re-pin is deliberate (t0.4):** engine measured **52,433 B raw / 12,744 gz** at the d0 tree against the shipped pin **46,000 / 11,600** — blown by the landed oct-2 wire growth (52,433 / 12,744 vs 46,000 / 11,600; `wc -c designer/assets/webui-engine.js`). `WebUIBudgetPlugin`'s designed trip fired and is now **re-pinned to 55,000 raw / 13,600 gz** with documented rationale (headroom above the measured 52,433/12,744 so the next growth spur — d1 engine bytes for op apply/coalescer/echo — trips it deliberately, not on landing). **the gate now PASSES.** the ruling: the engine surface pin is deliberately raised at d0; lane E's d1 additions get a fresh ceiling and a second deliberate trip rather than an immediate re-trip.

## gates (exact, this run)

```
swift build                                             -> Build complete
node designer/continuum-bench.mjs --bench {editor,grid,dashboard,feed,windowed} ... -> PASS ×5 (loopback + throttled)
node designer/probes/b-interaction-smoke.mjs            -> 6/6 PASS
node designer/probes/b-windowed-smoke.mjs               -> 5/5 PASS
swift package --disable-sandbox plugin budget           -> budget: PASS
```

`swift test` FULL runs as the lane's terminal gate (below).

## rollout (the d0 table for parent §5)

| bench | today model | loopback | throttled (80 ms) | what fixes it (measured) |
|---|---|---|---|---|
| feed 10k | full-render, replace per interaction | tti 102 ms; scroll p95 62.4 ms; append-100 replace 1.5 MB | tti 709 ms; append-100 replace +1.3 s | ops (19.5 kB) + engine-local window ✓ |
| grid 500×10 | whole-table replace per sort | tti 43 ms; sort 82 kB | tti 784 ms | ops (attr/move/remove) + windowed surface |
| dashboard 8×100 | whole-wall replace per tick | tti 97 ms; tick 278 kB | tti 762 ms; +226 ms rt | island/op-stream re-render |
| editor | server echo (300 ms debounce + rtt) | echo settled 311 ms | 368 ms | t1.4 local echo |
| strictly today's bar: ops | replace vs append | 1.5 MB vs 19.5 kB (77×) | same | d1 wire |

## stale-row refresh (parent §2, for the orchestrator to fold)

- engine `52,433 B raw / 12,744 gz, 1,579 lines` — confirmed at the d0 tree (`wc -c designer/assets/webui-engine.js`), unchanged by lane B.
- the shipped-surface budget breach is now deliberate-re-pinned: engine ceiling 46,000/11,600 → **55,000/13,600** (comment names the measured 52,433/12,744 and the d1 headroom rationale).
- showcase row census and island size are not re-measured here (showcase regen + wasm build are orchestrator/other-lane gates); the landed numbers (§2: rich row 825→792 on regen; island 164,670 stripped) stand as recorded.

## cross-lane notes

- to E (engine): `designer/assets/webui-engine.js` stays untouched in lane B; the new `remove`/`attr`/`move` ops (t1.1) will let the windowing ops-variant drop its empty-fragment-remove idiom. the windowed-page scroll observer exists only because the engine lacks `scroll` delivery — d1's additive `onScroll` (or t1.4 engine-local window) replaces it.
- to C (islands): the window step bytes (2,191 B ops vs 8,694 B naive) are the d2 island placement input.
- to D (surface): `@HotView`'s class inventory consumer will read `Continuum+Generated.swift` (t1.3, unit in this lane) — per-component class sets + union + attr allowlists, emitted by the build plugin.
