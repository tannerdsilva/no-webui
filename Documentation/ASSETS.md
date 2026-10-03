# shipping assets from a consumer package

a host's own css, js, fonts and wasm should reach a browser the way the framework's own
do: content-addressed, pre-compressed at build time, immutable-cached, and served by the
same server that serves the page. this article documents the toolkit that makes that true
for a *consumer* package, and the constraints — measured, not assumed — that fix its shape.

the toolkit is three products and one protocol:

| product | what it is | who calls it |
|---|---|---|
| `WebUIShippedAsset` (`WebUICore`) | the protocol generated code conforms to: bytes, address, content type, compressed variant | generated types; `WebUIAsset` |
| `WebUIBuild` | the host-side build library: gzip, the emitter, the manifest | a consumer's own tool; `WebUIAssetTool` |
| `WebUIEmbedPlugin` | the build-tool plugin: embeds a target's `Assets/webui-assets.json` on every build | a consumer's `Package.swift` |
| `WebUIAsset` (`WebUIServer`) | the runtime value: bytes + url + registration + cache policy from one source | a consumer's server |

## the constraints (why the api has this shape)

five swiftpm facts, measured in a two-package spike (`vendor` shipping a plugin product;
`consumer` attaching it) against 6.4.0, not read from documentation:

| probe | result |
|---|---|
| the plugin sees which package? | `context.package.directory` is the **consumer**; `target.directory` is its source dir; it can enumerate `Sources/` |
| can a plugin resolve an executable the consumer defines? | **no** — `Plugin does not have access to a tool named '…'` |
| can a plugin declare a consumer file as an input of its command? | **yes** |
| can a plugin target import a library, even its own package's? | **no** — that dependency is unsupported |
| can the vendored plugin's *tool* read a consumer's file? | **yes** |

two more facts of the same kind surfaced while implementing the toolkit:

- **the build library cannot link `WebUI`.** the framework's own asset plugin invokes
  `WebUIAssetTool`, which depends on `WebUIBuild`; a `WebUI` dependency there is a manifest
  cycle swiftpm refuses outright:
  `WebUI → WebUIAssetPlugin → WebUIAssetTool → WebUIBuild → WebUI`. the hash therefore comes
  from rawdog directly (see `Hash.swift` in `WebUIBuild`), and `WebUICore` — the other
  candidate — must stay rawdog-free, because the client build reaches `DesignToken` through
  `WebUIDesignSystemCore` precisely to avoid rawdog.
- **a build plugin compiles against the manifest's tools version, not the toolchain's.**
  this package is `swift-tools-version: 6.0`, so `Target.directoryURL` (6.1+) is
  unavailable; the plugin uses `target.directory`. when a plugin fails to compile, the
  build exits non-zero with *no* message — `swift build --verbose` is the instrument.

what follows, and nothing else does:

- **(a)+(b)** ⇒ the **file half is portable**: the framework's plugin can discover a
  consumer's assets, declare them as inputs and run the framework's own tool over them.
- **(b)+(d)** ⇒ the **render half is not**: no framework plugin can run a consumer's
  renderer, and no plugin can import a consumer's theme types. every consumer keeps exactly
  one executable tool — the framework's job is to make its body ~10 lines and its output a
  type the server already understands.
- **(e)** ⇒ a consumer with nothing to render (vendored css/js/fonts/wasm) needs no tool
  at all.

## recipe 1 — files: attach the plugin, write a manifest

for vendored css/js/fonts/wasm — anything that exists as files:

```swift
// Package.swift (the consumer)
.executableTarget(
    name: "MyApp",
    dependencies: [
        .product(name: "WebUI", package: "no-webui"),
        .product(name: "WebUIServer", package: "no-webui"),
    ],
    // the manifest and its assets are inputs to the plugin, not files for the compiler.
    exclude: ["Assets"],
    plugins: [
        .plugin(name: "WebUIEmbedPlugin", package: "no-webui"),
    ]
),
```

```
Sources/MyApp/Assets/webui-assets.json
Sources/MyApp/Assets/vendor/katex/katex.min.css
Sources/MyApp/Assets/vendor/katex/katex.min.js
Sources/MyApp/Assets/vendor/katex/fonts/*.woff2
```

```json
{
  "types": [
    { "name": "KaTeXCSS", "kind": "file", "path": "vendor/katex/katex.min.css",
      "contentType": "text/css; charset=utf-8", "minify": true, "prose": "check" },
    { "name": "KaTeXJS", "kind": "file", "path": "vendor/katex/katex.min.js",
      "contentType": "text/javascript" },
    { "name": "KaTeXFonts", "kind": "directory", "path": "vendor/katex/fonts",
      "extensions": [".woff2"], "contentType": "font/woff2",
      "ceilingBytes": 200000 }
  ]
}
```

every build runs the framework's tool over the manifest and compiles the result into the
target, so `KaTeXCSS`, `KaTeXJS` and `KaTeXFonts` exist as Swift types with no code written
by hand. editing a referenced file re-runs the command; the generated file is a build
product and is never committed.

