# r → G — the live-region surface the demo + probes consume

lane R landed (DX-13 + DX-16) on `task/r-livedata`. this is what the demo (`Sources/WebUIExample/main.swift`)
and `g-regions.mjs` build on.

## attaching the registry

```swift
let regions = WebUILiveRegions([
    ClosureLiveRegion(id: "clock", cadence: .seconds(1)) { "<span id=\"clock\">…</span>" },
    MyStructRegion(...),                                   // a custom LiveRegion struct
    StateLiveRegion(id: "count", state: box) { box in      // a LiveBox-backed region
        let v = box.value                                  // snapshot once, before any await
        return "<span id=\"count\">\(v)</span>"
    },
    StateLiveRegion(id: "feed", state: actorState) { st in // a custom LiveState actor
        let v = await st.snapshot()
        return "<span id=\"feed\">\(v)</span>"
    },
])
// both WebUIServer inits: regions: WebUILiveRegions? = nil  (nil = zero new work)
let server = WebUIServer(requestRender: ..., router: router, regions: regions)
```

## what the demo must ship (appendix C step 9 conformances)

four regions driven by: a **closure default**, a **custom `LiveRegion` struct**, a
**`LiveBox`**, and a **custom `LiveState` conformance whose actor `subscribe` is
`nonisolated`**. a `RegionInvalidations` control (an `EventOutcome` returning
`RegionInvalidations([id])`) invalidates a region through the dispatch seam.

## wire facts the probes assert

- pushes ride the **existing** `update` frame + `replace` op (no new wire type, I9);
- a region push is `{"type":"update","fragments":[{"id":"<region-id>","html":"…"}]}`;
- the fragment `id` == the region's `id` == the DOM id;
- **zero frames** when the render is unchanged (I7); bytes ≤ rendered html + 512 (I8);
- **two-push ordering (d-k):** a dispatch frame is written before any region worker
  woken by that dispatch's `RegionInvalidations` pushes — the registry marks dirty in
  the seam and wakes only *after* the handler frame is on the wire.

## unknown ids

`invalidate("ghost")` is a debug no-op (never a crash). `currentHTML(id)` is a
best-effort baseline (nil before start).