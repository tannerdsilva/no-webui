# AGENTS.md — no-webui

operational guidance for autonomous agents working on this project.

## project overview

two major parts under one Package.swift:

1. **no-webui core** — low-level Swift libraries (IP, futures, FIFO, pthread).
   mature, stable, minimal changes expected.
2. **WebUI** — SwiftUI-for-web framework. actively developed. this is
   where most work happens.

## first law — no inline comments in source

every line of documentation belongs in `Documentation/*.md` files. source files
contain zero `///` doc comments and zero `//` line comments. the only exceptions
are `// MARK:` (structural, Xcode navigation) and `// swift-tools-version:` in
Package.swift.

do not add, restore, or generate inline comments in any source file. if you
need to explain something, put it in the appropriate `Documentation/*.md` file.

## build and test

```bash
swift build             # includes plugin that auto-generates Assets+Generated.swift
swift test              # 244 tests, 11 suites
swift run WebUIExample  # example server on :9090
swift run WebUISmokeTest # interactive full-stack demo on :9123 (ws: /ws)
designer/sync.sh        # build + test + regenerate designer/previews/showcase.html
designer/demo.sh        # build + start demo server + open browser at :9123
designer/smoke.sh       # asset-integrity + deployed-page smoke gate
designer/fullstack-smoke.sh  # full-stack deployment gate (live WS round-trips)
```

the `WebUIAssetPlugin` build tool plugin runs automatically during `swift build`.
it reads `designer/assets/*.css` and `*.js` and generates
`Assets+Generated.swift` with the content embedded as Swift string constants.
no manual `swift run WebUIAssetTool` needed.

## project conventions

### code

- **lowercase comments** in `Documentation/*.md` files. prose is lowercase
  (no sentence capitalization). preserve backticked identifiers, quoted string
  literals, CLI flags, and acronyms.
- **tabs for indentation** in Swift source. `.spacesToTabs(4)`.
- **value types first** — default to struct. only use class for identity (===),
  reference semantics, or ObjC interop. only use actor for shared mutable state
  accessed from multiple tasks.
- **protocols first** — every abstraction starts as a protocol. multiple
  conformances encouraged. protocols never depend on concrete types.
- **no ad-hoc cleanup** — no `shutdown()` methods on non-Service types.
  cleanup belongs at the end of `Service.run()`.
- **no fatalError() in macro implementations** — always emit a Diagnostic.
- **no defer { await ... }** — `await` is forbidden in `defer` in Swift 6.
- **Swift Testing** (`import Testing`, `@Test`, `#expect`) for all new tests.
- **Swift Regex** over `NSRegularExpression` when targeting macOS 13+.
- **Int over size_t** everywhere.

### web UI framework conventions

- **View protocol** — `func render() -> String`. pure function, no side effects.
- **ViewModifier protocol** — `func apply(to html: String) -> String`. wraps
  rendered HTML with attributes or styles.
- **EventRouter** — routes WebSocket events to registered handlers. thread-safe
  via NSLock. max 10,000 handlers by default.
- **RenderContext** — `@TaskLocal` context for component ID generation and
  handler registration. must be set before rendering.
- **HTMLDocument** — assembles complete HTML with auto-generated CSP and nonce.
- **ObserverList** — thread-safe collection of Observable conformers. max 100
  observers by default.
- **CSRFProtection** — stateless HMAC-SHA256 tokens. no server-side storage.

### asset embedding

CSS and JS assets live in `designer/assets/` (the design system's working
directory). the `WebUIAssetPlugin` build tool plugin reads them and generates
`Assets+Generated.swift` during every build. the generated file lands under
`.build/` (gitignored).

to update assets:
1. edit the `.css` or `.js` file in `designer/assets/`
2. run `swift build` — the plugin regenerates the Swift file automatically

the designer's live preview is `designer/previews/designer-preview.html`, which
links `designer/assets/design-system.css` directly, so it reflects edits
instantly in the browser with no build step.

`designer/previews/showcase.html` is a generated artifact — a compiled snapshot
of the showcase page (Swift sources + embedded assets). it is not hand-edited.
regenerate it with `designer/sync.sh` (build + test + generate + copy).

