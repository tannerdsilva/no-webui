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
| smoke gate (server + 15 checks + teardown) | `swift package --disable-sandbox plugin smoke` | disabled |
| full-stack gate (server + live WS round-trips + teardown) | `swift package --disable-sandbox plugin fullstack-smoke` | disabled |
| browser gate (playwright layout, self-contained) | `node designer/browser-smoke.mjs` | none (not a plugin) |
| port probe | `swift package plugin probe [port]` | on |
| regenerate showcase into designer/previews/ | `swift package plugin showcase --allow-writing-to-package-directory` | on (write permission) |
| ad-hoc showcase to any path | `swift package plugin showcase --output <path> --allow-writing-to-package-directory` | on |

## stage 1 — asset embedding (build time, automatic)

`WebUIAssetPlugin` (build tool plugin, applied to the `WebUI` target) runs
`WebUIAssetTool` during every `swift build`. it reads
`designer/assets/design-system.css` and `designer/assets/webui-runtime.js` —
the canonical source of truth — and generates `Assets+Generated.swift` into the
plugin work directory (under `.build/`, gitignored) as swift string constants
consumed by `WebUIDocument` and `WebUIRuntime`.

to update assets: edit the files in `designer/assets/`, then `swift build`
(any plugin/gate invocation that builds `WebUI` also picks them up).

## stage 2 — unit verification

`swift test` — 264 tests across 11 suites covering views, modifiers, event
routing, sanitization, and design-system components.

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
edit designer/assets/*  →  swift build (stage 1)  →  swift test (stage 2)
→  serve (stage 3, optional interactive)  →  smoke + fullstack-smoke + browser-smoke (stage 4)
→  showcase  (regenerated reference page)
```
