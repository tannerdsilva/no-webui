# Render token dropped by init() → token-gated server bounces the page

Session 2026-09-17 (no-webui `dev` + the arc-agent consumer). The visual layer
was polished (login/chat/bots/settings all ≈9/10 dark theme, no defects) but a
NON-visual runtime defect was silently dropping the server-minted render token.
The paint looked great while the socket lifecycle was broken — the classic
"terrible / broken" report that is really a functional regression.

## The mechanism (durable, not checkout-specific)

`designer/assets/webui-runtime.js` `init(config_)` builds its `config` object by
copying **only the keys named in `DEFAULTS`**:

```js
function init(config_) { … var config = {}; for (var key in DEFAULTS) {
  if (config_ && (key in config_)) config[key] = config_[key]; else
    config[key] = DEFAULTS[key]; } … }
```

Any key the server injects into the bootstrap (`WebUIRuntime.init({…})`) that is
NOT a `DEFAULTS` key is **silently discarded**. The server mints a per-render
`renderToken` into the bootstrap, but `renderToken` was absent from `DEFAULTS`,
so the live runtime held `config.renderToken === null`.

No-webui's own security invariant #11: every `event`/`ping` must echo the render
token; the token-gated server (WebUIAuth) **redirects the page and closes the
socket** on a missing/unknown token. So the tokenless first ping (30s after
load) made the server send `redirect:` + close.

## Consequence in a real session

- A logged-in user idles 30–90s on a sub-page (settings/bots) → the first ping
  goes out tokenless → the server redirects to `/` and closes → the page bounces
  to `/chat`; the user loses their sub-page.
- Console logs `Close received after close` (the runtime's own WS state machine
  racing the server's close).

## The fix (verified end-to-end this session)

One line in `designer/assets/webui-runtime.js` — add the key to the whitelist so
the bootstrap value is preserved (the server still mints per-render and refreshes
in-place via the existing `if (msg.token) config.renderToken = msg.token`):

```js
var DEFAULTS = { …, logLevel: 'warn', renderToken: null };
```

Plus a guard test in `Tests/WebUITests/DeploymentIntegrityTests.swift` pinning
`js.contains("renderToken: null")` so the whitelist can't regress. `swift build`
regenerates the embedded `WebUIAssets.js` from the asset, and the byte-identity
test keeps the two in sync automatically.

Verified: no-webui full suite green (new guard passes); rebuilt the CONSUMER
(arc-agent) so it embeds the fixed runtime; restarted its gateway; fresh
logged-in session on `/settings` for 90s → `config.renderToken` non-null, 3
tokened ping/pong cycles at 30s, **zero** console errors, **zero** bounces,
socket CONNECTED at the end.

## Diagnosis recipe (reproducible)

1. **Bootstrap-vs-live diff.** Compare what the server injected with what the
   runtime kept:
   - `grep -o 'WebUIRuntime\.init([^)]*)' page.html` → the injected keys/values.
   - In-page: `WebUIRuntime._getInstance().config` (or read the bootstrap script
     + the live object). A key present in the bootstrap but `null`/absent in
     `config` = dropped by the whitelist.
2. **Force the degraded path.** On a logged-in page, send ONE tokenless ping on
   the live socket and watch the URL within ~3s (the redirect frame lands, the
   server closes). Distinguishes "token was dropped" from "token was wrong".
3. **Real-session symptom.** Fresh logged-in context, idle past one ping interval
   (30s): if the page bounces or logs `Close received after close`, the token is
   being dropped — not the socket, not the server.

## Consumer-app verification tier (arc-agent)

The in-repo no-webui gates (`smoke` / `fullstack-smoke` / `browser-smoke`) host
their OWN server and can't see what a *consuming app* actually deploys. To verify
the consumer's real output:

1. `cd arc-agent && ARC_WEB_PASSWORD='<known>' .build/debug/arc-agent serve
   --port 8098 --web-port 8099`. The `ARC_WEB_*` env overrides let you set known
   login creds; without them a random password is generated (from
   `~/.arc/config.json`).
2. In a browser: fresh context → login (CSRF `_csrf` field + credentials →
   submit) → visit each real page (login / chat / bots / settings).
3. Idle past the ping interval on a sub-page; assert URL unchanged,
   `config.renderToken` non-null, socket `readyState` CONNECTED, zero console
   errors.

Pitfalls:
- A raw-WS node/Python probe from the shell usually 403s at the upgrade gate
  (it can't replicate the exact browser header set). The **in-page browser socket**
  is the faithful probe — drive the probe from within the page's own socket context.
- `file://` can't test the token flow — the token round-trips over a **served**
  page. Use a live HTTP serve for token verification.
- Rebuild the **consumer** after any no-webui asset change — the consumer embeds
  no-webui via a local path dep, so building no-webui alone does NOT update the
  consumer's embedded copy.
