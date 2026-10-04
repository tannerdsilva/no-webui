// swift-tools-version: 6.0
import PackageDescription

// the once-per-app continuum block (CONTINUUM_DX §0.3 / §2.5). this is the
// STATIC, inert block a new app starts from and an existing app bootstraps
// once: the framework dependency + the WebUIAutobuildPlugin on the page
// target + one island executable target. it never changes per island — the
// autobuild plugin scans the package, so afterwards islands need no manifest
// edits (candidate (c) is dead; this is the §0.3 Package.swift frontier,
// accepted by the owner).
//
// `__FRAMEWORK_PATH__` is substituted by designer/dx-acceptance.mjs at prep
// time (the acceptance runs in a home-directory project, ~/dx-accept, and the
// framework checkout location is machine-specific).
let package = Package(
    name: "dx-accept",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "App", targets: ["App"]),
        .executable(name: "feed", targets: ["feed"]),
    ],
    dependencies: [
        .package(name: "no-webui", path: "__FRAMEWORK_PATH__"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "WebUI", package: "no-webui"),
                .product(name: "WebUIDesignSystem", package: "no-webui"),
                .product(name: "WebUIServer", package: "no-webui"),
            ],
            plugins: [.plugin(name: "WebUIAutobuildPlugin", package: "no-webui")]
        ),
        .executableTarget(
            name: "feed",
            dependencies: [
                .product(name: "WebUIIslandCore", package: "no-webui"),
                .product(name: "WebUISharedCore", package: "no-webui"),
            ]
        ),
    ]
)