the `designer-sync` workflow is a shell script, not a SwiftPM command plugin:
`swift package plugin` holds the package `.build` lock for the whole plugin
run, so a nested `swift build`/`swift test` inside the plugin deadlocks on
`flock()` of that same lock, and the command-plugin write sandbox also forbids
writing inside the package directory.

for ad-hoc showcase generation to a path outside the package
(e.g. `/tmp`), the `showcase` command plugin still works:
`swift package plugin showcase --output /tmp/showcase.html`.

### security invariants

these must never be weakened:

1. **CSP with nonces** — every HTML document gets a unique nonce. all inline
   `<script>` tags include `nonce="..."`. default CSP covers script-src,
   style-src, img-src, connect-src.
2. **URL sanitization** — `sanitizeURL()` blocks `javascript:`, `data:`,
   `vbscript:` protocols. applied to Link, Image, Form, Router.
3. **HTML sanitization** — `sanitizeFragmentHTML()` strips `<script>` tags,
   event handler attributes, and javascript: URLs before DOM insertion.
4. **Prototype pollution protection** — `State.set()` rejects `__proto__`,
   `constructor`, `prototype` keys.
5. **Attribute escaping** — `htmlEscape()` on all attribute keys and values
   in modifiers.
6. **CSRF tokens** — `CSRFProtection` with HMAC-SHA256 stateless tokens.
7. **Thread safety** — NSLock on all EventRouter.State and ObserverList
   mutations.
8. **Growth caps** — EventRouter.maxHandlers (10K) and ObserverList.maxObservers
   (100).

## common workflows

### adding a new primitive view

1. add the struct conforming to `View` in `Primitives.swift`
2. add any modifier methods in `Modifiers.swift`
3. add tests in `Tests/WebUITests/`
4. update `Documentation/API.md` with the new type and parameters
5. run `swift test` to verify

### adding a new design system component

1. add the component struct in `WebUIComponents.swift`
2. add CSS classes in `designer/assets/design-system.css`
3. add tests in `Tests/WebUITests/`
4. update `Documentation/DESIGN_SYSTEM.md` with the new component
5. run `swift build` (plugin regenerates assets) then `swift test`

### regenerating the showcase artifact

1. run `designer/sync.sh` (or `designer/sync.sh --no-test` to skip tests)
2. review `designer/previews/showcase.html` in a browser

### fixing a security issue

1. fix in the appropriate source file
2. add a test that proves the fix (e.g., XSS payload that now produces safe output)
3. run `swift test` to verify
4. update `Documentation/ARCHITECTURE.md` security table if adding a new mitigation
5. do not add inline comments explaining the fix — put the explanation in
   the appropriate `Documentation/*.md` file

## pitfalls

- **Assets+Generated.swift** is auto-generated and lives under `.build/`
  (gitignored). if you need to inspect it, run `swift build` first then look in
  `.build/plugins/outputs/no-webui/WebUI/tools/WebUIAssetPlugin/Assets+Generated.swift`.
- **Plugin failures** — if `swift build` fails with a plugin error, check that
  `designer/assets/` exists and contains both `design-system.css`
  and `webui-runtime.js`.
- **never nest `swift build`/`swift test` inside `swift package plugin`** — the
  plugin host holds the `.build` lock; the nested process deadlocks on it
  (observed: nested build parked in `flock()` indefinitely). keep such
  workflows in shell scripts like `designer/sync.sh`.
- **`Logger.Message` type** — swift-log's `Logger` methods take `Logger.Message`,
  not `String`. string concatenation with `+` doesn't produce `Logger.Message`.
  use string interpolation or a single string literal.
- **`@unchecked Sendable`** — used for NSLock-guarded classes. the lock is the
  synchronization mechanism, not the type system. do not remove `@unchecked`
  without adding real Sendable safety.
- **`#if DEBUG`** — avoid for security-relevant warnings. use unconditional
  `Logger.warning()` instead so production builds also see the warning.
- **`defer { txnAbort }` after `txnCommit`** — aborting a committed LMDB
  transaction crashes with SIGTRAP. not applicable here (no LMDB), but worth
  noting for future database work.

## related projects

- `arc-agent` — ARC agent (Swift agent/gateway with LMDB persistence, web UI, MCP)
- `swift-mcp` — MCP server framework for Swift (macros, Service Lifecycle)
- `rawdog` — lean binary encode/decode (alignment, endianness)
