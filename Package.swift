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
        .library(
            name: "WebUIBlocks",
            targets: ["WebUIBlocks"]
        ),
        .plugin(
            name: "WebUIIslandPlugin",
            targets: ["WebUIIslandPlugin"]
        ),
        .library(
            name: "WebUIIslandCore",
            targets: ["WebUIIslandCore"]
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
                .product(name: "Logging", package: "swift-log"),
                .product(name: "RAW", package: "rawdog"),
                .product(name: "RAW_sha256", package: "rawdog"),
                .product(name: "RAW_hmac", package: "rawdog"),
            ],
            plugins: [
                "WebUIAssetPlugin",
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

        // ── Asset Tool ───────────────────────────────────────────
        .executableTarget(
            name: "WebUIAssetTool"
        ),

        // ── Icon Tool (svg iconography generator + linter) ───────
        .executableTarget(
            name: "WebUIIconTool"
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
            ],
            resources: [.copy("orphan-class-baseline.txt")]
        ),
        .testTarget(
            name: "WebUIWasmToolTests",
            dependencies: [
                .product(name: "RAW_sha256", package: "rawdog"),
            ]
        ),
        .testTarget(
            name: "WebUIIslandCoreTests",
            dependencies: [
                "WebUIIslandCore",
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
    ]
)
