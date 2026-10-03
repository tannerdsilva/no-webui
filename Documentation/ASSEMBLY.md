# Assembly

how the package assembles and verifies itself, stage by stage. source of truth
for the project tooling. see also `Documentation/ARCHITECTURE.md` for the
runtime architecture and `designer/README.md` for the designer-facing workflow.

## tooling surface — one table

every developer action is a single command. there are no shell scripts.

| task | command | sandbox |
|---|---|---|
| build (embeds assets) | `swift build` | — |
| unit tests | `swift test` | — |
| host the smoke/demo server on :9123 | `swift package --disable-sandbox plugin serve` | disabled (bind requires it) |
| host the auth demo on :9091 | `swift run WebUIAuthExample` | — |
| smoke gate (server + 7 checks + teardown) | `swift package --disable-sandbox plugin smoke` | disabled |
| full-stack gate (server + live WS round-trips + teardown) | `swift package --disable-sandbox plugin fullstack-smoke` | disabled |
| browser gate (playwright layout, self-contained) | `node designer/browser-smoke.mjs` | none (not a plugin) |
| port probe | `swift package plugin probe [port]` | on |
| regenerate showcase into designer/previews/ | `swift package plugin showcase --allow-writing-to-package-directory` | on (write permission) |
| ad-hoc showcase to any path | `swift package plugin showcase --output <path> --allow-writing-to-package-directory` | on |
| svg icon tooling (generate/lint/list/stats/render-preview) | `swift run WebUIIconTool <verb> --manifest designer/icons/icon-manifest.json …` | on |

## stage 1 — asset embedding (build time, automatic)

`WebUIAssetPlugin` (build tool plugin, applied to the `WebUI` target) runs
`WebUIAssetTool` during every `swift build`. it reads
`designer/assets/design-system.css` and `designer/assets/webui-runtime.js` —
the canonical source of truth — and generates `Assets+Generated.swift` into the
plugin work directory (under `.build/`, gitignored) as swift string constants
consumed by `WebUIDocument` and `WebUIRuntime`.

to update assets: edit the files in `designer/assets/`, then `swift build`
(any plugin/gate invocation that builds `WebUI` also picks them up).

