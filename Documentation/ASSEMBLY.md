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

`swift test` — 567 tests across 62 suites covering views, modifiers, event
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

**deliberately not in the demo (plan M2):** the Argon2 concurrency cap /
bounded queue (the login endpoint remains a CPU+memory flood amplifier),
session caps and the sweep service, per-session state containers (the demo
shares one global state across sessions). the auth demo has no plugin gate —
the `smoke`/`fullstack-smoke`/`browser-smoke` gates cover the framework
reference page only, and are untouched by it.

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
