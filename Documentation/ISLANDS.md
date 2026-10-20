# capability islands — running your Swift in the browser

an island is **your Swift logic, compiled to a small standalone wasm module, running
client-side**. the same source also runs on the server as the region's first-render
fallback, so a page is never broken when the artifact is missing.

use an island when the work is a **pure function of client-local facts** — input
validation, formatting, measured-width layout, filtering a snapshot the page already
carries. use an ordinary component (the websocket event path) when the work needs
server state or persistence: the server stays authoritative, and a round trip is the
correct price.

this guide is the end-user contract. the machinery lives in `Sources/WebUICore/Island.swift`
(protocols + region views), `Sources/WebUIIslandWire/` (the wire contract both sides
implement), `Sources/WebUIIslandRuntime/` (the wasi entry harness), one target per
capability, and the engine's island block in `designer/assets/webui-engine.js`.

---

## 1. the two protocols

```swift
public protocol Island: Sendable {
	static var name: String { get }              // the capability grant
	static func render(_ input: String) -> String
}

public protocol ResizableIsland: Island {
	static func render(_ input: String, width: Int?) -> String
}
```

- `Island` renders once at mount. the server calls `render(input)` for the fallback;
  the wasm module calls the same function when the engine mounts the region.
- `ResizableIsland` adds the **client re-render door**: the engine re-invokes
  `render(_:width:)` on mount and whenever the region's container width changes,
  passing the measured css pixel width. server rendering passes `nil` — the width is
  a *client* fact, and your `nil` branch must render a legible default layout.

the refinement (rather than a requirement on `Island`) is deliberate: `Island` is
frozen surface, and an extension-default requirement would silently no-op through
`any Island` existentials because defaults dispatch statically.

## 2. declaring a region

```swift
IslandRegion<MyIsland>("input text")                  // static capability
ResizableIslandRegion<MyResizableIsland>("input")     // width-aware capability
```

declaring the region **is the whole wiring**. `WebUIDocument` scans the rendered body
for `data-webui-island="…"` and folds every name into the emitted
`RuntimeConfig.capabilities`, so the engine grants + lazily fetches the artifact with
no manual capability list. the region emits:

```html
<div data-webui-island="my-island"
     data-webui-island-resize="true"       <!-- resizable regions only -->
     data-webui-args='{"input":"input text"}'>…fallback markup…</div>
```

- `data-webui-island-state` is engine-owned: absent until mount, then `mounted` or
  `unmapped` (absent/failed artifact — the fallback stays).
- the args envelope is `{"input": …}`; a resizable region additionally receives
  `"width": <integer px>` from the engine at mount and on every re-render.

## 3. authoring recipe (five steps)

the reference implementation is the width probe, and this recipe matches it
line-for-line: `Sources/WebUIIslandFixtures/WidthProbeIsland.swift` (the capability
module) + `Sources/WebUIWidthProbeIsland/main.swift` (the product) + its
`Package.swift` entry.

### step 1 — your capability module (a leaf)

put the logic in its own target so both sides reach it and nothing else does.
**it must stay Foundation-free** (it builds for wasm32-wasi), and it depends only
on `WebUIIslandWire`: use `WebUISharedCore`'s `JSONValue`, `htmlEscape`, and the
render primitives — never Foundation, never another capability module.

```swift
public enum MyIsland {
	public static func render(_ input: String) -> String {
		"<span class=\"island__msg\">\(htmlEscape(input))</span>"
	}
}
```

a resizable one takes the width and renders its default layout for `nil`:

```swift
public enum MyResizableIsland {
	public static func render(_ input: String, width: Int?) -> String {
		let widthText = width.map(String.init) ?? "nil"
		return "<div data-probe-width=\"\(widthText)\">…</div>"
	}
	/// decode the engine envelope (`{"input": …, "width": …}`).
	public static func render(argsJSON: String) -> String { /* JSONValue.parse */ }
}
```

### step 2 — the product entry (~10 lines, no boilerplate)

`Sources/WebUIMyIsland/main.swift`:

```swift
import WebUIIslandRuntime

@main
struct WebUIMyIsland {
	static func main() {
		#if os(WASI)
		IslandEntry.render = { argsJSON in
			MyResizableIsland.render(argsJSON: argsJSON)
		}
		#endif
	}
}
```

