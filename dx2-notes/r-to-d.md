# r → D — the biting live-data semantics (for the substitution guide)

lane R landed (DX-13 + DX-16). consumer-stated semantics the guide must carry:

1. **baseline silence** — `start()` renders every region's baseline eagerly and pushes
   **nothing**; a push happens only on a real change.
2. **byte minimality** — an unchanged render pushes **zero** frames; a changed one pushes
   ≤ its rendered html + 512 B. the framework byte-compares; the consumer never diffs.
3. **render contract** — `render()` runs *inside the render context* (a control it emits
   self-registers) and returns `String?`; `nil` = nothing to push. **stable ids only** —
   a minted id (no DOM id) grows the router's handler map; the registry warns
   (`live region '<id>' grew the handler map across a render`).
4. **state binding** — `LiveRegion.source` (defaulted `nil`) is the registry's
   subscription hook; `StateLiveRegion` returns its state; the registry subscribes
   non-nil sources at start, **before** baselines, and cancels them at stop
   (`LiveSubscription.cancel()` is idempotent and suppresses future delivery). a custom
   actor's `subscribe` witness **must be `nonisolated`** (a sync hop onto a busy actor
   can block `start()`).
5. **notify-after-unlock** — `LiveBox` (and `LiveNotifier`) notify strictly **after** the
   lock is released; a render closure must snapshot the value **once**, before any `await`.
6. **currentHTML best-effort** — `currentHTML(id)` is the last committed render at the
   instant of the call — a host-scoped baseline, **not** a per-client snapshot (drift
   windows exist).
7. **invalidations** — `invalidate(id)` / `invalidateAll()` mark dirty + wake; a region
   woken by a **dispatch's** `RegionInvalidations` never pushes before the dispatch frame
   (two-push ordering).
8. **lifecycle** — pumps stop with `stop()`; zero frames after stop; a per-start stop flag
   bounds the worker's wait by ≤ 1 cadence.
9. **overwrite-wins** — re-rendering a stable id re-registers (last-render-wins); it never
   grows the map.

`regions:` is a **defaulted init parameter** (`WebUILiveRegions? = nil`) on both
`WebUIServer` inits; `nil` = zero new work.