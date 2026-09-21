# wasm native build integration — spike evaluation

_branch: `spike/wasm-native-build` · date: 2026-09-20_

## goal

external projects consume no-webui for their web UI, and enable client (wasm)
mode through the swift build system itself — package plugins + package
resources — rather than memorizing a `swift build --swift-sdk …` incantation.

## what was built (on the spike branch)

| piece | kind | what it does |
|---|---|---|
| `WebUIClientRuntime`, `WebUICore`, `WebUIDesignSystemCore` | **library products** (new) | consumers can now depend on the wasm-clean render core directly — before, only the bundled `WebUI` product reached consumers |
| `WebUIClient` | **executable product** (new) | consumers can build their own client product (or the reference client) from the dependency |
| `WebUIWasmPlugin` | **build-tool plugin** (applied to `WebUI`) | during every host build, finds the prebuilt wasm artifact, validates wasm magic/version, computes sha-256, emits `Wasm+Generated.swift` (`WebUIWasmInfo`); emits an absent carrier when no artifact exists |
| `WebUIWasmTool` | executable tool | the plugin's engine: `--wasm-input` validates + hashes (RAW_sha256), `--missing` writes the absent carrier, corrupt/missing artifacts exit non-zero |
| `WebUIWasmClientPlugin` | **command plugin** (verb `wasm-client`) | cross-builds a named client product with the wasm sdk into an isolated `.build/wasm-client-scratch`, copies the artifact to the canonical `.build/out/Products/Release-webassembly-wasm32/<product>.wasm` |
| `WebUIBoot.wasmAvailable` / `wasmSHA256` / `wasmProductURL(productName:)` | host surface | serving seam reads the build-time carrier; product-name overload resolves consumer artifacts under their own name |

## empirically settled (the load-bearing facts)

1. **a command plugin CAN run the wasm cross-build** — with `--disable-sandbox`
   and an isolated scratch `--build-path` under `.build`. verified: the plugin
   makes a nested `swift build --swift-sdk …wasm` that completes, with the
   swiftly toolchain resolving correctly in the spawn context (the Xcode
   frontend would fail — the plugin uses `~/.swiftly/bin/swift` directly).
