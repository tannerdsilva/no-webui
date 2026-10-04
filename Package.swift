// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "no-webui",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "WebUI",
            targets: ["WebUI"]
        ),
        .library(
            name: "WebUICore",
            targets: ["WebUICore"]
        ),
        .library(
            name: "WebUIDesignSystem",
            targets: ["WebUIDesignSystem"]
        ),
        .library(
            name: "WebUIChart",
            targets: ["WebUIChart"]
        ),
        .library(
            name: "WebUIAuth",
            targets: ["WebUIAuth"]
        ),
        .library(
            name: "WebUIDesignSystemCore",
            targets: ["WebUIDesignSystemCore"]
        ),
        .library(
            name: "WebUIServer",
            targets: ["WebUIServer"]
        ),
        // the host-side build library: gzip, generated-source emission and the asset
        // manifest, shared by the framework's own tool and a consumer's tool (a plugin
        // cannot import a library, so the plugin ships this and invokes a tool).
        .library(
            name: "WebUIBuild",
            targets: ["WebUIBuild"]
        ),
        .library(
            name: "WebUIBlocks",
            targets: ["WebUIBlocks"]
        ),
        .plugin(
            name: "WebUIIslandPlugin",
            targets: ["WebUIIslandPlugin"]
        ),
        // dx-5: the autobuild plugin a consumer attaches to its own target —
        // a plain `swift build` then cross-builds the real island graph via
        // direct swiftc (no nested SwiftPM). see Plugins/WebUIAutobuildPlugin.
        .plugin(
            name: "WebUIAutobuildPlugin",
            targets: ["WebUIAutobuildPlugin"]
        ),
        // dx-2: the scaffold command plugin — appends island product+target
        // entries + generates the 3-line runtime-form main for an existing
        // app. see Plugins/WebUIScaffoldPlugin.
        .plugin(
            name: "WebUIScaffoldPlugin",
            targets: ["WebUIScaffoldPlugin"]
        ),
        // a consumer attaches this plugin and ships an `Assets/webui-assets.json`; the
        // plugin runs the framework's tool over it on every build.
        .plugin(
            name: "WebUIEmbedPlugin",
            targets: ["WebUIEmbedPlugin"]
        ),
        .library(
            name: "WebUIIslandCore",
            targets: ["WebUIIslandCore"]
        ),
        // the zero-dep leaf, exposed for consumer islands that import it
        // directly alongside WebUIIslandCore (dx-5 consumer island mains).
        .library(
            name: "WebUISharedCore",
            targets: ["WebUISharedCore"]
        ),
        .executable(
            name: "WebUIExample",
            targets: ["WebUIExample"]
        ),
        .executable(
            name: "WebUIAuthExample",
            targets: ["WebUIAuthExample"]
        ),
        .executable(
            name: "WebUIShowcase",
            targets: ["WebUIShowcase"]
        ),
        .executable(
            name: "WebUISmokeTest",
            targets: ["WebUISmokeTest"]
        ),
        .executable(
            name: "WebUIShowcaseServer",
            targets: ["WebUIShowcaseServer"]
        ),
