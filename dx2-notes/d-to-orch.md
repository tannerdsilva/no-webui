# d → orch — lane D close (MACRO_DX feature E)

_branch: `task/d-adopt` · base `3230deb` (origin/dev-macro) · lane ports 9410–9419._

## what landed

1. **the macro variant in the demo** (`Sources/WebUIExample/main.swift`):
   `@LiveRegions struct MacroDemoRegions` carrying a `@LiveRegion` struct with a
   `@RegionState` source and a `@LiveState` actor, mirroring `DemoStructRegion` /
   `DemoFeedState` one-for-one, plus the closure-default and `StateLiveRegion`
   twins. the hand-written control group (`DemoRegions`) is byte-unchanged; the
   served registry is ONE `WebUILiveRegions(regions.regionList +
   macroRegions.regionList)` so both variants render on the same page and are
   driven in the same run. ids g-mreg-a..d; macro controls read from the served
   markup.
2. **the twins** (`Tests/WebUITests/MacroParityTests.swift`): hand and macro
   spellings driven through the SAME registry seam (start/render/push), asserted
   byte-equal (ids/html/order + wire bytes via deterministic encoder), both
   conform, I7 quiet on both. green.
3. **the probe** (`designer/probes/g-regions.mjs`): macro siblings of all four
   drivers + d-k + racing, same push/quiet expectations, ids read from the served
   markup. 20 passed / 0 failed, deterministic across runs.

## gates (lane ports)

```
swift build                                    → Build complete
swift test --filter MacroParityTests          → 2/2 passed
swift test                                    → full suite green (nothing failed)
node designer/probes/g-regions.mjs --port 9411 --binary .build/out/Products/Debug/WebUIExample
                                              → 20 passed, 0 failed — G-REGIONS GREEN PASS (x2 deterministic)
```

## findings to record

- **pre-existing server accept quirk (not lane D's):** a bare connection that
  immediately follows a closed one is transiently reset (verified on the pristine
  base `3230deb`; raw TCP upgrades succeed 3/3, so it is the second node
  WebSocket client connection, not the server's handshake). the i0 probe masked
  it because its second socket was the I7 idle check, which asserts zero frames
  and passes vacuously on an errored socket. g-regions now retries a failed
  socket (matching the acceptance's retry-on-no-open). x-report for lane G: the
  acceptance's own sequential sockets may hit the same quirk — reuse a retry.
- the frozen `WebUILiveRegions` takes one registry; the demo composes via the
  additive `regionList` seam (hand `registry` is untouched, so 9b's
  `WebUILiveRegions([` grep still matches).
- `MacroParityTests` lives in `WebUITests` (WebUIExample is an executable and
  cannot be imported) — the twins are declared in the test one-for-one, exactly
  as the compiled runtime fixtures do in `WebUIServerMacroTests`.
