import Testing
import Foundation
import WebUI

// MARK: - Engine boot contract (next-architecture p0)
//
// this file also covered the wasm flavor; that flavor was deleted with the
// monolith client (see NEXT_ARCHITECTURE.md) — the engine is the framework's
// client runtime, and `ClientBoot` now describes only that path.

@Test("the engine head contract is the config meta plus the engine script")
func engineHeadMarkup() {
	let boot = ClientBoot(config: RuntimeConfig(wsUrl: "ws://example.com/ws"))
	let head = boot.headMarkup()
	#expect(head.contains("<meta name=\"webui-config\""))
	#expect(head.contains("ws://example.com/ws"))
	#expect(head.contains("<script src=\"/ui/webui-engine.js\"></script>"))
	#expect(!head.contains("webui-wasm"))
	#expect(!head.contains("webui-client.js"))
}

@Test("the head markup always carries a config meta so the meta-driven auto-boot fires")
func engineEmptyConfigMeta() {
	let head = ClientBoot().headMarkup()
	#expect(head.contains("content=\"{}\""))
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