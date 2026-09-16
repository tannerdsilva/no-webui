// server-layer seam: the design-system components live in the wasm-clean
// WebUIDesignSystemCore target; this re-export keeps `import WebUIDesignSystem`
// byte-identical for every consumer (the theme/document/assets stay here).
@_exported import WebUIDesignSystemCore
