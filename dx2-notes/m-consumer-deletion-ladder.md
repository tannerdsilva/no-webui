# lane M — the consumer-deletion ladder (measured)

_lane M · LIVE_DX W2, feature D · branch: `task/m-ladder` · base: `c24857a` (= `origin/dev-subst` = i1) · 2026-10-05_

> **the 19% lesson, stated first.** the CONTINUUM theme-port *guessed* ">50% shrink" and
> **measured 19%** (`Sources/ArcTheme/ThemeCatalog.swift:14`). every number below is emitted by
> the reproducing script in appendix A against the i1 head; nothing is projected. where a
> measurement is extended to arc's full scale, it is labeled as a band-check, not a number.

---

## 0. the ladder, in one table

| seam | arc's deleted shape | the substituted shape | ΔLOC (measured) | touchpoints (measured) | Δwire (measured) |
|---|---|---|---|---|---|
| **wiring** (DX-12/14) | boot-time `wire(router,id:)` registrations + hand `btn(id, component)` emitter | `control(_:handler:)` call sites; handler-rendered controls self-register | **−22** (111 → 89; 13.9 → 11.1 lines/control) | **3→1** id statements per control (2 files → 1) | — (routing unchanged) |
| **push** (DX-13/16) | `PushDeduper` + `IntervalService` + 3 poll Services and their guards | `WebUILiveRegions` + `ClosureLiveRegion`/`StateLiveRegion` + `LiveBox` (+ custom `LiveState` twin) | **−68** (94 → 26; 31.3 → 8.7 lines/driver) | logbox 3→2 · status 2→1 statements | one nav click: **92,142 B → 11,087 B** (−88%) |
| **theme tooling** (DX-15a) | `ProtoAssetTool` + `ProtoAssetPlugin` + the `Package.swift` block (= arc's 81-line `ArcAssetTool`/`ArcAssetPlugin` pair) | one `.plugin(name: "WebUIThemePlugin", package: "no-webui")` attach; the framework's tool does the work | **−82** (85 → 3) | — | — |
| **collisions** (DX-15b) | a string sheet re-skinning 9 DS classes (`chip`, `kv`, `toast`, `modal-overlay`, `log-line`, `md`, `swatch`, `inline-edit`, `tool-btn`) | typed `@Theme(rules:)` + token-only values + namespaced selectors | 9 → **0** collisions (headline) · 10 → **0** (deep, real DS union) | — | — |

the headline wire number against arc's recorded baseline: arc's whole-`#app` nav click measured
**136,195 B** (CONTINUUM_DX §1.3). this cut's whole-`#app` click measures **92,142–99,099 B**
payload — same order; the substituted click pushes the changed region only: **11,087–18,484 B**.

---

## 1. the prototype (what actually ran)

`/tmp/dx2-consumer-prototype` — a scratch Swift package, **never committed to the repo**. one
target pair per shape, both compiled and run against the **i1 head** (`/tmp/continuum-fleet/lane-d`
@ `c24857a`, asserted by the script's precondition block):

- **ProtoBefore** (:9380, and :9382 with `--no-dedupe`) — ports arc's shapes:
  `Sources/ProtoBefore/Helpers.swift` (the hand `btn(id, component)` emitter),
  `Controllers.swift` (the `wire(router,id:)` controller + 8 boot-time registrations),
  `PushLayer.swift` (`PushDeduper` + `IntervalService` + 3 poll Services and their guards),
  `Sources/ProtoAssetTool` + `Plugins/ProtoAssetPlugin` (the consumer sheet tooling),
  `Sources/ProtoTheme/ChromeSheet.swift` (the string sheet carrying the 9 shadowed classes).
- **ProtoAfter** (:9381) — the substitution:
  `Controls.swift` (`control(_:handler:)` call sites + a handler-rendered control),
  `Regions.swift` (3 regions: closure / `LiveBox`-bound / custom-`LiveState`-actor-bound),
  `Theme.swift` (typed `rules` + tokens; the framework plugin emits the sheet).
- the wire client is **Python 3.9 stdlib only** (`scripts/ws_probe.py`, appendix B): a raw
  WebSocket client that clicks ids it can see and counts the exact bytes the server sends.

both hosts render **the same content** for the same state (600 log lines, a 200-row sidebar,
100/60 content rows); the sheet/scaffold differences are the measured layers. lifecycle and
framework semantics (`LiveBox` notify-after-unlock, region byte-compare, the dispatch seam) are
the framework's own at i1 — the prototype consumes them, it does not re-implement them.

**the scenario** (one probe session per host): connect → `nav-ws` → `nav-home` → `add-log` →
`poke` → `refresh` → `detail-open` → `detail-close` → idle 2.5 s. `poke` invalidates/re-emits
*unchanged* chrome; `detail-*` swaps a handler-rendered control in and out.

---

## 2. per-seam results (all numbers from appendix C)

### 2.1 wiring (DX-12/14) — deleted: the boot-wiring pass

- **deleted shape** (ported, measured): 111 lines = 8 (`btn` helper) + 103 (the `wire` helper,
  `wireAll`, 8 registrations, their event-filter guards, and the handler bodies that must live
  away from the emission site). the id is stated twice per control at the registration+emission
  sites (arc's note: "up to three times").
- **substituted shape**: 89 lines = one `control(_:event:handler:)` call site per control; the
  call registers AND emits; a control first rendered *inside a handler* self-registers (the
  seam), so nothing is pre-wired.
- **measured**: ΔLOC −22 (13.9 → 11.1 lines/control over 8 controls; the bodies themselves are
  unchanged and cancel). the *scaffold-only* deletion rate is 2.75 lines/control — arc's own
  inventory estimated its 128 registrations carried 250–400 lines of pure scaffold
  (≈3.1±0.8/control). **band-check: the cut's measured rate lands inside that band.** arc's
  full number is arc's to measure (d-j), not this lane's to project.
- **touchpoints (measured by `grep` on id string-literals)**: `nav-ws`, `add-log`, `poke`,
  `detail-open`, `detail-close` each: **before `files=2 occurrences=3` → after `files=1
  occurrences=1`**. adding a control to the ported shape means editing the controller AND the
  renderer; adding one to the substitution means editing one call site.
- **runtime evidence**: in both shapes the handler-rendered control answers a later click
  (`detail-open` → 348 B frame → `detail-close` → 212 B frame, before; 366 B → 192 B, after).

### 2.2 push (DX-13/16) — deleted: the deduper + poll Services

- **deleted shape** (ported, measured): 94 lines = `PushDeduper` (13 LoC at arc
  `WebUIHost.swift:15`) + `IntervalService` + 3 poll Services (`log-stream` 400 ms,
  `workspace-tree` 3 s, `chrome-refresh` 1 s) and their guards.
- **substituted shape**: 26 lines = 3 region declarations. the registry owns rendering, change
  detection, cadence, serialization and pump lifetime.
- **measured**: ΔLOC −68 (31.3 → 8.7 lines/driver over 3 drivers).
- **Δwire (the measured scenario; payload B = WebSocket text frames as received, html B = the
  fragments' html):**

| scenario | before (deduper ON) | before (`--no-dedupe`) | after (regions) |
|---|---|---|---|
| nav click, `nav-ws` | **1 frame · 92,142 B payload · 88,886 B html** (whole `#app`) | 2 frames · 92,250 · 88,933 | **1 frame · 11,087 · 10,296** (the `main` region) |
| nav click, `nav-home` | 1 frame · 99,099 · 95,363 (whole `#app`) | 2 frames · 99,207 · 95,410 | 1 frame · 18,484 · 17,213 (the `main` region) |
| add-log (a real change) | 2 frames · 58,352 · 57,028 | 4 frames · 58,568 · 57,122 | 2 frames · 60,159 · 58,835 |
| poke (unchanged re-emit / invalidation) | **0 frames** (deduper absorbs) | **3 frames · 116,596 · 114,009** | **0 frames** (framework byte-compare, I7) |
| idle 2.5 s | **0 frames** | 2 frames · 216 · 94 | **0 frames** |
| refresh | 1 frame · 17,378 · 16,107 | 2 frames · 17,486 · 16,154 | 1 frame · 18,484 · 17,213 |
| detail-open / detail-close | 348/212 B | 456/320 B | 366/192 B |

  - **the headline**: a whole-`#app` nav replace measures **92,142 B → 11,087 B** (−88%;
    8.3× payload, 8.6× html on `nav-ws`; 5.4× on `nav-home`). arc's recorded whole-app click
    (136,195 B) sits in the same class as this cut's 92–99 KB whole-app numbers.
  - **the deduper's deletion is evidenced twice**: `poke` costs the ported shape 116,596 B
    without the deduper and 0 with it — the after gets the 0 from the framework with **zero
    consumer lines**. idle is the same story (216 B + 2 frames vs 0).
  - the before host's one *first-copy* nuance, measured and named: the `chrome-refresh` poller
    re-emits unchanged chrome every second; the deduper suppresses every repeat, but its map
    starts empty, so the first copy can ship once while a client is attached (observed once in
    this run: a 47 B status frame in the connect window). the steady state is 0. the after has
    no such window: `poke` and idle are 0 from the first click.
  - observed framework warning (after host, once): `live region 'main' grew the handler map
    across a render (0 → 1); stable ids only` — the baseline render registering `detail-open`
    for the first time. stable ids mean growth stops at 1 (subsequent renders overwrite);
    recorded because it is exactly the warning the contract promises.

### 2.3 theme tooling (DX-15a) — deleted: the consumer tool + plugin

- **deleted shape** (ported, measured): 85 lines = `ProtoAssetTool` 36 + `ProtoAssetPlugin` 34 +
  15 lines of `Package.swift` block (arc's recorded pair: 43 + 38 = 81 lines + its manifest
  block). receipts from the build: `sheet 1541 bytes, stamp 0e6f68f6827f, gzip 589 bytes`.
- **substituted shape**: 3 lines — the plugin attach. the framework's `WebUIThemePlugin` +
  `WebUIThemeTool` drive a direct `swiftc` over the catalog; the emitted conformance
  (`ProtoAfterCatalogSheet`, 4817 B source) compiles into the target. receipt:
  `emitted ProtoAfterCatalogSheet: 2103 B, gzip 470 B, stamp 8d5e2fc32cf5`.
- **measured**: ΔLOC −82. both sheets are **served at `/ui/theme.css`** (HTTP 200: 1541 B
  before / 2103 B after — measured), so the pipeline is proven end-to-end, not merely built.
- note: the after's 3 attach lines still require (as arc did) a declared catalog; the *catalog
  itself* is not part of the deleted layer and is present in both shapes.

### 2.4 collisions (DX-15b) — 9 → 0

- **before**: the string sheet declares the 9 contract classes and the markup (tree-wide) uses
  5 of them. measured by `WebUIContinuumTool shadow`:
  - headline (the contract's built-in nine-class reference): **9 collisions** — all nine named
    with owners (`chip`→WebUIChip, `kv`, `toast`→WebUIToast, `modal-overlay`→WebUIModal,
    `log-line`, `md`→markdownBody, `swatch`, `inline-edit`→WebUIInlineEdit, `tool-btn`).
  - deep (against the real `designer/assets/design-system.css` union): **10** (the nine plus
    `chip--primary`).
  - tree-wide before (markup included): **5** (chip, kv, log-line, md, swatch — a subset of the
    nine).
- **after**: typed `rules` + tokens, namespaced selectors — **0 / 0 / (tree 0)** on the same
  three scans. the declarations did not vanish; they moved to a namespace that cannot shadow.
- an intermediate pass surfaced two extractor artifacts (`.count` / `.swift` inside string
  literals read as class tokens — the extractor's string-literal leg is deliberately broad);
  the prototype sources were cleaned of them and the **final committed runs (appendix C) are
  artifact-free** — every scan output quoted above comes from those runs.

---

## 3. what did NOT shrink (and why)

1. **item 5's full 2,810-line chrome conversion stays a follow-on (d-w).** this ladder never
   claims the chrome sheet shrank: the prototype proves the *architecture* (typed `rules:` +
   token policy + the shadow check reading 0) on **12 rule entries**, one family. the 2.8k-line
   conversion is measured by this ladder only as the collision count (9 → 0); its line count is
   unchanged by design and awaits d-w. **say it plainly: the 2,810 lines are not deleted here.**
2. **handler bodies / domain logic.** the wiring Δ is small (−22) precisely because behavior is
   unchanged: the seam deletes *plumbing* (registration ceremony, id restatements, the helper),
   not what a click does. per-control scaffolding ≈2.75 lines deleted; bodies cancel.
3. **page content bytes.** both hosts ship the same 600 log lines / 200 sidebar rows / content
   rows. the after's namespaced class names make its logbox push a few bytes *larger*
   (57,028 → 58,835 B html). content is content.
4. **the 9 classes' CSS declarations.** they move into typed rules; collisions → 0 is a
   namespace fact, not a line reduction (see §3.1).
5. **the after's reliance on framework lines.** the registry, codec, and byte-compare are
   framework-side lines the consumer no longer writes — the consumer-visible surface is what
   shrank (measured); the framework's cost is real and out of this lane's scope.
6. **domain producers still exist.** something must still *cause* changes (a click, a stream).
   what died is the poll+guard+push+dedupe plumbing around them, not the events themselves.

---

## 4. assumptions & method notes

1. the port is a **cut** (8 controls, 3 drivers, 2 themes): per-unit rates are measured;
   full-arc totals are cited from the plan inventory (and spot-checked read-only against the arc
   worktree at `ae67d73a`: Actions.swift 2,835 lines / 124 `wire(router…` calls + a 5-case nav
   loop = 128 registrations; `Helpers.swift` 77 lines, `btn` at :74; `IntervalService.swift` 47;
   `ArcAssetTool` 43; `ArcAssetPlugin` 38; `ChromeSheet.swift` 2,810 lines).
2. byte counts: "payload" = WebSocket text-frame payload bytes as received (the JSON frame);
   "html" = Σ utf8 length of the fragments' `html` fields. both are emitted by the probe.
3. after-add-log latency: the before host pushes via its 400 ms poll (window 1.4 s); the after
   pushes state-driven (immediate). windows are fixed per step in the probe, so both are
   captured whole.
4. **execution context**: the Hermes terminal backend went down mid-run; the script was run via
   a thin audit-test adapter (`Tests/LadderTests` in the prototype — not part of any measured
   layer: it spawns `scripts/measure.sh` unchanged and surfaces its exit). on a normal machine
   the reproduction is exactly `bash scripts/measure.sh`. the adapter is disclosed here so no
   number depends on a hidden path.
5. ports 9380/9381/9382 only (the lane block); hosts bind 127.0.0.1.
6. the `--no-dedupe` counterfactual is a runtime flag on the before host (bypasses
   `PushDeduper.filter` only) — it isolates the deduper's own contribution to the deleted layer.
7. shadow scans: "headline" = the contract's built-in nine-class reference (no `--ds-css`);
   "deep" = `--ds-css designer/assets/design-system.css`; "tree-wide" = the ProtoBefore sources
   including markup literals.

---

## appendix A — the reproducing script

`/tmp/dx2-consumer-prototype/scripts/measure.sh` (executed to produce appendix C):

#!/usr/bin/env bash
# ============================================================================
# lane M — the consumer-deletion ladder: the reproducing script.
#
# runs against:  /tmp/dx2-consumer-prototype  (this prototype, never committed)
# framework:     /tmp/continuum-fleet/lane-d  @ c24857a (the i1 head)
# output:        $PROTO/out/measure-raw.txt  (raw; embedded in
#                dx2-notes/m-consumer-deletion-ladder.md)
#
# measures, per seam: ΔLOC, Δwire bytes, touchpoints.
# every number below is emitted by this script; nothing is projected.
# ============================================================================
set -u
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export LC_ALL=C

PROTO=/tmp/dx2-consumer-prototype
FRAME=/tmp/continuum-fleet/lane-d
PROBE="$PROTO/scripts/ws_probe.py"
TOOL="$FRAME/.build/out/Products/Debug/WebUIContinuumTool"
[ -x "$TOOL" ] || TOOL="$FRAME/.build/debug/WebUIContinuumTool"
OUT="$PROTO/out/measure-raw.txt"
mkdir -p "$PROTO/out"
: > "$OUT"

log()  { echo "$@" | tee -a "$OUT"; }
rule() { log ""; log "================================================================================"; }

run() {
  log "\$ $*"
  "$@" 2>&1 | tee -a "$OUT"
  return "${PIPESTATUS[0]}"
}

# count lines BETWEEN two marker lines in a file (exclusive).
section() {
  awk -v b="$1" -v e="$2" 'index($0,b){f=1;next} index($0,e){f=0} f{c++} END{print c+0}' "$3"
}

# touchpoints: where a control/region id is STATED as a string literal.
tp() {
  local dir="$1" id="$2"
  local files occurrences
  files=$(grep -r --include="*.swift" -l -- "\"$id\"" "$dir" 2>/dev/null | wc -l | tr -d ' ')
  occurrences=$(grep -r --include="*.swift" -o -- "\"$id\"" "$dir" 2>/dev/null | wc -l | tr -d ' ')
  echo "files=$files occurrences=$occurrences"
}

kill_port() {
  local pids
  pids=$(lsof -ti tcp:"$1" 2>/dev/null)
  if [ -n "$pids" ]; then kill $pids 2>/dev/null; sleep 0.4; fi
}
wait_http() {
  local i
  for i in $(seq 1 60); do
    if curl -s -o /dev/null "http://127.0.0.1:$1/"; then return 0; fi
    sleep 0.25
  done
  return 1
}

rule "== lane M — consumer-deletion ladder · raw measured output =="
log "date:      $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
log "host:      $(uname -sm)"
log "swift:     $(swift --version 2>&1 | head -1)"
log "python3:   $(python3 --version 2>&1)"
log "prototype: $PROTO"
log "framework: $FRAME"

rule "== 0. preconditions =="
log "framework head: $(git -C "$FRAME" rev-parse HEAD)"
log "framework branch: $(git -C "$FRAME" branch --show-current)"
if [ "$(git -C "$FRAME" rev-parse HEAD)" != "c24857a6aeca0d40112635263dc365a8ffb53173" ]; then
  log "FATAL: framework head is not the i1 head c24857a — refusing to measure"
  exit 1
fi
log "framework HEAD == c24857a (i1): OK"
log "prototype vendor symlink: $(readlink "$PROTO/vendor/no-webui")"
kill_port 9380; kill_port 9381; kill_port 9382
log "ports 9380-9382 cleared"

rule "== 1. build the prototype (both shapes) =="
run swift build --package-path "$PROTO"
BIN=$(swift build --package-path "$PROTO" --show-bin-path)
log "bin path:  $BIN"

rule "== 2. theme emission — the build products of each shape =="
log "-- before: the consumer tool's emitted sheet (ProtoAssetPlugin) --"
for f in $(find "$PROTO/.build/plugins/outputs" -name "ProtoSheetAssets.swift" 2>/dev/null); do
  log "  $f"
  log "  bytes: $(wc -c < "$f" | tr -d ' ')"
  grep -o 'stamp = "[0-9a-f]*"' "$f" | head -1 | sed 's/^/  /'
done
log "-- after: the framework plugin's emitted sheet (WebUIThemePlugin) --"
for f in $(find "$PROTO/.build/plugins/outputs" -name "ProtoAfterCatalogSheet.swift" 2>/dev/null); do
  log "  $f"
  log "  bytes: $(wc -c < "$f" | tr -d ' ')"
  grep -o 'stamp = "[0-9a-f]*"' "$f" | head -1 | sed 's/^/  /'
done
log "-- tool receipts (repeat build; the first run's receipts are in section 1) --"
run swift build --package-path "$PROTO" 2>&1 | grep -i "sheet\|emitted" || true

rule "== 3. shadow check — the collisions seam (DX-15b) =="
log "-- headline: the contract's nine-class built-in reference --"
run "$TOOL" shadow --sources "$PROTO/Sources/ProtoTheme" --demo
run "$TOOL" shadow --sources "$PROTO/Sources/ProtoAfter" --demo
log "-- deep: against the real design-system sheet union --"
run "$TOOL" shadow --sources "$PROTO/Sources/ProtoTheme" --ds-css "$FRAME/designer/assets/design-system.css" --demo
run "$TOOL" shadow --sources "$PROTO/Sources/ProtoAfter" --ds-css "$FRAME/designer/assets/design-system.css" --demo
log "-- tree-wide before (markup included) --"
run "$TOOL" shadow --sources "$PROTO/Sources/ProtoBefore" --demo
run "$TOOL" shadow --sources "$PROTO/Sources/ProtoBefore" --ds-css "$FRAME/designer/assets/design-system.css" --demo

rule "== 4. ΔLOC — per seam, marker-delimited =="
WB_HELP=$(section "SEAM:wiring-begin" "SEAM:wiring-end" "$PROTO/Sources/ProtoBefore/Helpers.swift")
WB_CTRL=$(section "SEAM:wiring-begin" "SEAM:wiring-end" "$PROTO/Sources/ProtoBefore/Controllers.swift")
WA_CTRL=$(section "SEAM:wiring-begin" "SEAM:wiring-end" "$PROTO/Sources/ProtoAfter/Controls.swift")
PB_LAYER=$(section "SEAM:push-begin" "SEAM:push-end" "$PROTO/Sources/ProtoBefore/PushLayer.swift")
PB_MAIN=$(section "SEAM:push-begin" "SEAM:push-end" "$PROTO/Sources/ProtoBefore/main.swift")
PA_REG=$(section "SEAM:push-begin" "SEAM:push-end" "$PROTO/Sources/ProtoAfter/Regions.swift")
PA_MAIN=$(section "SEAM:push-begin" "SEAM:push-end" "$PROTO/Sources/ProtoAfter/main.swift")
TB_TOOL=$(wc -l < "$PROTO/Sources/ProtoAssetTool/main.swift" | tr -d ' ')
TB_PLUGIN=$(wc -l < "$PROTO/Plugins/ProtoAssetPlugin/plugin.swift" | tr -d ' ')
TB_PKG=$(section "SEAM:theme-before-begin" "SEAM:theme-before-end" "$PROTO/Package.swift")
TA_PKG=$(section "SEAM:theme-after-begin" "SEAM:theme-after-end" "$PROTO/Package.swift")

log "wiring.before  = $WB_HELP (Helpers btn) + $WB_CTRL (Controllers) = $((WB_HELP + WB_CTRL)) lines"
log "wiring.after   = $WA_CTRL (Controls) = $WA_CTRL lines"
log "wiring.delta   = $((WB_HELP + WB_CTRL - WA_CTRL)) lines deleted"
log "push.before    = $PB_LAYER (PushLayer) + $PB_MAIN (main) = $((PB_LAYER + PB_MAIN)) lines"
log "push.after     = $PA_REG (Regions) + $PA_MAIN (main) = $((PA_REG + PA_MAIN)) lines"
log "push.delta     = $((PB_LAYER + PB_MAIN - PA_REG - PA_MAIN)) lines deleted"
log "theme.before   = $TB_TOOL (ProtoAssetTool) + $TB_PLUGIN (ProtoAssetPlugin) + $TB_PKG (Package block) = $((TB_TOOL + TB_PLUGIN + TB_PKG)) lines"
log "theme.after    = $TA_PKG (Package attach) = $TA_PKG lines"
log "theme.delta    = $((TB_TOOL + TB_PLUGIN + TB_PKG - TA_PKG)) lines deleted"
log "per-control rate (8 controls): before=$(awk -v a=$((WB_HELP + WB_CTRL)) 'BEGIN{printf "%.1f", a/8}') lines/control · after=$(awk -v a=$WA_CTRL 'BEGIN{printf "%.1f", a/8}') lines/control"
log "per-driver rate (3 pollers → 3 regions): before=$(awk -v a=$((PB_LAYER + PB_MAIN)) 'BEGIN{printf "%.1f", a/3}') lines/driver · after=$(awk -v a=$((PA_REG + PA_MAIN)) 'BEGIN{printf "%.1f", a/3}') lines/driver"

rule "== 5. touchpoints — id statements per new control/region =="
log "before tree ($PROTO/Sources/ProtoBefore):"
for id in nav-ws add-log poke detail-close detail-open; do
  log "  \"$id\": $(tp "$PROTO/Sources/ProtoBefore" "$id")"
done
log "after tree ($PROTO/Sources/ProtoAfter):"
for id in nav-ws add-log poke detail-close detail-open; do
  log "  \"$id\": $(tp "$PROTO/Sources/ProtoAfter" "$id")"
done
log "region ids:"
log "  before \"logbox\": $(tp "$PROTO/Sources/ProtoBefore" "logbox")"
log "  after  \"logbox\": $(tp "$PROTO/Sources/ProtoAfter" "logbox")"
log "  before \"status\": $(tp "$PROTO/Sources/ProtoBefore" "status")"
log "  after  \"status\": $(tp "$PROTO/Sources/ProtoAfter" "status")"

rule "== 6. wire bytes — a raw client, per scenario =="
log "-- before @ :9380 (deduper ON) --"
kill_port 9380
"$BIN/ProtoBefore" --port 9380 > "$PROTO/out/before-run.log" 2>&1 &
BEFORE_PID=$!
wait_http 9380 && log "  [proto-before up]" || log "  FATAL: before host did not come up"
run python3 "$PROBE" --port 9380 --label before
log "  [http] before /ui/theme.css: $(curl -s -o /dev/null -w '%{http_code} bytes=%{size_download}' 'http://127.0.0.1:9380/ui/theme.css')"
kill $BEFORE_PID 2>/dev/null; wait $BEFORE_PID 2>/dev/null; kill_port 9380

log "-- before @ :9382 (--no-dedupe; the counterfactual) --"
kill_port 9382
"$BIN/ProtoBefore" --port 9382 --no-dedupe > "$PROTO/out/before-nodedupe-run.log" 2>&1 &
BEFORE_ND_PID=$!
wait_http 9382 && log "  [proto-before --no-dedupe up]" || log "  FATAL: before (no-dedupe) did not come up"
run python3 "$PROBE" --port 9382 --label before-nodedupe
kill $BEFORE_ND_PID 2>/dev/null; wait $BEFORE_ND_PID 2>/dev/null; kill_port 9382

log "-- after @ :9381 (regions) --"
kill_port 9381
"$BIN/ProtoAfter" --port 9381 > "$PROTO/out/after-run.log" 2>&1 &
AFTER_PID=$!
wait_http 9381 && log "  [proto-after up]" || log "  FATAL: after host did not come up"
run python3 "$PROBE" --port 9381 --label after
log "  [http] after /ui/theme.css: $(curl -s -o /dev/null -w '%{http_code} bytes=%{size_download}' 'http://127.0.0.1:9381/ui/theme.css')"
kill $AFTER_PID 2>/dev/null; wait $AFTER_PID 2>/dev/null; kill_port 9381

rule "== done =="
log "raw output: $OUT"
log "host logs: $PROTO/out/{before,before-nodedupe,after}-run.log"

## appendix B — the raw wire client

`/tmp/dx2-consumer-prototype/scripts/ws_probe.py` (Python 3.9 stdlib only):

#!/usr/bin/env python3
"""lane M wire probe — a RAW WebSocket client (Python stdlib only).

drives a dx2-consumer-prototype host over /ws and measures the exact bytes the
server puts on the socket per scenario. no browser, no npm, nothing inferred:

  nav-ws / nav-home   a content-swap click (the whole-#app-replace baseline)
  add-log             log growth (one real change)
  poke                unchanged (re)emission / invalidation — I7
  refresh             main-scope update
  detail-open/close   a handler-rendered control answering
  idle                a silence window (no sends)

usage:
  ws_probe.py --port 9380 --label before
  ws_probe.py --port 9382 --label before-nodedupe --set poke1x
  ws_probe.py --port 9381 --label after

raw output: one line per step, e.g.
  [wire] before nav-ws: frames=1 payload=90572 html=90241 ids=app
"""
import argparse
import base64
import json
import os
import socket
import struct
import sys
import time


def ws_connect(host, port, path="/ws", timeout=6.0):
    s = socket.create_connection((host, port), timeout=timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        "GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\n"
        "Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n"
        % (path, host, port, key)
    )
    s.sendall(req.encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            raise RuntimeError("closed during handshake")
        buf += chunk
    head, _, rest = buf.partition(b"\r\n\r\n")
    status = head.split(b"\r\n", 1)[0].decode()
    if "101" not in status:
        raise RuntimeError("handshake failed: %s" % status)
    return s, rest


def _mask(payload):
    m = os.urandom(4)
    return m, bytes(b ^ m[i % 4] for i, b in enumerate(payload))


def send_text(sock, text):
    payload = text.encode()
    header = bytearray([0x81])
    n = len(payload)
    if n < 126:
        header.append(0x80 | n)
    elif n < 65536:
        header.append(0x80 | 126)
        header += struct.pack("!H", n)
    else:
        header.append(0x80 | 127)
        header += struct.pack("!Q", n)
    m, masked = _mask(payload)
    sock.sendall(bytes(header) + m + masked)


def send_pong(sock, payload):
    header = bytearray([0x8A])
    n = len(payload)
    if n < 126:
        header.append(0x80 | n)
    elif n < 65536:
        header.append(0x80 | 126)
        header += struct.pack("!H", n)
    else:
        header.append(0x80 | 127)
        header += struct.pack("!Q", n)
    m, masked = _mask(payload)
    sock.sendall(bytes(header) + m + masked)


def parse_frames(buf, frames):
    """pull every complete frame out of `buf`; append (opcode, payload)."""
    while True:
        if len(buf) < 2:
            return buf
        b0, b1 = buf[0], buf[1]
        opcode = b0 & 0x0F
        masked = (b1 >> 7) & 1
        ln = b1 & 0x7F
        idx = 2
        if ln == 126:
            if len(buf) < 4:
                return buf
            ln = struct.unpack("!H", buf[2:4])[0]
            idx = 4
        elif ln == 127:
            if len(buf) < 10:
                return buf
            ln = struct.unpack("!Q", buf[2:10])[0]
            idx = 10
        if masked:
            idx += 4
        if len(buf) < idx + ln:
            return buf
        payload = buf[idx:idx + ln]
        buf = buf[idx + ln:]
        frames.append((opcode, payload))


def collect(sock, window, leftover=b""):
    """collect frames for `window` seconds; return (frames, leftover_buf)."""
    frames = []
    buf = leftover
    deadline = time.time() + window
    sock.settimeout(0.08)
    while True:
        remaining = deadline - time.time()
        if remaining <= 0:
            break
        try:
            chunk = sock.recv(1 << 16)
            if not chunk:
                break
            buf += chunk
        except socket.timeout:
            continue
        buf = parse_frames(buf, frames)
    # settle: one last drain of anything already buffered
    buf = parse_frames(buf, frames)
    return frames, buf


def summarize(frames):
    """text-frame payload bytes + parsed fragment ids/html bytes."""
    payload_bytes = 0
    html_bytes = 0
    ids = []
    texts = 0
    for opcode, payload in frames:
        if opcode == 0x1:  # text
            texts += 1
            payload_bytes += len(payload)
            try:
                msg = json.loads(payload.decode("utf-8"))
            except Exception:
                continue
            if msg.get("type") == "update":
                for frag in msg.get("fragments", []):
                    ids.append(frag.get("id", "?"))
                    html_bytes += len(frag.get("html", "").encode("utf-8"))
    return texts, payload_bytes, html_bytes, ids


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--steps", default="nav-ws,nav-home,add-log,poke,refresh,detail-open,detail-close,idle")
    args = ap.parse_args()

    event_steps = {
        "nav-ws": 1.0,      # settle window after the click
        "nav-home": 1.0,
        "add-log": 1.4,     # allows the before-host 400 ms poll to fire
        "poke": 1.2,
        "refresh": 1.0,
        "detail-open": 1.0,
        "detail-close": 1.0,
    }

    sock, rest = ws_connect(args.host, args.port)

    # baseline drain: connecting must yield no frames (baseline silence)
    frames, rest = collect(sock, 0.6, rest)
    texts, pbytes, hbytes, ids = summarize(frames)
    print("[wire] %s connect: frames=%d payload=%d html=%d ids=%s" % (args.label, texts, pbytes, hbytes, ",".join(ids)))

    for step in args.steps.split(","):
        step = step.strip()
        if not step:
            continue
        if step == "idle":
            frames, rest = collect(sock, 2.5, rest)
            texts, pbytes, hbytes, ids = summarize(frames)
            print("[wire] %s idle-2.5s: frames=%d payload=%d html=%d ids=%s" % (args.label, texts, pbytes, hbytes, ",".join(ids)))
            continue
        window = event_steps.get(step)
        if window is None:
            print("[wire] %s %s: SKIP unknown step" % (args.label, step))
            continue
        msg = json.dumps({"type": "event", "component": step, "event": "click", "data": {"targetId": step}})
        send_text(sock, msg)
        frames, rest = collect(sock, window, rest)
        texts, pbytes, hbytes, ids = summarize(frames)
        print("[wire] %s %s: frames=%d payload=%d html=%d ids=%s" % (args.label, step, texts, pbytes, hbytes, ",".join(ids)))

    sock.close()


if __name__ == "__main__":
    main()

## appendix C — raw output (as emitted)

`/tmp/dx2-consumer-prototype/out/measure-raw.txt`:


================================================================================
date:      2026-10-05T12:36:26Z
host:      Darwin arm64
swift:     swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
python3:   Python 3.9.6
prototype: /tmp/dx2-consumer-prototype
framework: /tmp/continuum-fleet/lane-d

================================================================================
framework head: c24857a6aeca0d40112635263dc365a8ffb53173
framework branch: task/m-ladder
framework HEAD == c24857a (i1): OK
prototype vendor symlink: /tmp/continuum-fleet/lane-d
ports 9380-9382 cleared

================================================================================
$ swift build --package-path /tmp/dx2-consumer-prototype
Building for debugging...
[Computing dependencies]
[Using on-disk description]
[1 / 1]
[1 / 89] SwiftParserDiagnostics
Build complete! (1.21 sec)
bin path:  /private/tmp/dx2-consumer-prototype/.build/out/Products/Debug

================================================================================
-- before: the consumer tool's emitted sheet (ProtoAssetPlugin) --
  /tmp/dx2-consumer-prototype/.build/plugins/outputs/dx2-consumer-prototype/ProtoBefore/destination/ProtoAssetPlugin/ProtoSheetAssets.swift
  bytes: 4217
-- after: the framework plugin's emitted sheet (WebUIThemePlugin) --
  /tmp/dx2-consumer-prototype/.build/plugins/outputs/dx2-consumer-prototype/ProtoAfter/destination/WebUIThemePlugin/ProtoAfterCatalogSheet.swift
  bytes: 4817
-- tool receipts (repeat build; the first run's receipts are in section 1) --
$ swift build --package-path /tmp/dx2-consumer-prototype
Building for debugging...
[Computing dependencies]
[Using on-disk description]
[1 / 87] NIO
Build complete! (1.01 sec)

================================================================================
-- headline: the contract's nine-class built-in reference --
$ /tmp/continuum-fleet/lane-d/.build/out/Products/Debug/WebUIContinuumTool shadow --sources /tmp/dx2-consumer-prototype/Sources/ProtoTheme --demo
warning: class 'chip' shadows design-system class 'chip' (owned by WebUIChip) at ChromeSheet.swift
warning: class 'inline-edit' shadows design-system class 'inline-edit' (owned by WebUIInlineEdit) at ChromeSheet.swift
warning: class 'kv' shadows design-system class 'kv' (owned by design-system.css) at ChromeSheet.swift
warning: class 'log-line' shadows design-system class 'log-line' (owned by design-system.css) at ChromeSheet.swift
warning: class 'md' shadows design-system class 'md' (owned by WebUIDesignSystemCore.markdownBody) at ChromeSheet.swift
warning: class 'modal-overlay' shadows design-system class 'modal-overlay' (owned by WebUIModal) at ChromeSheet.swift
warning: class 'swatch' shadows design-system class 'swatch' (owned by design-system.css) at ChromeSheet.swift
warning: class 'toast' shadows design-system class 'toast' (owned by WebUIToast) at ChromeSheet.swift
warning: class 'tool-btn' shadows design-system class 'tool-btn' (owned by design-system.css) at ChromeSheet.swift
[WebUIContinuumTool] shadow: 9 collision(s) against the DS class union
$ /tmp/continuum-fleet/lane-d/.build/out/Products/Debug/WebUIContinuumTool shadow --sources /tmp/dx2-consumer-prototype/Sources/ProtoAfter --demo
[WebUIContinuumTool] shadow: 0 collision(s) against the DS class union
-- deep: against the real design-system sheet union --
$ /tmp/continuum-fleet/lane-d/.build/out/Products/Debug/WebUIContinuumTool shadow --sources /tmp/dx2-consumer-prototype/Sources/ProtoTheme --ds-css /tmp/continuum-fleet/lane-d/designer/assets/design-system.css --demo
warning: class 'chip' shadows design-system class 'chip' (owned by WebUIChip) at ChromeSheet.swift
warning: class 'chip--primary' shadows design-system class 'chip--primary' (owned by design-system.css) at ChromeSheet.swift
warning: class 'inline-edit' shadows design-system class 'inline-edit' (owned by WebUIInlineEdit) at ChromeSheet.swift
warning: class 'kv' shadows design-system class 'kv' (owned by design-system.css) at ChromeSheet.swift
warning: class 'log-line' shadows design-system class 'log-line' (owned by design-system.css) at ChromeSheet.swift
warning: class 'md' shadows design-system class 'md' (owned by WebUIDesignSystemCore.markdownBody) at ChromeSheet.swift
warning: class 'modal-overlay' shadows design-system class 'modal-overlay' (owned by WebUIModal) at ChromeSheet.swift
warning: class 'swatch' shadows design-system class 'swatch' (owned by design-system.css) at ChromeSheet.swift
warning: class 'toast' shadows design-system class 'toast' (owned by WebUIToast) at ChromeSheet.swift
warning: class 'tool-btn' shadows design-system class 'tool-btn' (owned by design-system.css) at ChromeSheet.swift
[WebUIContinuumTool] shadow: 10 collision(s) against the DS class union
$ /tmp/continuum-fleet/lane-d/.build/out/Products/Debug/WebUIContinuumTool shadow --sources /tmp/dx2-consumer-prototype/Sources/ProtoAfter --ds-css /tmp/continuum-fleet/lane-d/designer/assets/design-system.css --demo
[WebUIContinuumTool] shadow: 0 collision(s) against the DS class union
-- tree-wide before (markup included) --
$ /tmp/continuum-fleet/lane-d/.build/out/Products/Debug/WebUIContinuumTool shadow --sources /tmp/dx2-consumer-prototype/Sources/ProtoBefore --demo
warning: class 'chip' shadows design-system class 'chip' (owned by WebUIChip) at Content.swift
warning: class 'kv' shadows design-system class 'kv' (owned by design-system.css) at Content.swift
warning: class 'log-line' shadows design-system class 'log-line' (owned by design-system.css) at Content.swift
warning: class 'md' shadows design-system class 'md' (owned by WebUIDesignSystemCore.markdownBody) at Content.swift
warning: class 'swatch' shadows design-system class 'swatch' (owned by design-system.css) at Content.swift
[WebUIContinuumTool] shadow: 5 collision(s) against the DS class union
$ /tmp/continuum-fleet/lane-d/.build/out/Products/Debug/WebUIContinuumTool shadow --sources /tmp/dx2-consumer-prototype/Sources/ProtoBefore --ds-css /tmp/continuum-fleet/lane-d/designer/assets/design-system.css --demo
warning: class 'chip' shadows design-system class 'chip' (owned by WebUIChip) at Content.swift
warning: class 'kv' shadows design-system class 'kv' (owned by design-system.css) at Content.swift
warning: class 'log-line' shadows design-system class 'log-line' (owned by design-system.css) at Content.swift
warning: class 'md' shadows design-system class 'md' (owned by WebUIDesignSystemCore.markdownBody) at Content.swift
warning: class 'swatch' shadows design-system class 'swatch' (owned by design-system.css) at Content.swift
[WebUIContinuumTool] shadow: 5 collision(s) against the DS class union

================================================================================
wiring.before  = 8 (Helpers btn) + 103 (Controllers) = 111 lines
wiring.after   = 89 (Controls) = 89 lines
wiring.delta   = 22 lines deleted
push.before    = 79 (PushLayer) + 15 (main) = 94 lines
push.after     = 25 (Regions) + 1 (main) = 26 lines
push.delta     = 68 lines deleted
theme.before   = 36 (ProtoAssetTool) + 34 (ProtoAssetPlugin) + 15 (Package block) = 85 lines
theme.after    = 3 (Package attach) = 3 lines
theme.delta    = 82 lines deleted
per-control rate (8 controls): before=13.9 lines/control · after=11.1 lines/control
per-driver rate (3 pollers → 3 regions): before=31.3 lines/driver · after=8.7 lines/driver

================================================================================
before tree (/tmp/dx2-consumer-prototype/Sources/ProtoBefore):
  "nav-ws": files=2 occurrences=3
  "add-log": files=2 occurrences=3
  "poke": files=2 occurrences=3
  "detail-close": files=2 occurrences=3
  "detail-open": files=2 occurrences=3
after tree (/tmp/dx2-consumer-prototype/Sources/ProtoAfter):
  "nav-ws": files=1 occurrences=1
  "add-log": files=1 occurrences=1
  "poke": files=1 occurrences=1
  "detail-close": files=1 occurrences=1
  "detail-open": files=1 occurrences=1
region ids:
  before "logbox": files=2 occurrences=3
  after  "logbox": files=2 occurrences=2
  before "status": files=1 occurrences=2
  after  "status": files=1 occurrences=1

================================================================================
-- before @ :9380 (deduper ON) --
  [proto-before up]
$ python3 /tmp/dx2-consumer-prototype/scripts/ws_probe.py --port 9380 --label before
[wire] before connect: frames=1 payload=108 html=47 ids=status
[wire] before nav-ws: frames=1 payload=92142 html=88886 ids=app
[wire] before nav-home: frames=1 payload=99099 html=95363 ids=app
[wire] before add-log: frames=2 payload=58352 html=57028 ids=logbox,status
[wire] before poke: frames=0 payload=0 html=0 ids=
[wire] before refresh: frames=1 payload=17378 html=16107 ids=main
[wire] before detail-open: frames=1 payload=348 html=270 ids=detail-widget
[wire] before detail-close: frames=1 payload=212 html=138 ids=detail-widget
[wire] before idle-2.5s: frames=0 payload=0 html=0 ids=
  [http] before /ui/theme.css: 200 bytes=1541
-- before @ :9382 (--no-dedupe; the counterfactual) --
  [proto-before --no-dedupe up]
$ python3 /tmp/dx2-consumer-prototype/scripts/ws_probe.py --port 9382 --label before-nodedupe
[wire] before-nodedupe connect: frames=0 payload=0 html=0 ids=
[wire] before-nodedupe nav-ws: frames=2 payload=92250 html=88933 ids=status,app
[wire] before-nodedupe nav-home: frames=2 payload=99207 html=95410 ids=app,status
[wire] before-nodedupe add-log: frames=4 payload=58568 html=57122 ids=status,logbox,status,status
[wire] before-nodedupe poke: frames=3 payload=116596 html=114009 ids=logbox,logbox,status
[wire] before-nodedupe refresh: frames=2 payload=17486 html=16154 ids=main,status
[wire] before-nodedupe detail-open: frames=2 payload=456 html=317 ids=detail-widget,status
[wire] before-nodedupe detail-close: frames=2 payload=320 html=185 ids=detail-widget,status
[wire] before-nodedupe idle-2.5s: frames=2 payload=216 html=94 ids=status,status
-- after @ :9381 (regions) --
  [proto-after up]
$ python3 /tmp/dx2-consumer-prototype/scripts/ws_probe.py --port 9381 --label after
[wire] after connect: frames=0 payload=0 html=0 ids=
[wire] after nav-ws: frames=1 payload=11087 html=10296 ids=main
[wire] after nav-home: frames=1 payload=18484 html=17213 ids=main
[wire] after add-log: frames=2 payload=60159 html=58835 ids=status,logbox
[wire] after poke: frames=0 payload=0 html=0 ids=
[wire] after refresh: frames=1 payload=18484 html=17213 ids=main
[wire] after detail-open: frames=1 payload=366 html=292 ids=detail-open
[wire] after detail-close: frames=1 payload=192 html=121 ids=detail-close
[wire] after idle-2.5s: frames=0 payload=0 html=0 ids=
  [http] after /ui/theme.css: 200 bytes=2103

================================================================================
raw output: /tmp/dx2-consumer-prototype/out/measure-raw.txt
host logs: /tmp/dx2-consumer-prototype/out/{before,before-nodedupe,after}-run.log


## appendix D — host logs (as emitted)

--- out/before-run.log ---
2026-10-05T07:36:32-0500 info webui.server: [WebUIServer] WebUIServer serving / on http://127.0.0.1:9380 (ws://127.0.0.1:9380/ws)

--- out/before-nodedupe-run.log ---
2026-10-05T07:36:44-0500 info webui.server: [WebUIServer] WebUIServer serving / on http://127.0.0.1:9382 (ws://127.0.0.1:9382/ws)

--- out/after-run.log ---
2026-10-05T07:36:55-0500 info webui.server: [WebUIServer] WebUIServer serving / on http://127.0.0.1:9381 (ws://127.0.0.1:9381/ws)
2026-10-05T07:36:55-0500 warning webui.regions: [WebUIServer] live region 'main' grew the handler map across a render (0 → 1); stable ids only


---

## sidecar §3.8 report

```
lane: M · branch head sha: this note's commit (see the lane's push log; parent base c24857a)
       · base sha: c24857a
prototype: /tmp/dx2-consumer-prototype · client: Swift (hosts) + Python stdlib (wire probe)
tasks:
  wiring     done (Δ −22; touchpoints 3→1 per control)     (this commit)
  push       done (Δ −68; nav 92,142 → 11,087 B)           (this commit)
  theme      done (Δ −82; both sheets emitted + served)    (this commit)
  collisions done (9 → 0 headline; 10 → 0 deep)            (this commit)
green:
  bash scripts/measure.sh -> BUILD OK; shadow 9→0; wiring 111→89; push 94→26; theme 85→3;
  wire: nav-ws 92,142→11,087 B; poke 0/116,596/0 B; idle 0/216/0 B; theme.css 200 (1541/2103 B)
assumptions:
  1) the port is a cut (8 controls/3 drivers/2 themes); per-unit rates measured, full-arc totals
     cited from the plan inventory (spot-checked read-only).
  2) bytes = raw WS payloads + fragment html lengths, emitted by the probe.
  3) run via a disclosed audit-test adapter (terminal backend outage); script unchanged.
did-not-shrink:
  · item 5's 2,810-line chrome conversion — follow-on (d-w), proven on one family only.
  · handler bodies / domain logic — the seam deletes plumbing, not behavior.
  · page content bytes — same content both shapes (after's class renames: +~1.8 KB on logbox).
  · the 9 classes' declarations — moved to typed rules; 9→0 is a namespace fact.
  · framework-side lines the consumer no longer writes — real, and out of this lane's scope.
next-slice: the consumer transplant (d-j) scoped by this ladder — port one REAL arc module at
  full size and re-run it; then d-w for the chrome sheet.
```