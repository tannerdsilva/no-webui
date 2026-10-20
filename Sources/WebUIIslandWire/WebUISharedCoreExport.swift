// island-authoring seam: everything in the foundation-free leaf is visible to
// `import WebUIIslandWire` consumers. an island author works in `htmlEscape`,
// `JSONValue` and the render primitives without also naming the leaf — and,
// critically, without depending on `WebUICore`, which links swift-log and
// cannot join an embedded wasm build.
@_exported import WebUISharedCore