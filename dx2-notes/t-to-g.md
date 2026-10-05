# t-to-g — the theme pipeline handoff (lane T → lane G)

_lane T · 2026-10-04 · branch `task/t-themes` · see also `t-theme-spike-verdict.md`_

## 1. which mechanism ran: (a) — the DIRECT swiftc route, DEMOED end-to-end

the spike verdict is mechanism **(a)**: a framework **build-tool** plugin
(`WebUIThemePlugin`) driving a **direct `swiftc`** over the consumer's theme
sources. no consumer tool target exists anywhere — the consumer's whole surface
is (1) a `ThemeCatalog` in their app target, (2) the plugin attached to that
target, (3) one reference to the emitted asset. the two firsts (macro dylib
load, `.build` module/link consumption + ordering) were settled empirically in
`t-theme-spike-verdict.md`, including the two demo-discovered sharpenings
(`-Xfrontend -disable-sandbox` under the plugin-command seatbelt; leaving
`WebUIDesignSystem` OUT of the driver link closure).

## 2. what lane G needs for `g-theme.mjs` (the verdict-parametric gate)

- **consumer surface (recorded, for your demo scaffold):**
  - PKG: attach `WebUIThemePlugin` to the app target —
    `plugins: [.plugin(name: "WebUIThemePlugin", package: "no-webui")]`;
  - DECLARE: a `ThemeCatalog` (providers via `@Theme` — or the hand-written
    twin) in the attached target's sources; the plugin scans the target dir for
    a `…: ThemeCatalog` conformance and emits for it;
  - SERVE: reference the emitted `WebUIShippedAsset` conformance — named
    `<CatalogTypeName>Sheet` (e.g. `DemoCatalog` → `DemoCatalogSheet`) — via
    `WebUIAsset(DemoCatalogSheet.self, path:)` exactly like any other
    registered asset. the plugin writes it into the plugin work dir and SwiftPM
    compiles it into your target (the Assets+Generated.swift mechanism).
- **the gate, asserted (appendix C step 7, (a) half):**
  1. served page links the emitted theme url (content-addressed, `?v=<stamp>`);
  2. sheet bytes == `WebUIThemeBuild.emit` output (stamp + payload);
  3. **stamp stable across a rebuild** — run the demo server, rebuild, re-serve,
     stamp and bytes unchanged. the lane probe (`t-emission.mjs`) proves this
     on the committed fixture (`designer/probes/fixtures/t-theme-catalog/`);
  4. NO consumer tool target in the consumer's Package.swift (nothing named
     `WebUIThemeTool` in the app's own manifest — it is a framework product).
- **the twin (acceptance):** a hand-written `WebUIThemeProvider` (no `@Theme`)
  whose `theme` uses `overlaying` emits through the same path — proven in the
  t-emission fixture (`ProbeTwin`) and the unit suite. your demo can include one
  so the accept step shows the twin live.

## 3. exact URL/shape contract (what a served theme looks like)

- emitted asset conforms to `WebUIShippedAsset` (contentType `text/css; charset=utf-8`,
  `stamp` = first 12 hex of sha256(body), `body`, `gzip`).
- `ThemeSheet` (WebUIDesignSystem) computes the route: `/__assets/theme.<sha256hex>`.
  serve it via the same `WebUIAsset` registration path other assets use.
- the page links it via `WebUIDocument`'s `themeStylesheetURL` (content-addressed
  → zero theme bytes on navigation). if your demo hand-rolls, copy the
  ThemeSheet.url convention so the served url and the linked url cannot diverge.

## 4. the DX-15b policy (shadow check) — one command for your no-layer audit

the shadow check is a NEW `shadow` verb on `WebUIContinuumTool` (**additive**;
`lint`/`generate` untouched, pins intact):

```
swift run WebUIContinuumTool shadow --sources <consumer-dir> --demo
   # + --ds-css designer/assets/design-system.css --ds-sources Sources/WebUIDesignSystemCore
   #   for the real-artifact DS union; --fail to gate (exit 1 on any collision)
```

- extracts exact class tokens from consumer string-literal CSS, `CSSRule("…")`
  args and `class="…"` literals; warns NAMING the owning component;
- never scans DS sources (paths under the framework tree are refused/skipped);
- the 9 shadowed DS classes (`chip`, `kv`, `toast`, `modal-overlay`, `log-line`,
  `md`, `swatch`, `inline-edit`, `tool-btn`) each fire with their owner;
- demo target ZERO: run it over your WebUIExample sources in g-theme — must
  report 0 (thread it into the no-layer audit's shadow assertion).
- probes: `node designer/probes/t-shadow.mjs` + `t-emission.mjs` (lane T) green.

## 5. notes for the merge

- `Package.swift` gained exactly the DX-15a block (5 entries): plugin product +
  plugin target + `WebUIThemeBuild` library product+target + `WebUIThemeTool`
  executable target. append-only; expect the orchestrator's `dump-package` diff
  vestige is lane-R/`regions:`-free so this block should apply cleanly.
- files I touched: `Sources/WebUIThemeBuild/`, `Sources/WebUIThemeTool/`,
  `Plugins/WebUIThemePlugin/`, `Sources/WebUIContinuumTool/` (+`ShadowCheck.swift`),
  `Tests/WebUIContinuumToolTests/ShadowCheckTests.swift`,
  `Tests/WebUIDesignSystemMacroTests/ThemeRulesProof.swift`,
  `designer/probes/t-*.mjs`, `dx2-notes/t-*.md`. nothing under
  `designer/assets/`, `Sources/WebUICore/`, `Sources/WebUIServer/`,
  `templates/`, showcase or smoke.
- the shadow `--demo` one-liner is gate-embeddable; keep lane ports your own.
