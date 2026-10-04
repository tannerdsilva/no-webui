# lane D → lane B: W2 handoffs (task/d-surface2) — the adapter type-name pin, the DX-11a byte exception, the measured-row dependency, and the scan's duplicate-name trap

## 1. the generated island adapter TYPE NAME — pin this string in BOTH suites

`@HotView("<name>")` on `struct <Type>` generates:

- `extension <Type>: ContinuumServerPath { struct <Type>Island: ContinuumIsland { ... } }`
  — the island adapter is a NESTED struct named **`<Type>Island`**, qualified
  **`<Type>.<Type>Island`** (the peer-emitted `@_expose(wasm, "<name>_encode")`
  shims reference `\(Type).\(Type)Island._continuumEncode()`).
- your scaffold (`continuum --add-island <Name>`) generates the 3-line main
  that binds it: the shim MUST name **`IslandRuntime<<Name>Island>.run()`** —
  the string `IslandRuntime<\(Name)Island>.run()` (the in-tree precedent is
  `templates/app/Sources/feed/main.swift`: `IslandRuntime<FeedIsland>.run()`).
- **caveat (recorded, not fixable by D today):** the macro-generated adapter
  conforms to `ContinuumIsland` ONLY — `IslandRuntime<I>` requires `I:
  IslandRuntimeSurface` (the decodeEvent/regionHTML/stateToJSON/stateFromJSON
  hooks are author-supplied; the acceptance feed is hand-written for exactly
  this reason). `IslandRuntime<<Name>Island>.run()` therefore type-checks only
  when the AUTHOR also writes the four hooks + `State: IslandEmptyState` (the
  template feed shows the canonical shape). D's emission keeps the adapter
  `ContinuumIsland`-only so name-only `@HotView` stays additive (I5).

## 2. the DX-11a byte-identity exception (I1 register, for dx-content-pin)

WebUITable INTERACTIVE rows gain `id="{id}-r{i}"` + `data-key="{rowId}"`
(committed `c2f0d27`). reference-page impact:

- **smoke page**: `interactive-table` is WIRED (typed handlers) → its row tags
  change → **the smoke page's served bytes change**. record the exception at
  the next dx-content-pin run. the interactive-count pins (25
  `data-component-id`) are UNCHANGED (rows carry no routing attrs); the
  control ids (`-sort-{i}` / `-select-all` / `-select-{rowId}` /
  `-expand-{rowId}`) are unchanged.
- **showcase / blocks**: no wired table → byte-identical. display-only tables
  (no typed handlers) stay byte-identical BY DESIGN (the wired gate).

## 3. the macro `budget:` tightening diagnostic — your measured-row exposure

committed `4e9e29e`: imports-without-budget auto-defaults (deleted
`missingBudgetMessage`), and `budget:` is tightening-only with a POSITIVE
LITERAL pin requirement (a declared `maxBytes: 0` is the auto spelling —
refused). **the tighter-than-measured COMPARISON needs your `islands[]`
measured rows (b-docs:571-573: `maxBytes/raw/gz/sha` per island) — not
visible in this tree.** when they land (DX-3 W2), D's macro wants a
compile-time auto-pin to compare a declared pin against (declared < measured
→ the error); until then the build-side enforce (BudgetDriftTests +
the plugin's per-island row) holds. please surface the measured pin where a
macro consumer can see it (suggest: also emit a generated
`static let continuumMeasuredBudget`-style constant beside the manifest row —
name/format is yours; D adapts).

## 4. the registry scan's duplicate-name trap (tiny, yours)

D ships the strict `@HotView("<name>")` marker form (ASCII single token,
committed `04aa48c`) and macro-side duplicate/collision diagnostics. the
CROSS-FILE duplicate still silently dedupes in your
`WebUIContinuumTool.islandPins` (`!pins.contains { $0.name == name }` drops
the second declaration) and in the capability lint — please make a duplicate
island name a scan-time BUILD ERROR with a fix hint (e.g. "island \"feed\"
is declared twice — island names are unique registry keys; rename one"). the
macro cannot see other files, so this half is yours.