the tool also *composes* what ships. the served sheet is the layer order
statement, then the layout primitives wrapped in `@layer webui.utilities`, then
the working sheet — which is itself wrapped in `@layer webui` in the source, so
the working file the dev preview links behaves exactly like the served bytes.
unlayered css (the app's own sheet, `rawStyles`, the theme sheet) outranks both
layers by cascade origin. and the payloads are prose-free by construction:
`WebUICore.ProseGuard` scans the runtime, engine, shell and minified sheet and
fails the build naming file, line and text — the first law, enforced where the
payloads are fixed. `--used-tokens <path> [--guard-css <path>]` optionally prunes
the sheet's `:root` surface to the reachable set (T9), recording the counts in the
build manifest; omitted, the sheet ships whole.

## stage 1b — svg icon generation (build time, automatic)

`WebUIIconPlugin` (build tool plugin, applied to the `WebUI` target, alongside
`WebUIAssetPlugin`) runs `WebUIIconTool generate` during every `swift build`.
it reads `designer/icons/icon-manifest.json` — the canonical icon catalog — and
generates `IconLibrary.swift` into the plugin work directory (under `.build/`,
gitignored): the `IconName` enum (618 glyphs), the `WebUIIcons` catalog table,
and the category enum, consumed by `WebUIIcon` / `WebUIIconCustom`.

the generator is deterministic (same manifest → same bytes), so the build
plugin's output never drifts from the manifest and produces no spurious diffs.
the same tool backs the standalone verbs (`lint` for a CI gate, `list` for
discovery, `stats` for the payload report, `render-preview` for the visual QA
page). to update the catalog: edit `designer/icons/icon-manifest.json`, run
`swift run WebUIIconTool lint --manifest designer/icons/icon-manifest.json`,
then `swift build`. see `Documentation/ICONS.md`.

## stage 2 — unit verification

`swift test` — 903 tests across 89 suites covering views, modifiers, event
routing, sanitization, the svg icon catalog + api, design-system components,
web-ui hardening (url sanitization, escaping, the icon allowlist, the json
nesting cap), the `ConnectionGate`, and the `WebUIAuth` authentication
foundation (tokens, cookies, stores, Argon2id, throttles, single-use csrf),
plus end-to-end ceremony tests that boot the real auth server over raw
sockets (session-gated upgrade, render-token ws binding, byte-complete
delivery, accept-time connection cap).

## stage 3 — the server

`serve` hosts the `WebUISmokeTest` server (the full NIO HTTP + WebSocket stack,
the interactive counter/progress/echo demo page) as a child process, binding and
listening on :9123. the command-plugin sandbox forbids `bind()` — even with the
local network permission — so the verb is run with the sandbox disabled. `serve`
keeps running until Ctrl+C (SIGINT/SIGTERM are forwarded to the child, leaving
no orphans).

note: a running plugin invocation holds the package `.build` lock for its whole
run, so `serve` cannot run concurrently with other `swift package` commands.
run it standalone, then Ctrl+C before the next invocation.

## stage 3b — the auth demo (opt-in)

`swift run WebUIAuthExample` hosts the login-gated interactive demo on :9091
(no plugin, no sandbox — it is a plain executable like `WebUIExample`). sign in
with `admin` / `password`.

what it demonstrates:

- a runtime-free login page (native form POST per AD-1 of
  `Documentation/AUTH_SESSIONS.md`) with a synchronizer CSRF token, hardened
  CSP, and `X-Frame-Options`
- M0 `WebUIAuth` machinery end to end: `SessionToken` (SecureRandom-only,
  SHA-256 hashed at rest), the in-memory session store, cookie parse/build,
  `PasswordVerifier` Argon2id with dummy-hash equalization and a
  `constantTimeEquals` username compare, `AuthContext`
- the interactive dashboard (counter / progress / echo, optimistic reset) with
  a per-session router; the WebSocket upgrade refuses foreign/no-origin
  handshakes and, per event, checks the session is still valid — after logout
  or expiry an open socket is redirected to `/login` and closed
- CSRF-protected POST logout

the demo applies the full M2 hardening: the Argon2 concurrency cap
(`AsyncSemaphore` + dedicated pool) so the login endpoint is not a
CPU/memory flood amplifier, per-ip + per-account throttles, single-use
login tokens with per-issuer outstanding budgets, a connection gate with
bare-connect admission, idle socket reaping, per-session state containers
(bounded, purged by the sweep and on logout), and a 60 s maintenance sweep
(session purge, throttle/token-store pruning, router + state cleanup).
per-identity session caps are a deployment policy — the store holds every
live session until expiry, so hosts that need caps enforce them at login
(e.g. invalidating older sessions via `listSessions` / `invalidateAll`).
the auth demo has no plugin gate — the `smoke`/`fullstack-smoke`/
`browser-smoke` gates cover the framework reference page only, and are
untouched by it.

## stage 4 — deployment gates

the gates are self-contained single commands: each spawns the server via
`context.tool(named:)`, runs its checks, and tears the server down on every
path. they cannot target a server hosted by another plugin invocation (the
lock above), so hosting and checking happen inside one invocation.

| gate | what it proves |
|---|---|
| `smoke` | served asset bytes == `designer/assets/` source; page-structure signatures; self-containment; CSP |
| `fullstack-smoke` | live WebSocket round-trips (ping/pong, click/echo, DOM patch via FragmentUpdate) driven through node |
| `browser-smoke` (node) | real-layout invariants in headless Chromium (playwright), screenshot to `.smoke/browser.png`; not a plugin verb because chromium cannot run inside the plugin sandbox |

all gates exit non-zero on the first failure.

## stage order in practice

```
edit designer/assets/*        →  swift build (stage 1)      →  swift test (stage 2)
edit designer/icons/*.json    →  swift build (stage 1b)
→  serve (stage 3, optional interactive)  →  smoke + fullstack-smoke + browser-smoke (stage 4)
→  showcase  (regenerated reference page)
```

## blocks (p6)

`WebUIBlocks` is a library product of standalone page scaffolds; `WebUIBlocksServer`
serves one of them per process (``--block <name>``, default ``index``) on :9093.

the plan proposed routing them on the showcase server at ``/blocks/<name>``. that
would have required changing ``WebUIServer.Render`` (``@Sendable () -> String``,
no request argument) — a pinned public API — so the server takes ``--block`` and
serves that page at ``/`` instead. ``WebUIServer`` now also offers a
request-aware render (``requestRender:``, receiving a ``WebUIServerRequest``),
which removes that constraint for a future revision; ``Render`` itself is
unchanged, and the ``--block`` arrangement stands. the exit gate is satisfied more strongly this
way: a block is served with no showcase dependency at all, and the index page
links every block.

evidence gate: ``node designer/blocks-sweep.mjs`` (spawns the server per block,
sweeps 320/768/1440 in both themes, asserts no horizontal overflow and that each
block renders the parts it claims, writes ``.smoke/blocks-<date>/``).

blocks compose the existing class surface only; the pins assert that every class
a block emits exists in the sheet, which is what caught the orphan
``chart__axis-label--x``.

## local state (gitignored)

everything below is working state, never committed, and disposable — the build
and the gates recreate it. nothing here is needed to compile, test, or serve the
package: a fresh clone with an empty tree builds from scratch.

| path | written by | rough size | clear with |
|---|---|---|---|
| `.build/` | `swift build` / `swift test` — products, dependency checkouts, and the plugin outputs (`Assets+Generated.swift`, `IconLibrary.swift`, `DesignTokens+Generated.swift`, `Wasm+Generated.swift`) | a release build lands around 3–4 GB, dominated by the swift-syntax checkout | `swift package clean`, or `rm -rf .build` for a from-scratch build |
| `.build/swift-package-audit/` | the external audit toolchain's ephemeral scratch build root, one per run | transient | the toolchain sweeps it itself; `rm -rf .build` also clears it |
| `.build-audit/` | a **legacy** name for that same audit scratch root — removed 2026-09-29 | was 1.3 GB | already gone; an older checkout can `rm -rf .build-audit` |
| `.smoke/` | every gate run writes dated evidence (`blocks-<date>/`, `rtl-<date>/`, `chart-mobile-<date>/`, screenshots) | tens of MB, growing per run | `rm -rf .smoke` — it is evidence, not input |
| `.audit/` | nothing in this repo — leftover output of older ad-hoc design audits | ~7 MB | `rm -rf .audit` |
| `.hermes/` | agent session plans and notes | small | `rm -rf .hermes` (loses the plan history) |

the convention: **audit and gate tooling leaves no persistent build state.** a
tool that needs scratch space uses `.build/<tool>-scratch/` and clears it on
exit; anything that outlives a run is listed above and is safe to delete.

`designer/previews/screenshots/` is deliberately *not* in that category: those
PNGs are tracked and regenerated by `designer/capture-previews.mjs`, so the
`.gitignore` rule for the path governs only newly generated files.
