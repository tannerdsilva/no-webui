# t-theme spike verdict — mechanism (a) DEMO (live), recorded BEFORE lint work

_lane T · 2026-10-04 · branch `task/t-themes` · base `726f123`_

## verdict: mechanism (a) is ALIVE — the direct-`swiftc` driver works, both firsts PASS

the spike (a bare `swiftc` invocation over a scratch consumer theme source, against
the framework's **own on-disk `.build` products**, no SwiftPM involvement) settled
both new firsts empirically:

| first | test | result |
|---|---|---|
| **(f1) the macro dylib must load** | `swiftc -load-plugin-executable <products>/WebUIDesignSystemMacros#WebUIDesignSystemMacros -I <products> … -typecheck scratch-theme.swift` | **PASS** — the plugin executable in `.build/out/Products/Debug/` loads under direct `swiftc`; `@Theme` expands (both the flat-token form and `@Theme(base:)` overlaying compose; a nonexistent `DesignToken` case surfaced as an expansion-site compile error, proving the macro genuinely ran) |
| **(f2) `.build` module/link consumption + the emit closure** | same driver line + link: `-L <products>` + `libWebUI*.a` archives + rawdog/Logging/CRAW object files + the C modulemaps (CRAW, `__crawdog_sha256`, `__crawdog_argon2`, `__crawdog_blake2`) → run | **PASS** — the compiled driver ran `WebUIAssetBuilder.emit` (minify + prose check) and wrote a valid `WebUIShippedAsset` conformance: **521 B sheet + 146 B gzip, stamp `517f4b31b1f5`**, `import WebUICore` only |

the emitted file is exactly the `WebUIBuild.Emit` shape a consumer target compiles
against (`WebUIShippedAsset` conformance, base64 body, gzip decoder) — proven by the
precedent: SwiftPM **auto-compiles a build-tool plugin's declared `outputFiles`
(swift sources) into the attached target** (`.build/plugins/outputs/…/Assets+Generated.swift`
→ `WebUI-t.build/…/Assets+Generated.o`, same for `Continuum+Generated.swift`). so a
framework **build-tool** plugin may emit the generated theme source into
`context.pluginWorkDirectoryURL` as a declared output and the consumer's own build
compiles + links it with zero consumer tooling.

## mechanism (a) — what the pipeline will be

- `Plugins/WebUIThemePlugin/` — a framework **build-tool** plugin attached to the
  consumer's app target. it scans the target's `@Theme`-bearing sources, locates the
  `.build` products (the tool's own directory is `…/Products/Debug/`), and emits a
  `.buildCommand(tool: WebUIThemeTool, inputFiles: <theme sources>, outputFiles:
  <plugin-work>/ThemeSheet+Generated.swift)` that spawns direct `swiftc`.
- `Sources/WebUIThemeTool/` — the framework executable the build command runs:
  writes a tiny driver main (calls `WebUIThemeBuild.emit(catalog: <Catalog>.self,
  to: <url>)`), then drives the **direct two-stage `swiftc`** over the consumer's
  theme sources + driver with `-load-plugin-executable <…>/WebUIDesignSystemMacros`
  (the dylib's `@loader_path` rpath resolves its swift-syntax deps from the same
  products dir), `-I <products>`, the rawdog C modulemaps, and the link line (the
  static archives + object files, discovered by globbing the products dir).
- build ordering (the hard half of f2): the tool is a framework **product** of the
  same package, so `context.tool(named:)` forces SwiftPM to build `WebUIThemeTool` —
  whose dependency closure includes `WebUIDesignSystem` → `WebUIDesignSystemMacros`
  and the `WebUIThemeBuild`/`WebUIDesignSystemCore` libraries — **before** the plugin
  command runs. every `.build` product the driver needs (macro dylib, swiftmodules,
  archives) therefore exists, built by the normal build pass, ordered by the tool
  product dependency. plugin `inputFiles` alone cannot express target-product
  ordering; the tool product CAN and does.
- `Sources/WebUIThemeBuild/` — the new library (`WebUIThemeBuild.emit`), catalog →
  sheet → `WebUIAssetBuilder.emit` → generated asset.
- `Package.swift` — the DX-15a block, 5 entries (tool route taken): plugin **product**
  + plugin **target** + `WebUIThemeBuild` library **target** + library **product** +
  `WebUIThemeTool` executable **target** (and its own product via the executable).

## cost / what remains consumer-side

- **cost:** the pipeline ships a framework tool (~130 lines of CLI + driver
  template + link-line resolution) and the plugin; the `.build` path layout
  (`Products/Debug`, `Intermediates.noindex/GeneratedModuleMaps`) is a
  toolchain-version assumption (current-version validated by the spike), and the
  link closure follows the on-disk spelling (classic `lib<M>.a` archives OR the
  new-build-system per-module `<M>.o` whole objects — both handled) rather than
  hard-coded names, so a new framework dependency flows in without editing the
  tool.
- **consumer-side remaining (per the plan's own frame):** the consumer (1) declares
  a `ThemeCatalog` with `@Theme` — or a hand-written `WebUIThemeProvider` twin —
  (2) attaches `WebUIThemePlugin` to their app target (one `.plugin` line in their
  `Package.swift`), and (3) references the emitted `WebUIShippedAsset` conformance
  in their server (`WebUIAsset(ThemeSheet.self, path:)`) exactly as they would any
  other registered asset. **arc's 81 lines of consumer tooling are deleted** — no
  consumer executable target, no consumer command line, nothing beyond the
  one-attach one-reference surface above.

## two mechanism details discovered in the demo (f2/f1 sharpenings)

the full consumer build (a path-dependency package attaching the plugin) surfaced
two things the raw spike could not see, both now folded into the tool:

1. **nested sandbox kills the macro dylib — `-Xfrontend -disable-sandbox` fixes
   it.** a build-tool PLUGIN command runs under SwiftPM's `sandbox-exec`
   `(allow process*) (allow file-read*)` seatbelt (target compiles do not; that is
   why a plain consumer compiles `@Theme` fine). inside that seatbelt, swiftc's own
   wrapper around external macro launches re-applies a sandbox, which the kernel
   refuses (`sandbox_apply: Operation not permitted`) and the macro reports a
   malformed response. `-Xfrontend -disable-sandbox` stops the frontend from
   re-wrapping the plugin process; the dylib then runs under the command's own
   `(allow process*)` geometry. verified: with the flag, the sandboxed emission is
   **byte-identical** to the unsandboxed one (stamp `517f4b31b1f5`).
2. **`WebUIDesignSystem` must NOT be in the driver's link closure.** the consumer
   theme source imports it for the `@Theme` attribute declaration, but every symbol
   the expanded macro references lives in `WebUIDesignSystemCore`/`WebUICore`;
   linking the whole `WebUIDesignSystem` module drags `WebUI` + its embedded assets
   (`HTMLDocument`, `WebUIAssets…`) into the driver for zero reason and fails the
   link on the consumer-only build (no libWebUI.a variant present there).

end-to-end proof (executed): a scratch consumer (path-dependency on the lane clone)
with a 2-theme `@Theme` catalog attached the plugin; a plain `swift build` emitted
`DemoCatalogSheet` (`WebUIShippedAsset` conformance, 523 B sheet + 141 B gzip,
stamp `1a5e92bdf20c`) into the plugin work dir, SwiftPM compiled it into the
consumer executable, and the binary printed its stamp/bytes/gzip at runtime.
second run with the catalog touched emitted **byte-identical** output (sha256
`cfe5cafcbdb62…` on both generated files) — stamp-stable.

recorded 2026-10-04 by lane T · amended after the demo (same date) with the two
mechanism details above.