.executable(
            name: "WebUIBench",
            targets: ["WebUIBench"]
        ),
        .executable(
            name: "WebUIContinuumTool",
            targets: ["WebUIContinuumTool"]
        ),
        // the stateful probe capability island (DESKTOP_GRADE t2.5) — built
        // for wasm via the wasm-island plugin; the host product is inert.
        .executable(
            name: "WebUIProbeIsland",
            targets: ["WebUIProbeIsland"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", "1.0.0"..<"2.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", "2.0.0"..<"3.0.0"),
        // published and tagged 22.0.0 (2026-09); resolves by the pinned
        // revision in Package.resolved.
        .package(url: "https://github.com/tannerdsilva/rawdog.git", "22.0.0"..<"23.0.0"),
        // swift-syntax for the @Theme macro implementation (603.x matches the
        // 6.3 toolchain line).
        .package(url: "https://github.com/apple/swift-syntax.git", "603.0.0"..<"604.0.0"),
        // swift-service-lifecycle: hosts `WebUIServer` inside a `ServiceGroup`
        // (`WebUIServerService`), so a long-lived server has ordered startup
        // and graceful shutdown instead of an ad-hoc process lifecycle.
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", "2.6.0"..<"3.0.0"),
    ],
    targets: [

        // ── Web UI Framework ─────────────────────────────────────
        // the zero-dep leaf. it still needs libm on linux: `Double.rounded()`
        // lowers to a plain `round` call, and an island product pulls in no
        // other target that would bring libm along. apple platforms get their
        // math from libSystem, so the setting is linux-only.
        .target(
            name: "WebUISharedCore",
            linkerSettings: [
                .linkedLibrary("m", .when(platforms: [.linux])),
            ]
        ),
        .target(
            name: "WebUICore",
            dependencies: [
                "WebUISharedCore",
                .product(name: "Logging", package: "swift-log"),
            ],
            plugins: [
                "WebUIIconPlugin",
            ]
        ),
        .target(
            name: "WebUI",
            dependencies: [
                "WebUICore",
                "WebUIContinuumMacros",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "RAW", package: "rawdog"),
                .product(name: "RAW_sha256", package: "rawdog"),
                .product(name: "RAW_hmac", package: "rawdog"),
            ],
            plugins: [
                "WebUIAssetPlugin",
                "WebUIContinuumPlugin",
            ]
        ),
        // the capability-island core: same-swift logic that compiles to a
        // small standalone wasm module (next architecture d3). libraries
        // here must stay foundation-free — they build for wasm32-wasi.
        // deliberately depends only on the zero-dep leaf, so island builds
        // never compile swift-log (not embedded-compatible).
        .target(
            name: "WebUIIslandCore",
            dependencies: [
                "WebUISharedCore",
            ]
        ),
        .executableTarget(
            name: "WebUIValidateIsland",
            dependencies: [
                "WebUIIslandCore",
                "WebUISharedCore",
            ]
        ),
        .executableTarget(
            name: "WebUIProbeIsland",
            dependencies: [
                "WebUIIslandCore",
                "WebUISharedCore",
            ]
        ),
        .target(
            name: "WebUISmokeShared",
            dependencies: [
                "WebUICore",
            ]
        ),
        // the full showcase page, shared between the static generator
        // (WebUIShowcase) and the always-on showcase server.
        .target(
            name: "WebUIShowcaseContent",
            dependencies: [
                "WebUI",
                "WebUIDesignSystem",
                "WebUIChart",
            ]
        ),
        .target(
            name: "WebUIDesignSystemCore",
            dependencies: [
                "WebUICore",
                .product(name: "Logging", package: "swift-log"),
            ],
            plugins: [
                "WebUIAssetPlugin",
            ]
        ),
        .target(
            name: "WebUIDesignSystem",
            dependencies: [
                "WebUIDesignSystemCore",
                "WebUI",
                "WebUIDesignSystemMacros",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "WebUIChart",
            dependencies: [
                "WebUICore",
            ]
        ),
        .target(
            name: "WebUIServer",
            dependencies: [
                "WebUI",
                "WebUIDesignSystem",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ]
        ),
        .target(
            name: "WebUIAuth",
            dependencies: [
                "WebUI",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "RAW", package: "rawdog"),
                .product(name: "RAW_sha256", package: "rawdog"),
                .product(name: "RAW_argon2", package: "rawdog"),
            ]
        ),

        // ── Asset Build Library (host-side) ──────────────────────
        // the logic the framework's asset tool and a consumer's tool share, promoted out
        // of `WebUIAssetTool` so there is one implementation of gzip, emission and the
        // manifest. host-only by construction: it may import Foundation and links WebUI
        // (for `SHA256`) — the client never sees any of it.
        .target(
            name: "WebUIBuild",
            dependencies: [
                // sha-256 comes from rawdog directly, NOT through WebUI: WebUI's own asset
                // plugin invokes `WebUIAssetTool`, which depends on this library, so a WebUI
                // dependency here is a manifest cycle SwiftPM refuses. WebUICore — the other
                // candidate — must stay rawdog-free, because the client build reaches
                // `DesignToken` through it precisely to avoid rawdog. see `Hash.swift`.
                .product(name: "RAW", package: "rawdog"),
                .product(name: "RAW_sha256", package: "rawdog"),
                // the minifier and the prose guard live here (`ProseGuard` is package-level,
                // which is exactly why this library — not a plugin — is where a consumer's
                // tool meets them).
                .target(name: "WebUICore"),
            ]
        ),

        // ── Asset Tool ───────────────────────────────────────────
        .executableTarget(
            name: "WebUIAssetTool",
            dependencies: [
                // the minifier and the layout rules live in WebUICore, so the
                // minified sheet is produced at BUILD time (and therefore
                // compressible at build time — the runtime has no compressor).
                .target(name: "WebUICore"),
                // the gzip/emit internals live in WebUIBuild; the tool is a CLI over them.
                .target(name: "WebUIBuild"),
            ]
        ),

        // ── Icon Tool (svg iconography generator + linter) ───────
        .executableTarget(
            name: "WebUIIconTool"
        ),

        // ── Continuum Tool (class inventory + build lint + served manifest, d1/d2) ──
        .executableTarget(
            name: "WebUIContinuumTool",
            dependencies: [
                // the served, content-addressed engine slice rides the same
                // WebUIAssetBuilder emitter as the css/js assets — one
                // implementation of stamping, gzip and the prose gate.
                .target(name: "WebUIBuild"),
            ]
        ),

        // ── Wasm Tool (validates + hashes the prebuilt client artifact) ──
        .executableTarget(
            name: "WebUIWasmTool",
            dependencies: [
                .product(name: "RAW_sha256", package: "rawdog"),
            ]
        ),

        // ── @Theme Macro ────────────────────────────────────────
        .macro(
            name: "WebUIDesignSystemMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // ── @HotView / @HotClass Macros (the continuum surface) ─
        // host-compiled compiler plugin (swift-syntax, already vendored above).
        // its declarations live inert in `WebUI`; the implementation must never
        // enter a wasm-compiled chain — a compiler plugin cannot cross-build.
        .macro(
            name: "WebUIContinuumMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // ── Example ──────────────────────────────────────────────
        .executableTarget(
            name: "WebUIExample",
            dependencies: [
                "WebUI",
                "WebUIDesignSystem",
                "WebUIServer",
            ]
        ),
        .executableTarget(
            name: "WebUIAuthExample",
            dependencies: [
                "WebUI",
                "WebUIDesignSystem",
                "WebUIAuth",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ]
        ),
        // ── Bench host (desktop-grade measurement fixtures, d0) ──
        .executableTarget(
            name: "WebUIBench",
            dependencies: [
                "WebUI",
                "WebUIChart",
                "WebUICore",
                "WebUIDesignSystem",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ]
        ),

        // ── Showcase ─────────────────────────────────────────────
        .executableTarget(
            name: "WebUIShowcase",
            dependencies: [
                "WebUI",
                "WebUIDesignSystem",
                "WebUIChart",
                "WebUIShowcaseContent",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
            ]
        ),

        // ── Smoke/demo server (hosted by the serve/gate plugins) ──
        .executableTarget(
            name: "WebUISmokeTest",
            dependencies: [
                "WebUI",
                "WebUIDesignSystem",
                "WebUIChart",
                "WebUISmokeShared",
                "WebUIBlocks",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ],
            // `Assets/` is consumed by `WebUIEmbedPlugin`, not compiled: excluding it keeps
            // swiftpm from warning about files it does not know how to handle (the plugin
            // reads them through its own context, which exclusion does not affect).
            exclude: ["Assets"],
            plugins: [
                "WebUIEmbedPlugin",
            ]
        ),

        // ── Live showcase server (serves the full showcase, swift-generated) ──
        .executableTarget(
            name: "WebUIShowcaseServer",
            dependencies: [
                "WebUI",
                "WebUIDesignSystem",
                "WebUIChart",
                "WebUIShowcaseContent",
                "WebUIServer",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // ── Blocks: standalone page scaffolds, composed from the existing set ──
        .target(
            name: "WebUIBlocks",
            dependencies: [
                "WebUI",
                "WebUIDesignSystem",
                "WebUIChart",
            ]
        ),
        .executableTarget(
            name: "WebUIBlocksServer",
            dependencies: [
                "WebUI",
                "WebUIBlocks",
                "WebUIServer",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // ── Plugins ──────────────────────────────────────────────
        .plugin(
            name: "WebUIAssetPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "WebUIAssetTool"),
            ]
        ),
        .plugin(
            name: "WebUIIconPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "WebUIIconTool"),
            ]
        ),
        // the static half of the continuum class machinery: scans the
        // design-system core sources every build and emits
        // `Continuum+Generated.swift` into the WebUI target.
        .plugin(
            name: "WebUIContinuumPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "WebUIContinuumTool"),
            ]
        ),
        // the file half of the asset toolkit: a target shipping `Assets/webui-assets.json`
        // attaches this; the plugin runs the framework's own tool over the manifest.
        .plugin(
            name: "WebUIEmbedPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "WebUIAssetTool"),
            ]
        ),
        .plugin(
            name: "WebUIBudgetPlugin",
            capability: .command(
                intent: .custom(
                    verb: "budget",
                    description: "Fail when any shipped surface (engine, design-system sheet, shell, island artifact) exceeds its pinned size ceiling. Read-only; no sandbox flag needed."
                )
            )
        ),
        .plugin(
            name: "WebUIIslandPlugin",
            capability: .command(
                intent: .custom(
                    verb: "wasm-island",
                    description: "Cross-build a capability island product (e.g. WebUIValidateIsland) with the wasm SDK into .build/wasm-island-scratch, then copies the stripped artifact to .build/out/Products/… (requires --disable-sandbox)."
                )
            ),
            dependencies: [
                .target(name: "WebUIWasmTool"),
            ]
        ),
        // dx-5 build-tool plugin: the cross-build runs INSIDE a plain
        // `swift build` (the developer's default command, no flags) via the
        // framework's WebUIContinuumTool `wasm-cross` verb. the command
        // declares the island sources as inputs and the artifact as output,
        // so warm builds are llbuild-skipped and a source edit invalidates.
        .plugin(
            name: "WebUIAutobuildPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "WebUIContinuumTool"),
            ]
        ),
        // dx-2 scaffold command plugin: `swift package --disable-sandbox plugin
        // scaffold` — append-only Package.swift edits (product+target entries /
        // the once-per-app bootstrap block) + the generated island main.
        .plugin(
            name: "WebUIScaffoldPlugin",
            capability: .command(
                intent: .custom(
                    verb: "scaffold",
                    description: "Append an island (product + executableTarget + the 3-line runtime-form main) or bootstrap an existing app with the once-per-app continuum block (path dep + WebUIAutobuildPlugin). Append-only anchors; --print previews without writing."
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "append island product+target entries to Package.swift and write Sources/<Name>/main.swift (DX-2 scaffold)"),
                ]
            ),
            dependencies: [
                .target(name: "WebUIContinuumTool"),
            ]
        ),
        // dx-8 verify command plugin: `swift package --disable-sandbox plugin
        // verify` runs the FULL island verification path against this package —
        // host build -> wasm cross-build -> DX-3 measure/pin -> the
        // WebUIBudgetPlugin budget row (one budget path). the consolidated
        // consumer-facing island-verification verb (`wasm-island` stays
        // internal); the same surface is usable from a consumer app via the
        // tool directly (`webui-continuum verify --package-dir <app>
        // --framework <no-webui path>`).
        .plugin(
            name: "WebUIVerifyPlugin",
            capability: .command(
                intent: .custom(
                    verb: "verify",
                    description: "Run the full island verification path (host build -> wasm cross-build -> DX-3 measure/auto-pin -> the budget row) and print a per-stage verdict. Belt-and-suspenders: a plain `swift build` already cross-builds + auto-pins the islands (zero manual verbs)."
                )
            ),
            dependencies: [
                .target(name: "WebUIContinuumTool"),
            ]
        ),
        .plugin(
            name: "WebUIShowcasePlugin",
            capability: .command(
                intent: .custom(
                    verb: "showcase",
                    description: "Generate the WebUI Showcase HTML page into designer/previews/."
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "write designer/previews/showcase.html"),
                ]
            ),
            dependencies: [
                .target(name: "WebUIShowcase"),
            ]
        ),
        .plugin(
            name: "WebUIServePlugin",
            capability: .command(
                intent: .custom(
                    verb: "serve",
                    description: "Host the smoke/demo server on :9123 (requires --disable-sandbox)."
                )
            ),
            dependencies: [
                .target(name: "WebUISmokeTest"),
            ]
        ),
        .plugin(
            name: "WebUIShowcaseServePlugin",
            capability: .command(
                intent: .custom(
                    verb: "showcase-serve",
                    description: "Host the live swift-generated showcase server on :9092 (requires --disable-sandbox)."
                )
            ),
            dependencies: [
                .target(name: "WebUIShowcaseServer"),
            ]
        ),
        .plugin(
            name: "WebUISmokePlugin",
            capability: .command(
                intent: .custom(
                    verb: "smoke",
                    description: "Self-contained smoke gate: hosts the server, checks it, tears down."
                )
            ),
            dependencies: [
                .target(name: "WebUISmokeTest"),
            ]
        ),
        .plugin(
            name: "WebUIFullstackSmokePlugin",
            capability: .command(
                intent: .custom(
                    verb: "fullstack-smoke",
                    description: "Self-contained full-stack gate: hosts the server, drives live WS round-trips, tears down."
                )
            ),
            dependencies: [
                .target(name: "WebUISmokeTest"),
            ]
        ),
        .plugin(
            name: "WebUIProbePlugin",
            capability: .command(
                intent: .custom(
                    verb: "probe",
                    description: "Check whether a port is in use."
                ),
                permissions: [
                    .allowNetworkConnections(scope: .local(ports: [9123]),
                                              reason: "connect-probe port 9123"),
                ]
            ),
            dependencies: []
        ),

        // ── Tests ────────────────────────────────────────────────
        .testTarget(
            name: "WebUITests",
            dependencies: [
                "WebUI",
                "WebUISharedCore",
                "WebUIDesignSystem",
                "WebUIChart",
                "WebUIAuth",
                "WebUIShowcaseContent",
                "WebUIServer",
                "WebUIBlocks",
                // the surface pins reference the toolkit's public types (STABILITY.md
                // change discipline).
                "WebUIBuild",
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
            ],
            resources: [
                .copy("orphan-class-baseline.txt"),
                // the W0-captured smoke island regions — the byte-identity
                // target of WebUIIslandTests (CONTINUUM_DX DX-4a).
                .copy("Fixtures/dx-w0-island-regions.html"),
            ]
        ),
        .testTarget(
            name: "WebUIWasmToolTests",
            dependencies: [
                .product(name: "RAW_sha256", package: "rawdog"),
            ]
        ),
        // the asset tool carries the token surface (T9 pruning), so its pruner is
        // unit-tested in-process and its CLI is exercised as a subprocess.
        .testTarget(
            name: "WebUIAssetToolTests",
            dependencies: [
                "WebUIAssetTool",
            ]
        ),
        .testTarget(
            name: "WebUIContinuumToolTests",
            dependencies: [
                "WebUIContinuumTool",
            ]
        ),
        .testTarget(
            name: "WebUIBuildTests",
            dependencies: [
                "WebUIBuild",
            ]
        ),
        .testTarget(
            name: "WebUIIslandCoreTests",
            dependencies: [
                "WebUIIslandCore",
                "WebUISharedCore",
            ]
        ),
        // the seam vocabulary + the hand-rolled scalar-clean op-stream codec
        // (record format v1, DESKTOP_GRADE §t2.3) — round-trips + edge cases.
        .testTarget(
            name: "WebUISharedCoreTests",
            dependencies: [
                "WebUISharedCore",
            ]
        ),
        .testTarget(
            name: "WebUIAuthTests",
            dependencies: [
                "WebUIAuth",
                "WebUI",
            ]
        ),
        .testTarget(
            name: "WebUIDesignSystemMacroTests",
            dependencies: [
                "WebUIDesignSystem",
                "WebUIDesignSystemMacros",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        // the continuum surface expansion suite: string-based expansion tests only
        // in wave 1 — generated members are asserted by name/shape but never
        // compiled (lane C's vocabulary is unmerged). the compiled end-to-end
        // fixture and the hand-written-equivalent rule join in wave 2.
        .testTarget(
            name: "WebUIContinuumMacroTests",
            dependencies: [
                "WebUI",
                "WebUIContinuumMacros",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
    ]
)
