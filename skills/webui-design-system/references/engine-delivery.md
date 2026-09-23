# Engine-first delivery — documents, routes, islands

the default client runtime is the framework-owned **engine** (`webui-engine.js`,
~30 kb, shipped asset, no consumer-facing JS). the retired wasm-only default is
gone; the wasm client remains available via an explicit
`ClientBoot(flavor: .wasm, …)` provider for applet/client-mode pages.

## Document contract (what every default page emits)

- `WebUIDocument` default boot is engine flavor and **links the design sheet**:
  `<link rel="stylesheet" href="/__assets/css">` (same bytes as the old inline
  sheet — `DesignSystemAssets.minifiedCss`; `WebUIDocument(stylesheetURL: nil)`
  inlines like before, and `HTMLDocument` stays inline by default). the
  document itself is ~2.6 kb.
- `<meta name="webui-config" content="{…}">` first (config-meta ordering
  gotcha: the engine's boot glue reads it during head parse, so the meta must
  precede the script tag), then `<script src="/ui/webui-engine.js">`.
- `RuntimeConfig` rides the `webui-config` meta. keys are camelCase
  (`wsUrl`, `debounceInputMs`, `optimisticSettleMs`, `logLevel`,
  `renderToken`, `capabilities: ["validate", "offline", …]`, `persistence`).
  tests that read config must decode the entity-escaped meta
  (`&quot;` → `"`), not search for `WebUIRuntime.init`.
- `ClientBoot(flavor: .wasm, …)` switches a page to the wasm contract
  (`webui-wasm` meta + `/ui/webui-client.js` + `/ui/webui-app-boot.js`), which
  the chamber/applet path still serves byte-for-byte.
- CSP is the client csp (no nonce, `script-src 'self' …`); the engine adds no
  inline scripts, so it needs nothing beyond 'self'.

## The server must serve

- `/__assets/css` → the design sheet (`DesignSystemAssets.minifiedCss`), with
  `public, max-age=3600` (cacheable — this is the whole point of the link)
- `/ui/webui-engine.js` → the engine (`WebUIAssets.engine`), `public, max-age=3600`
- `/ui/webui-shell.js` → the offline service worker (`WebUIAssets.shell`) —
  register it only when the page declares the `offline` capability, with
  `{ scope: '/' }`; the server must send `Service-Worker-Allowed: /` (the
  default max scope is the script's directory, and a missing header makes
  browser registration reject with a SecurityError).
- `/__assets/webui-<capability>.wasm` → island artifacts, `application/wasm`
- `/ws` is the authority channel (same envelope as ever: `event`/`ping` →
  `pong`/`update` fragments).
- the wasm client's routes (`/ui/webui-client.js`, app-boot, content-addressed
  artifact) only matter for explicit wasm-mode pages.

## Capability islands

- the engine lazily fetches `/__assets/webui-<name>.wasm` only for capabilities
  declared in `webui-config.capabilities`; an absent artifact degrades to
  `data-webui-island-state="unmapped"` with a console warning, and the page
  stays fully server-rendered + engine-driven.
- a region is `<div data-webui-island="validate" data-webui-args='{…}'>`; the
  module composes it via the region contract (`webui_input_ptr` /
  `webui_render_region` / `webui_frame_ptr|len`), sanitized before mount.
- build islands with
  `swift package --disable-sandbox plugin wasm-island --sdk swift-6.4.0-RELEASE_wasm-embedded`
  (the plugin links the sdk's `libswiftUnicodeDataTables.a` automatically).
- island logic must stay **scalar-clean** (no `Character(...)`, no
  `String(decoding:as:)`, no `firstRange`) and dependency-free of swift-log —
  see `WebUISharedCore` for the pattern and the measured 160 kb result.

## Verify (per change)

`swift build` → `swift test` → `plugin smoke` → `plugin fullstack-smoke`
(default = engine; `WEBUI_BOOT=wasm node designer/browser-smoke.mjs` for the
wasm regression path). browser-smoke drives engine mode by default with
`node designer/browser-smoke.mjs`; it also proves the shell, view transitions,
and the island mount/degrade/re-validate probes. both themes are audited with
`emulateMedia({ colorScheme: 'dark' })`.
