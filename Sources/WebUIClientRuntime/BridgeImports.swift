import WebUICore

// the hand-rolled bridge ABI (trajectory w§3.2 + harness v2): the wasm
// module's `env` imports, as file-level globals (`@_extern` requires
// globals). every import is referenced at boot (WebUIBridge.install) so the
// full surface stays linked and pinned — the chamber must implement all or
// instantiation fails. the capability imports (focus, clipboard, broadcast)
// are no-ops in the chamber unless the boot config grants the capability,
// so the import surface is also the permission surface.

#if os(WASI)
@_extern(wasm, module: "env", name: "setInnerHTML")
private func setInnerHTML(_ idPtr: UnsafeRawPointer?, _ idLen: Int, _ htmlPtr: UnsafeRawPointer?, _ htmlLen: Int)

@_extern(wasm, module: "env", name: "removeElement")
private func removeElement(_ idPtr: UnsafeRawPointer?, _ idLen: Int)

@_extern(wasm, module: "env", name: "getElementValue")
private func getElementValue(_ idPtr: UnsafeRawPointer?, _ idLen: Int, _ outPtr: UnsafeMutableRawPointer?, _ outLen: Int) -> Int

@_extern(wasm, module: "env", name: "setElementValue")
private func setElementValue(_ idPtr: UnsafeRawPointer?, _ idLen: Int, _ valPtr: UnsafeRawPointer?, _ valLen: Int)

@_extern(wasm, module: "env", name: "setCustomValidity")
private func setCustomValidity(_ idPtr: UnsafeRawPointer?, _ idLen: Int, _ msgPtr: UnsafeRawPointer?, _ msgLen: Int)

@_extern(wasm, module: "env", name: "wsSend")
private func wsSend(_ bytesPtr: UnsafeRawPointer?, _ len: Int)

@_extern(wasm, module: "env", name: "storageGet")
func storageGet(_ keyPtr: UnsafeRawPointer?, _ keyLen: Int, _ outPtr: UnsafeMutableRawPointer?, _ outLen: Int) -> Int

@_extern(wasm, module: "env", name: "storageSet")
func storageSet(_ keyPtr: UnsafeRawPointer?, _ keyLen: Int, _ valPtr: UnsafeRawPointer?, _ valLen: Int)

@_extern(wasm, module: "env", name: "focusElement")
private func focusElement(_ idPtr: UnsafeRawPointer?, _ idLen: Int)

@_extern(wasm, module: "env", name: "clipboardWrite")
private func clipboardWrite(_ textPtr: UnsafeRawPointer?, _ textLen: Int)

@_extern(wasm, module: "env", name: "broadcastSubscribe")
private func broadcastSubscribe(_ channelPtr: UnsafeRawPointer?, _ channelLen: Int)

@_extern(wasm, module: "env", name: "broadcastPublish")
private func broadcastPublish(_ channelPtr: UnsafeRawPointer?, _ channelLen: Int, _ dataPtr: UnsafeRawPointer?, _ dataLen: Int)

@_extern(wasm, module: "env", name: "fullscreenElement")
private func fullscreenElement(_ idPtr: UnsafeRawPointer?, _ idLen: Int)

@_extern(wasm, module: "env", name: "mediaQuery")
private func mediaQuery(_ queryPtr: UnsafeRawPointer?, _ queryLen: Int) -> Bool

@_extern(wasm, module: "env", name: "now")
private func now() -> Double

@_extern(wasm, module: "env", name: "log")
private func log(_ level: Int, _ msgPtr: UnsafeRawPointer?, _ msgLen: Int)
#endif

/// the boot seam that keeps every bridge import linked and referenced.
public enum WebUIBridge {
	/// touch every import with benign arguments so the surface stays linked
	/// and pinned (p2-t4: the chamber must implement the full set). each
	/// import guards `len > 0` before touching memory, so the no-op calls are
	/// safe. called once from `webui_init`.
	public static func install() {
#if os(WASI)
		setInnerHTML(nil, 0, nil, 0)
		removeElement(nil, 0)
		let scratch = UnsafeMutableRawPointer.allocate(byteCount: 256, alignment: 16)
		defer { scratch.deallocate() }
		_ = getElementValue(nil, 0, scratch, 256)
		setElementValue(nil, 0, nil, 0)
		setCustomValidity(nil, 0, nil, 0)
		wsSend(nil, 0)
		_ = storageGet(nil, 0, scratch, 256)
		storageSet(nil, 0, nil, 0)
		WebUIClientRuntime.focusElement(nil, 0)
		WebUIClientRuntime.clipboardWrite(nil, 0)
		WebUIClientRuntime.broadcastSubscribe(nil, 0)
		WebUIClientRuntime.broadcastPublish(nil, 0, nil, 0)
		WebUIClientRuntime.fullscreenElement(nil, 0)
		_ = WebUIClientRuntime.mediaQuery(nil, 0)
		_ = now()
		let message = [UInt8]("webui ready".utf8)
		message.withUnsafeBytes { raw in
			log(1, raw.baseAddress, raw.count)
		}
#endif
	}

	/// move browser focus to the element with `id` (capability: `focus`).
	/// no-op outside wasm or when the capability is not granted.
	public static func focusElement(_ id: String) {
#if os(WASI)
		let bytes = [UInt8](id.utf8)
		bytes.withUnsafeBytes { raw in
			WebUIClientRuntime.focusElement(raw.baseAddress, raw.count)
		}
#endif
	}

	/// write `text` to the system clipboard (capability: `clipboard`).
	public static func writeClipboard(_ text: String) {
#if os(WASI)
		let bytes = [UInt8](text.utf8)
		bytes.withUnsafeBytes { raw in
			WebUIClientRuntime.clipboardWrite(raw.baseAddress, raw.count)
		}
#endif
	}

	/// subscribe the chamber to a broadcast channel (capability: `broadcast`).
	/// inbound messages re-enter through `webuiBroadcast` /
	/// `ClientRuntime.handleBroadcast`.
	public static func subscribeBroadcast(_ channel: String) {
#if os(WASI)
		let bytes = [UInt8](channel.utf8)
		bytes.withUnsafeBytes { raw in
			WebUIClientRuntime.broadcastSubscribe(raw.baseAddress, raw.count)
		}
#endif
	}

	/// publish a payload string on a broadcast channel (capability:
	/// `broadcast`). local echoes do not self-deliver (BroadcastChannel
	/// semantics); other tabs receive it.
	public static func publishBroadcast(_ channel: String, _ payload: String) {
#if os(WASI)
		let ch = [UInt8](channel.utf8)
		let data = [UInt8](payload.utf8)
		ch.withUnsafeBytes { chRaw in
			data.withUnsafeBytes { dataRaw in
				WebUIClientRuntime.broadcastPublish(chRaw.baseAddress, chRaw.count, dataRaw.baseAddress, dataRaw.count)
			}
		}
#endif
	}

	/// request fullscreen on the element with `id` (capability: `fullscreen`).
	public static func fullscreenElement(_ id: String) {
#if os(WASI)
		let bytes = [UInt8](id.utf8)
		bytes.withUnsafeBytes { raw in
			WebUIClientRuntime.fullscreenElement(raw.baseAddress, raw.count)
		}
#endif
	}

	/// evaluate a media query in the browser (capability: `media`). returns
	/// false on the host / outside wasm.
	public static func mediaQuery(_ query: String) -> Bool {
#if os(WASI)
		let bytes = [UInt8](query.utf8)
		return bytes.withUnsafeBytes { raw in
			WebUIClientRuntime.mediaQuery(raw.baseAddress, raw.count)
		}
#else
		return false
#endif
	}
}
