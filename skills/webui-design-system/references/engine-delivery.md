# Engine-first delivery — documents, routes, islands

the default client runtime is the framework-owned **engine** (`webui-engine.js`,
~30 kb, shipped asset, no consumer-facing JS). the retired wasm-only default is
gone; wasm survives as per-page capability islands (see below).

## Document contract (what every default page emits)

- `WebUIDocument` default boot is engine flavor and **links the design sheet**:
  `<link rel="stylesheet" href="<content-addressed>">` — the default
  `stylesheetURL` is `DesignSystemAssets.stylesheetURL`
  (`/__assets/css.<sha256>` of the minified sheet). a rebuilt sheet is a new
  url, so the route is served `public, max-age=31536000, immutable` and never
  needs revalidation or invalidation. the legacy `/__assets/css` path (same
  bytes — `DesignSystemAssets.minifiedCss`) is still served with a short cache
  for old pages. `WebUIDocument(stylesheetURL: nil)` inlines like before, and
  `HTMLDocument` stays inline by default. the document itself is ~2.6 kb.
- `<meta name="webui-config" content="{…}">` first (config-meta ordering
  gotcha: the engine's boot glue reads it during head parse, so the meta must
  precede the script tag), then `<script src="/ui/webui-engine.js">`.
- `RuntimeConfig` rides the `webui-config` meta. keys are camelCase
  (`wsUrl`, `debounceInputMs`, `optimisticSettleMs`, `logLevel`,
  `renderToken`, `capabilities: ["validate", "offline", …]`, `persistence`).
  tests that read config must decode the entity-escaped meta
  (`&quot;` → `"`), not search for `WebUIRuntime.init`.
  the chamber/applet path still serves byte-for-byte.
- CSP is the client csp (no nonce, `script-src 'self' …`); the engine adds no
  inline scripts, so it needs nothing beyond 'self'.

## The server must serve

- `/__assets/css` → the design sheet (`DesignSystemAssets.minifiedCss`), with
  `public, max-age=3600` (cacheable — this is the whole point of the link)
- `/__assets/css.<sha256>` → the same sheet, content-addressed, served
  `public, max-age=31536000, immutable`; this is what `WebUIDocument` links
  by default. serve both; gzip (`Content-Encoding: gzip` + `Vary:
  Accept-Encoding`) — the ~310 kb sheet is ~46 kb on the wire. `WebUIServer`
  does all of this out of the box
- `/ui/webui-engine.js` → the engine (`WebUIAssets.engine`), `public, max-age=3600`
- `/ui/webui-shell.js` → the offline service worker (`WebUIAssets.shell`) —
  register it only when the page declares the `offline` capability, with
  `{ scope: '/' }`; the server must send `Service-Worker-Allowed: /` (the
  default max scope is the script's directory, and a missing header makes
  browser registration reject with a SecurityError).
- `/__assets/webui-<capability>.wasm` → island artifacts, `application/wasm`
- `/ws` is the authority channel (same envelope as ever: `event`/`ping` →
  `pong`/`update` fragments).
  artifact) only matter for explicit wasm-mode pages.

## Capability islands

- the engine lazily fetches the island's wasm — the URL comes from the served
  manifest's `islands[]` (`/ui/continuum-manifest.json`, content-addressed)
  with the name-convention `/__assets/webui-<name>.wasm` fallback (v1
  payload / 404). an absent artifact degrades to
  `data-webui-island-state="unmapped"` with a console warning, and the page
  stays fully server-rendered + engine-driven.
- a region is `<div data-webui-island="validate" data-webui-args='{…}'>` —
  declare it with the `WebUIIsland(id:name:args:)` view (the pinned byte
  contract: attribute order id → data-webui-island → data-webui-args,
  single-quoted args); the module composes it via the region contract
  (`webui_input_ptr` / `webui_render_region` / `webui_frame_ptr|len`),
  sanitized before mount.
- islands build AUTOMATICALLY inside a plain `swift build`
  (`WebUIAutobuildPlugin`; the once-per-app block comes from `scaffold
  --bootstrap` or the app template). `plugin wasm-island` is an internal
  framework verb (no `--sdk` flag — the swiftly toolchain is resolved
  host-side); the ONE consumer-facing verification verb is `verify`:
  `webui-continuum verify --package-dir . --framework <no-webui path>`
  (or `swift package --disable-sandbox plugin verify` in the framework
  home).
- island logic must stay **scalar-clean** (no `Character(...)`, no
  `String(decoding:as:)`, no `firstRange`) and dependency-free of swift-log —
  see `WebUISharedCore` for the pattern.

## Verify (per change)

`swift build` → `swift test` → `plugin smoke` → `plugin fullstack-smoke`
wasm regression path). browser-smoke drives engine mode by default with
`node designer/browser-smoke.mjs`; it also proves the shell, view transitions,
and the island mount/degrade/re-validate probes. both themes are audited with
`emulateMedia({ colorScheme: 'dark' })`.
