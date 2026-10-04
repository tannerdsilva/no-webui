# lane D → lane E: `.lease` placement hints (wave 2 landed; the behaviors are yours)

## what landed (lane D owns the file)

`Sources/WebUI/ContinuumLease.swift`:

- `public enum LeaseHint: Sendable, Hashable, CaseIterable { case viewport, echo }`
- `LeaseModifier: ViewModifier` + `View.lease(_:) -> ModifiedView<Self, LeaseModifier>`
- semantics NOW: inert. `apply(to:)` returns the html untouched; `decorate` is a
  buffer pass-through. pinned byte-identical in `Tests/WebUITests/APISurfaceTests.swift`
  ("placement hints are additive and byte-identical"): no markup, no attribute,
  no ws bytes — by design; placement is a precompile decision (§1.1), and the
  wave-2 contract is "no hints = today's behavior".
- the hint survives in the TYPE (`ModifiedView.modifier.hint`), which is the
  handle a build scan or a runtime bootstrap can read.

## what's yours (engine behaviors, wave 3 / t3.3+)

- `.viewport` → windowing support (t3.3): window size from the viewport rect +
  overscan, keyed identity, scroll anchoring. the hint is currently NOT
  serialized into the page — decide with B whether the continuum scan emits it
  into the served manifest (recommended; zero byte change) or the server adapter
  emits a `data-webui-lease` attribute (byte change → needs its own pin + it is
  inside the wave-1 attr seed's `data-*` allowlist, so the engine can read it).
- `.echo` → the t1.4 echo contract (`data-webui-echo="<id>"`) is yours already.
  `.lease(.echo)` is the *declaration* side; the delivery wiring (who emits the
  attribute) is t3.4/input-parity (D+C) — do NOT read `.lease(.echo)` as
  "attribute present" today.
- neither behavior may change today's bytes until the consuming slice lands and
  the pins move deliberately.

## contact surface

- file: `Sources/WebUI/ContinuumLease.swift` — lane D owns; coordinate before editing.
- tests: `Tests/WebUITests/APISurfaceTests.swift` — additive pin only, lane D owns edits.