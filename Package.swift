// swift-tools-version: 6.0
import PackageDescription

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
        // rawdog resolves to the same local rawdog-v21 tree QuickLMDB uses
        // (they are mid-flip from 20.x; the local tree is exactly tag 21.0.0).
        // keeping both manifests on one path gives the graph a single rawdog
        // identity — mixing a URL dep here with QuickLMDB's path dep makes
        // swiftpm see two packages exporting the same targets. flip both to
        // `.package(url: "https://github.com/tannerdsilva/rawdog.git", from: "21.0.0")`
        // in the same commit once QuickLMDB lands its own flip.
        .package(name: "rawdog", path: "../rawdog-v21"),
        // TEMP local path while the rawdog21 branch/tag is unpublished; flip to
        // .package(url: "https://github.com/tannerdsilva/QuickLMDB.git", branch: "rawdog21")
        // then `from: <tag>` once pushed (see Documentation/IMPLEMENTATION_PLAN.md)
        .package(name: "QuickLMDB", path: "../QuickLMDB"),
    ],
    targets: [

        // ── Web UI Framework ─────────────────────────────────────
        .target(
            name: "WebUI",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "RAW", package: "rawdog"),
                .product(name: "RAW_sha256", package: "rawdog"),
                .product(name: "RAW_hmac", package: "rawdog"),
            ],
            plugins: [
                "WebUIAssetPlugin",
                "WebUIIconPlugin",
            ]
        ),
        .target(
            name: "WebUIDesignSystem",
            dependencies: [
                "WebUI",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "WebUIChart",
            dependencies: [
                "WebUI",
            ]
        ),
        .target(
            name: "WebUIAuth",
            dependencies: [
                "WebUI",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "QuickLMDB", package: "QuickLMDB"),
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
            name: "WebUIAuthTests",
            dependencies: [
                "WebUIAuth",
                "WebUI",
            ]
        ),
    ]
)