2. **building into the package's own `.build` from a plugin deadlocks** — the
   plugin invocation holds the per-package build lock ("Another instance of
   SwiftPM is already running"). the isolated scratch sub-directory is
   *required*, not a nicety.
3. **a build-tool plugin (running during host `swift build`) CANNOT run the
   cross-build** — the plugin sandbox denies the nested build's own
   `sandbox-exec` re-entry (`sandbox_apply: Operation not permitted`). it can
   only *consume* a prebuilt artifact. (SE-0387 + the repo's two-invocation rule
   independently predicted this.)
4. **command plugins are NOT applied via a target's `plugins:` array** — doing
   so made the consumer's wasm cross-build fail ("declared with the buildTool
   capability"). the correct consumer wiring is: the plugin is a **product** of
   no-webui, the consumer just has the dependency, and invokes
   `swift package --disable-sandbox plugin wasm-client` by verb name.

## verification trail (all real, all observed)

- host `swift build` green with `WebUIWasmPlugin` applied → `WebUIWasmTool:
  validated + hashed … (64709348 bytes, sha bf158c…)`.
- generated `WebUIWasmInfo.sha256` == `shasum -a 256` of the artifact
  (byte-identical: `bf158c391b4d01f64c9da21742bc187a05c28d01fc157400415f6833601caa82`).
- `swift package --disable-sandbox plugin wasm-client` in-repo: cross-built a
  fresh client (64,709,348 bytes — a real rebuild), copied to the canonical
  path; a subsequent plain `swift build` re-validated + re-hashed it
  (`b4b111d3d706…`) with no extra steps.
- **consumer package** (`/tmp/webui-consumer-spike`, path-depends on no-webui):
  - `swift build --product ConsumerServer` green — `WebUI`/`WebUIClientRuntime`
    products resolve, the wasm carrier flows into the consumer build.
  - `swift package --disable-sandbox plugin wasm-client --product ConsumerClient`
    (a plugin shipped by the dependency, invoked by verb) cross-built the
    consumer's OWN client → `.build/out/Products/Release-webassembly-wasm32/ConsumerClient.wasm`
    (64,620,601 bytes).
  - the consumer server binary reads `WebUIBoot.wasmAvailable=true` and the
    build-time sha.
- tests: `WebUIWasmToolTests` (4, subprocess, synthetic wasm) + `WasmCarrierTests`
  (5, carrier ⇄ artifact contract) — all green; full `swift test` re-running.

## friction found

1. **`--disable-sandbox` is mandatory for the command plugin** (the nested
   `sandbox-exec` cannot re-enter the plugin sandbox). this matches the
   existing `serve`/`smoke`/`fullstack-smoke` convention — documented, not a
   regression, but consumers must learn it.
2. **resources are NOT the right tool for the 55 MB artifact.** the trajectory's
   §2.2.4 `WebUIAssets.wasm: [UInt8]` plan would be a ~190 MB (hex) / ~86 MB
   (base64) swift literal at this artifact size — a compile-time and memory
   disaster. instead the plugin emits a **metadata carrier** (presence + sha +
   byte count) and the host serves the artifact by path/hash at runtime — which
   is exactly what `readClientWasmArtifact` + `WebUIBoot.wasmHash(of:)` already
   did in the reference server. also, wasm-bundle resource accessors hit SPM
   issue #7120 when a plugin generates the resource.
3. **size**: the 64.7 MB raw artifact is ~58% full-stdlib data tables, 26%
   stdlib code, 15% strippable custom sections (name table + DWARF). the
   `wasm-client` verb now strips custom sections by default (64.7 → 55.1 MB,
   import/export surface verified byte-identical), and the serving docs state
   brotli/gzip (`~12 MB` over the wire, immutable-cached). the embedded-Swift
   diet (P6, kB-scale) is a framework change blocked today by swift-log
   flowing into `WebUICore` (`init(reflecting:)`/`Codable`/`description` are
   unavailable under embedded) — tracked separately, not part of build wiring.
4. **the build-tool plugin hardcodes `WebUIClient.wasm`** for in-repo builds; a
   consumer's *own* artifact is name-agnostic — `WebUIWasmPlugin` emits the
   absent carrier under a consumer build (no webui checkout remnant), and the
   consumer serves their artifact via `WebUIBoot.wasmProductURL(productName:)`
   at runtime. that split is correct, but the build-time is *framework-own* and
   runtime is *consumer-own* — worth stating loudly in docs.
4. **every host build that builds `WebUI` now reads the artifact** (a 64 MB
   input file). harmless on a warm tree (gitignored, plugin re-runs only when
   the artifact changes via input-file tracking), but a cold CI image without
   the artifact gets the absent carrier (soft), and without the wasm sdk the
   gates skip (existing behavior).

## the final design (recommendation)

**the "one extra step" stays one, but it is now a discoverable verb:**
`swift package --disable-sandbox plugin wasm-client`. everything else is native
`swift build`:

```
swift package --disable-sandbox plugin wasm-client [--product TheirClient]   # once per rebuild
swift build                                                                    # host — validates + hashes + serves
swift run TheirServer
```

split of responsibilities (the part that must survive into the real design):

| concern | mechanism |
|---|---|
| produce the artifact | `WebUIWasmClientPlugin` command plugin (scratch sub-dir + swiftly shim; cannot be a build-tool plugin — sandbox) |
| validate + hash at build time | `WebUIWasmPlugin` build-tool plugin → `WebUIWasmInfo` carrier (magic/version/sha, absent-carrier soft path) |
| serve the artifact | host reads bytes by path (`WebUIBoot.wasmProductURL(productName:)`) + hashes at startup if no carrier; client-mode CSP/scripts unchanged |
| consumer reachability | `WebUIClientRuntime`/`WebUICore`/`WebUIDesignSystemCore`/`WebUIClient` as products |
| cache-busting | the carrier sha feeds the content-addressed `/__assets/app.<sha>.wasm` immutable route — now known at build time |

what is deliberately NOT done (and why):
- no `.wasm` byte-embedding / bundle resource (64 MB literal; #7120) — metadata
  carrier + path/serving instead.
- no attempt to hide the wasm sdk install — it is an inherent cross-triple
  requirement (SE-0387), surfaced via the swiftly-shim invocation.

## forged design — the four decisions, resolved

1. **`wasm-client` stays explicit `--product`** (default `WebUIClient`). no
   `*Client`-scanning: a consumer package can own several `*Client`-named
   products (per-screen clients, A/B variants), and guessing which one to
   build is magic. the house rule is one crisp explicit choice. in-repo, the
   default recovers today's `swift build … --product WebUIClient` verb;
   consumers pass `--product TheirClient`. (documented in the plugin
   description + this doc.)
2. **the `WebUIWasmInfo` carrier stays server-side in `WebUI`.** it exists to
   drive the serving seam (`WebUIBoot` content-addressed route); the
   wasm-clean client core (`WebUIDesignSystemCore`) has no serving concern —
   a client doesn't need to know the sha of its own module, and routing the
   build-tool plugin into the wasm-clean target would drag host `.build`
   layout semantics into the wasm graph. consumers building a server against
   `WebUI` already receive the carrier through the existing product boundary.
3. **gate posture: soft default + `WEBUI_REQUIRE_WASM=1` hard-fail opt-in.**
   the default (artifact absent → `present=false` carrier → host builds fine,
   wasm route 404s) keeps a fresh clone without the wasm sdk fully green —
   the same tolerance `WasmIntegrityTests` uses. consumers who ship
   client-mode pages set `WEBUI_REQUIRE_WASM=1` (read at plugin-execution
   time, verified 2026-09 that SwiftPM passes it to build-tool plugins) and
   an absent artifact becomes a build failure with the exact fix command —
   never a silent 404 in production.
4. **scratch is the incremental cache — no `rm -rf`.** `.build/wasm-client-
   scratch` is gitignored with the rest of `.build`; the plugin *overwrites*
   the destination artifact on every successful run (`copyFile` removes the
   old file first), so a stale scratch can never be served. deleting it would
   only throw away the cross-build cache (the cheap warm-rebuild win surfaced
   in the probe: 0.38 s incremental vs full cold build).

## bloopers file (for the swarm)

- `plugins:` on a consumer target = build-tool semantics. command plugins are
  invoked by verb, not applied. this cost one full wasm build to discover.
- `Skip(...)` is not a Swift Testing API on this runtime; the repo's
  `Issue.record(severity: .warning)` + early-return is the house pattern.
- build-tool plugin sandbox output is verbose and `-v`-heavy; the fast-fail
  (`Build failed` with no detail) needs the tool's own stdout forwarding to
  diagnose — the final plugin should tee tool output into the display name.