server side, one value per asset:

```swift
let katexCSS = WebUIAsset(KaTeXCSS.self, path: "/ui/vendor/katex/katex.min.css")
let katexJS  = WebUIAsset(KaTeXJS.self,  path: "/ui/vendor/katex/katex.min.js")
let fonts = KaTeXFonts.filesBase64.map { name, base64 in
    WebUIServerAsset.bytes(
        "/ui/vendor/katex/fonts/" + name,
        Base64.decode(base64) ?? [],
        contentType: KaTeXFonts.contentType,
        cacheSeconds: 31536000, immutable: true
    )
}

let config = WebUIServerConfig(
    port: 9090,
    assets: [katexCSS.registration, katexJS.registration] + fonts
)
// …and the page links `katexCSS.url` / `katexJS.url`, never a hand-written path.
```

## recipe 2 — rendered Swift: a ten-line tool

for assets only the consumer can *render* (a theme sheet built from the consumer's own
types), SwiftPM forbids the framework from helping at build time — the consumer keeps one
executable, and it is a CLI over `WebUIBuild`:

```swift
import Foundation
import WebUIBuild
import MyTheme        // the consumer's own target — only this tool can import it

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let sheet = MyTheme.stylesheet()      // the render is the consumer's
let receipt = try WebUIAssetBuilder.emit(
    shipped: sheet,
    typeName: "MySheet",
    options: .init(minify: true, prose: .check, contentType: "text/css; charset=utf-8"),
    to: output
)
print("emitted \(receipt.typeName): \(receipt.bytes) bytes, \(receipt.gzipBytes ?? 0) gz, sha \(receipt.stamp)")
```

…wired from a small plugin of the consumer's own (its declared tool dependency is what
lets it run), or run by hand in CI. the emitted type is served exactly like a manifest
type: `WebUIAsset(MySheet.self, path: "/ui/style.css")`.

## the manifest

`<target.directory>/Assets/webui-assets.json`. one file per target — SwiftPM cannot
parameterize a plugin, so the manifest *is* the lever; a target that needs two should
attach the plugin twice under different directories.

| key | applies to | meaning |
|---|---|---|
| `name` | all | the generated Swift type's name (validated as an identifier) |
| `kind` | all | `file`, `text` (inline payload) or `directory` |
| `path` | `file`, `directory` | relative to the manifest's own directory |
| `text` | `text` | the inline payload |
| `extensions` | `directory` | which file names to include, e.g. `[".woff2"]` |
| `contentType` | all | the served `Content-Type`; also decides the prose grammar |
| `minify` | all | run the framework's css minifier before embedding |
| `prose` | all | `off` (default) or `check` — refuse comments that would ship |
| `ceilingBytes` / `ceilingGzipBytes` | all | pinned ceilings, enforced at embed time |

unknown keys, unknown kinds, missing required fields, non-utf-8 text payloads and missing
paths are all build failures that name the entry — a typo must not ship a page that links an
asset nobody embedded.

a `directory` entry emits a name-keyed `filesBase64: [String: String]` bag, deliberately
*not* a `WebUIShippedAsset` conformance: a bag is not one servable asset, so it has no single
address, and pretending otherwise would make the stamp a lie.

the generated types can be embedded in other generated types (e.g. a catalog of catalogue
entries) by listing them as `text` entries.

## prose, minify and ceilings

- **`minify`** runs `minifyCSS` — the same minifier the framework's own sheet goes through.
  it strips `/* … */` comments and blank lines; it does not touch whitespace inside rules.
- **`prose: "check"`** runs `ProseGuard` over the payload *as it will ship* (after minify),
  and fails the build naming line and text. the guard is a comment grammar: css block
  comments and javascript `//`/`/* */`, with string/regex/template-literal awareness. its
  documented limit travels with it: a javascript regex literal whose body contains `//`
  (e.g. `/a\/\//`) is read as a comment and reported — build the pattern from a string when
  that comes up. a payload with no comment grammar (a font, an image) is not scanned.
- **ceilings** are enforced by the embed step itself, so a payload that outgrows its pin
  fails the build that would ship it. `swift package --disable-sandbox plugin budget` also
  reports one row per consumer entry (labelled by manifest) next to the framework's pinned
  surfaces, via the receipt the plugin writes.

## what the framework does not do

- **no runtime compression.** the framework links no compressor; every compressed variant is
  a build product. a build host without `gzip` produces `nil` variants and the server serves
  the raw bytes rather than nothing.
- **no cache invalidation.** the url carries the stamp, so a rebuilt asset is a different
  url and a year-long `immutable` cache is safe by construction.
- **no second address.** `WebUIAsset.url` (what a document links) and `WebUIAsset.registration`
  (what the server answers) derive from the same bytes; the server matches host assets after
  stripping the query, so registering a *stamped* path answers 404 for the whole asset — the
  failure is pinned as a test, not a comment.