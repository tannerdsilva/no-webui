# WASM Subset Audit — swift-6.4.0 wasm SDK

_date: 2026-09-15 · companion to `WASM_TRAJECTORY.md` (W§4 Phase 0) ·
method: real builds with the official SDKs, recorded as built._

## toolchain

- host: macOS 27.0, arm64; host toolchain = official **swift-6.4-RELEASE**
  installed via swiftly (`~/.swiftly/bin`, `--no-modify-profile`), replacing
  the Xcode 27 frontend which cannot read the SDK's prebuilt modules
  ("compiled module was created by a different version of the compiler ''")
  and lacks `swift-autolink-extract`.
- SDKs: `swift-6.4.0-RELEASE_wasm` and `swift-6.4.0-RELEASE_wasm-embedded`,
  installed via `swift sdk install` (checksum-verified).
- run: `swift run --swift-sdk <id>` executes via WasmKit.

## audit table (built, not guessed)

audit target: `WebUICore` (the wasm-clean render core, split 2026-09-15).

| item | full `_wasm` | embedded `_wasm-embedded` |
|---|---|---|
| String-only render core | survives — Build complete (61.75s) | gate blocked by swift-log (below); own subset unverified until the LogFunnel swap (P6-T1) |
| `JSONValue` / `[UInt8]` codec | survives | same gate |
| `Synchronization.Mutex` | survives | same gate |
| `@TaskLocal` (RenderContext) | **survives** (compiles; runtime semantics re-verified in-page at P2-T2) | re-verified at P6-T1 |
| `_Concurrency` (`Task`, `withTaskGroup`) | survives (compiles) | same gate; re-verified at P6-T1 |
| swift-log (`Logging`) | **survives — KEEP (D3)** | **fails — D3 throw-out for the embedded tier**: `Codable`, `init(describing:)`, `init(reflecting:)`, class-typed metadata all unavailable in embedded (verified: all errors inside `.build/checkouts/swift-log`, zero in project code) |
| rawdog / crypto | **not pulled into the client** (WebUICore links only `Logging`; `RAW*` products stay in the `WebUI` server target) | n/a |

probe (independent of the package): the swift.org hello builds and runs on
both SDKs ("Hello from WASI!" via WasmKit) — toolchain verified end to end.

## D3 verdicts (resolved per tier, both pre-approved paths)

1. **`@TaskLocal` / `RenderContext`: keep.** it compiles on the full SDK, which
   satisfies D3 ("throw out only if it cannot survive for a technical reason").
   no ambient-context fallback (W§2.1.6) on the full-SDK client. re-verify in
   the browser at P2-T2 (runtime semantics) and at P6-T1 (embedded).
2. **swift-log: keep on the full-SDK client; throw out for the embedded tier.**
   the full-SDK client uses `Logger` as today. the embedded tier (P6) swaps to
   the in-package `LogFunnel` (W§2.1.16) — the parameter-type change lands once,
   in the embedded build only, under the accepted breaking-change policy.
3. **`_Concurrency`:** available on both SDKs per the toolchain build of the
   probe (embedded probe used `@main` + stdlib `print` only, so the full async
   surface re-verifies at P6-T1; the full SDK compiles our async handlers
   already). the sync-equivalent fallback (W§3.3) is recorded, not needed so far.

## open items

- full `WebUICore`-on-embedded compile is **not yet proven** (swift-log blocks
  the dependency build). resolving the `LogFunnel` swap at P6-T1 is the first
  embedded-tier gate.
- `@TaskLocal` runtime semantics in the browser (single-threaded) verified by
  the P2-T2 resident-router probe.