`IslandEntry` (in `WebUIIslandRuntime`) owns the wasi plumbing — the input/frame buffers,
utf-8 decode, and the four standard exports (`webui_input_ptr`, `webui_frame_ptr`,
`webui_frame_len`, `webui_render_region`). your `main` runs as `_start`, which the
engine invokes before any export, so the hook is installed before the first render.
a product with an extra capability export (the validate island's `webui_validate`)
adds just that one `@_expose(wasm, …)` function.

### step 3 — the manifest

```swift
.target(name: "MyCapability", dependencies: ["WebUIIslandWire"]),
.executableTarget(
	name: "WebUIMyIsland",
	dependencies: ["WebUIIslandRuntime", "MyCapability"]
),
```

### step 4 — build the artifact

```bash
swift package --disable-sandbox plugin wasm-island --product WebUIMyIsland
# -> .build/out/Products/Release-webassembly-wasm32/WebUIMyIsland.wasm
```

the verb cross-builds with the wasm SDK in an isolated scratch root, strips custom
sections, and copies the artifact into place. `--no-strip` keeps devtools stack traces.
on a fresh clone this is the step the browser gates tell you to run.

### step 5 — serve it

**the route is a wire contract**: the engine fetches `/__assets/webui-<name>.wasm`
where `<name>` is the value of `Island.name`. serve the artifact bytes as
`application/wasm` and let an absent artifact 404 — that 404 *is* the degrade path.
`Sources/WebUISmokeTest/main.swift` is the worked example (the
`/__assets/webui-width-probe.wasm` route, backed by `readWasmArtifact`); a
`WebUIServer` host registers it as a `WebUIServerAsset` binary entry.

## 3b. typed islands — payloads that are not strings

a string island parses its input out of a json args object. a **typed island**
ships the input as a versioned binary frame instead: encoded once on the
server, carried through the engine untouched, decoded in the module with no
json parse. use it when the payload is structured data — a chart series, a page
of rows — and the parse/allocation cost or the wire size matters.

```swift
public protocol TypedIsland: Sendable {
	associatedtype Input: IslandPayloadEncodable & IslandPayloadDecodable
	static var name: String { get }
	static func render(_ input: Input) -> String
}

public protocol TypedResizableIsland: Sendable {   // + width: Int? in render
	associatedtype Input: IslandPayloadEncodable & IslandPayloadDecodable
	static var name: String { get }
	static func render(_ input: Input, width: Int?) -> String
}
```

the region views are `TypedIslandRegion<I>` and `TypedResizableIslandRegion<I>`.
declaring one emits the capability, the resize flag where applicable, and:

```html
<div data-webui-island="chart-probe" data-webui-island-resize="true"
     data-webui-args='{"frame":"V1VJMQ…"}'>…fallback markup…</div>
```

**the wire frame** (`IslandEnvelope`, in `WebUIIslandWire`):

```
frame   := "WUI1" | u16be version | u16be reserved | u32be payload length | payload
payload := the value's IslandPayloadEncodable bytes, exactly payload length
```

the frame is base64-armored inside the args object — the engine parses that
object, adds the measured width, and hands the module its mount envelope
exactly as it does for a string island. **no javascript knows what a frame is**,
which is why the typed door cost zero engine bytes.

**the payload pair.** `IslandPayloadEncodable` reports a byte count and writes
to a destination pointer; `IslandPayloadDecodable` rebuilds from exactly one
buffer (`nil` on any length or content mismatch). the discipline is deliberate:
fixed layout, big-endian, all-or-nothing consumption. write a codec by hand:

```swift
extension MyPayload: IslandPayloadEncodable, IslandPayloadDecodable {
	func islandEncode(count: inout Int) { count = 2 + label.utf8.count + 8 }
	func islandEncode(_: UnsafeMutableRawPointer.Type, destination: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer { … }
	init?(islandDecode buffer: UnsafeRawBufferPointer) { … }
}
```

`IslandUTF8.decode(_:)` is the strict foundation-free text reader for string
fields (replace-with-U+FFFD is `decodeReplacingInvalid`, the lenient harness
policy). your codec must stay within `WebUIIslandWire`'s dependency budget:
**no Foundation, and no rawdog** — rawdog's module cannot compile for embedded
wasm (`RAW` uses `Codable`, which embedded Swift does not have; `CRAW` needs
mmap emulation), so a rawdog-conforming type cannot be decoded inside an
island. bridge a rawdog type host-side if you need one for storage, but the
island payload is this pair.

**the product** is one call:

```swift
TypedIslandEntry.installResizable(MyPayload.self, render: MyRenderer.render)
```

`TypedIslandEntry.install` covers the static case. both decode the mount args,
merge the engine-measured width, and return an empty frame on any decode
failure — which is the engine's existing "keep the fallback" path, not a new
mechanism.

**the live example** is the smoke page's `#island-chart` region: a `ChartSpec`
(five values, a title) mounts at the measured width, re-renders on resize, and
its output passes the fragment sanitizer. `browser-smoke.mjs` asserts the mount,
the frame magic in the args attribute, and the resize re-render.

## 3c. targets and the artifact gate

the island side is four narrow targets, not one shared blob:

| target | holds | depends on |
|---|---|---|
| `WebUIIslandWire` | the contract both sides implement: `IslandPayload*`, `IslandEnvelope`, base64 armor, the utf-8 scanner, the `@_exported` leaf seam | the leaf |
| `WebUIIslandRuntime` | the wasi harness (`IslandEntry`) and entry installers (`TypedIslandEntry`) — wasm-only code | wire |
| your capability module | the renderer both sides call (one target per capability) | wire |
| your product | `main` (hook assignment + any `@_expose` extra) | runtime + your capability |

an island's dependency set *is* its capability set. editing the chart renderer does not
rebuild the width probe, and a dependency added to one capability cannot silently change
another.

`plugin wasm-island` enforces that shape instead of trusting it, and it fails the build
that produced the violation:

- **graph rules (before the cross-build).** a capability module is a leaf — it may depend
  only on the shared layer; a product owns at most one capability module; a shared module
  never depends on a capability module. without them the symbol audit's "foreign" set is
  self-referential: an accidental edge folds the leaked module into the product's own
  closure and the gate would call the leak legitimate.
- **symbol audit (on the unstripped artifact, where the name section still exists).**
  every defined symbol's module must be shared or in this product's own closure; a foreign
  module fails the build. reads `llvm-nm`, resolved from `WEBUI_LLVM_NM`, the active
  toolchain, `xcrun`, or the installed toolchains.
- **export audit (on the artifact that ships).** exports must equal the runtime's
  `@_expose` set plus this product's own, modulo `memory` and `_start`. a fifth export
  nobody declared is a wire change that belongs in source.

every expectation is derived from the manifest and the sources — there is no per-product
allowlist to maintain, and a new capability is covered the moment its target exists.

## 4. what the engine does (the mount contract)

for each `[data-webui-island]` region the page's config grants:

1. fetch the artifact once; compile-stream, instantiate with stubbed imports;
2. call `_start` (your `main` — installs the render hook);
3. write `{name, args}` (≤ 64 KB) into the module's input buffer;
4. call `webui_render_region`, read the frame, **sanitize** the returned html through
   the same fragment sanitizer the websocket patch path uses, and swap it into the
   region;
5. set `data-webui-island-state="mounted"`; on any failure `"unmapped"` and the
   server-rendered fallback stays.

**resizable regions additionally:** a `ResizeObserver` watches the region; entries skip
unmounted nodes, zero widths (hidden/collapsed), and unchanged rounded widths; changes
coalesce to one re-render per region after 120 ms, measured fresh at fire time. a
fragment patch that replaces island content re-mounts it from the cached module and
re-observes the replacement (the old node is unobserved — no leak).

## 5. gotchas

- **one capability per artifact.** the product's entry is single-purpose; the four
  standard exports are shared, but extra exports (`webui_validate`) belong to that
  product. two capabilities wanting the same logic share the *code*, not the artifact.
  the build gate enforces all of it — see §3c.
- **`Island.name` must equal the route's `<name>`.** `name = "width-probe"` fetches
  `/__assets/webui-width-probe.wasm`. a mismatch is a silent `unmapped`.
- **the island targets stay Foundation-free.** a `Foundation` import in
  `WebUIIslandWire`, `WebUIIslandRuntime`, or any capability target breaks the wasm build.
- **width is a client fact.** never trust a width for anything but layout; the server
  render has none.
- **re-render replaces the region's children**, so a CSS transition on them restarts.
  acceptable for width-driven re-layout; don't rely on animation continuity inside a
  resizable region.
- **`'wasm-unsafe-eval'` is in the default CSP** for every engine page (needed to
  instantiate islands). scoping it per declared capability is a known follow-up.
- **degrade is by design.** no artifact → fallback markup, page fully functional,
  logged once. gates report a skip, not a failure, when the artifact is absent.

## 6. verification

| gate | asserts |
|---|---|
| `swift test --filter ResizeContract` | region markup, byte-identity of `IslandRegion`, `width == nil` server-side, protocol refinement |
| `swift package plugin budget` | every shipped surface (engine, sheet, shell, island artifacts) within its pinned ceiling |
| `swift package --disable-sandbox plugin smoke` | the artifact serves as `application/wasm`; the page pins its interactive count |
| `node designer/browser-smoke.mjs` | real-browser mount at measured width, viewport-resize re-render, non-flagged isolation, same-width no-op, patch re-mount |
| `plugin wasm-island` | the artifact builds, its dependency graph holds the island shape, no foreign capability symbols survive, and the export surface equals its declarations |

the smoke page's `#island-width` region is the live example; its "Re-render island"
control exercises the patch path. the full arc record lives in
`.hermes/plans/2026-10-20_100605-wasm-applogic-improve.md`.