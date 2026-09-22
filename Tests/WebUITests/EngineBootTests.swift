import Testing
import Foundation
import WebUI

// MARK: - Engine boot contract (next-architecture p0)

@Test("engine flavor emits the engine head contract (config meta + engine script)")
func engineFlavorHeadMarkup() {
    let boot = ClientBoot(wasmURL: "/__assets/app.abc.wasm", config: RuntimeConfig(wsUrl: "ws://example.com/ws"), flavor: .engine)
    let head = boot.headMarkup()
    #expect(head.contains("<meta name=\"webui-config\""))
    #expect(head.contains("ws://example.com/ws"))
    #expect(head.contains("<script src=\"/ui/webui-engine.js\"></script>"))
    #expect(!head.contains("webui-wasm"))
    #expect(!head.contains("webui-client.js"))
}

@Test("engine head markup always carries a config meta so the meta-driven auto-boot fires")
func engineFlavorEmptyConfigMeta() {
    let head = ClientBoot(wasmURL: "/x.wasm", flavor: .engine).headMarkup()
    #expect(head.contains("content=\"{}\""))
}

@Test("wasm flavor keeps the wasm contract byte-identical")
func wasmFlavorHeadMarkup() {
    let head = ClientBoot(wasmURL: "/__assets/app.abc.wasm", config: RuntimeConfig(renderToken: "t")).headMarkup()
    #expect(head.contains("<meta name=\"webui-wasm\" content=\"/__assets/app.abc.wasm\">"))
    #expect(head.contains("<script src=\"/ui/webui-client.js\">"))
    #expect(head.contains("webui-config"))
    #expect(!head.contains("webui-engine"))
}

@Test("WebUIAssets.engine embeds the engine, comment-free")
func engineAssetEmbedded() {
    #expect(WebUIAssets.engine.contains("WebUIEngine"))
    #expect(WebUIAssets.engine.contains("createFragmentPatcher"))
    #expect(!WebUIAssets.engine.contains("/*"))
    #expect(!WebUIAssets.engine.contains("WebUIRuntime"))
}

@Test("WebUIAssets.shell embeds the offline shell, comment-free")
func shellAssetEmbedded() {
    #expect(WebUIAssets.shell.contains("webui-shell-v1"))
    #expect(WebUIAssets.shell.contains("clients.claim"))
    #expect(!WebUIAssets.shell.contains("/*"))
}
