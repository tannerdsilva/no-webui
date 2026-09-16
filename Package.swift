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
        .target(
            name: "WebUICore",
            dependencies: [
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
        .target(
            name: "WebUIClientRuntime",
            dependencies: [
                "WebUICore",
                "WebUIDesignSystemCore",
                "WebUIChart",
            ],
            swiftSettings: [
                // the official sdk's wasm import primitive (@_extern(wasm, module:name:))
                .unsafeFlags(["-enable-experimental-feature", "Extern"]),
            ]
        ),
        .executableTarget(
            name: "WebUIClient",
            dependencies: [
                "WebUIClientRuntime",
                "WebUISmokeShared",
                "WebUIDesignSystemCore",
                "WebUIChart",
            ]
        ),
        .target(
            name: "WebUISmokeShared",
            dependencies: [
                "WebUICore",
            ]
        ),
        .target(
            name: "WebUIDesignSystemCore",
            dependencies: [
                "WebUICore",
                .product(name: "Logging", package: "swift-log"),
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
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
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
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
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
                "WebUIDesignSystem",
                "WebUIChart",
            ]
        ),
        .testTarget(
            name: "WebUIClientTests",
            dependencies: [
                "WebUIClientRuntime",
                "WebUICore",
                "WebUISmokeShared",
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
