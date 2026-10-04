# no-webui app template

a consumer app skeleton for the swiftui-for-web (`no-webui`) framework with an
island. this is the getting-started path — **zero manual verbs**:

```bash
swift build   # compiles the app natively AND cross-builds the island (WebUIAutobuildPlugin)
              # + auto-pins its budget into the work-dir ContinuumManifest.json (DX-3)
swift run App # serves the page (run the executable by product name)
```

## the islands in this app

`Sources/feed/` is a capability island: the generated `main.swift` names the
macro-produced adapter `feed.FeedIsland` (the `IslandRuntime<…>.run()` runtime
form); write the island logic in that directory. the once-per-app inert block
(research the framework path dependency + `WebUIAutobuildPlugin` on the app
target) means islands need **no manifest edits** — the plugin discovers them by
scanning `Sources/`.

## the one optional explicit check

when you want a belt-and-suspenders run of the whole island verification path —
build → wasm cross-build → measure/pin → the budget row — the **single** verb is
`verify` (the tool binary lives in the framework's `.build`):

```bash
<no-webui path>/.build/…/WebUIContinuumTool verify --package-dir . --framework <no-webui path>
```

it prints a per-stage verdict and fails on any budget breach. `wasm-island` is
internal (the framework's own ladder) — consumers never name it.

> the framework path in `Package.swift` (`__FRAMEWORK_PATH__`) is substituted
> when this template is copied into a home-dir project.
