import WebUICore

// the hand-rolled bridge ABI (trajectory w§3.2): the 8 imports the wasm
// module declares from the chamber's `env` namespace, as file-level globals
// (`@_extern` requires globals). every import is referenced at boot
// (WebUIBridge.install) so the full surface stays linked and pinned in the
// module — the chamber must implement all 8 or instantiation fails; the
// boundary guards (len > 0 before dereference) are mirrored on the JS side.

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
		_ = now()
		let message = [UInt8]("webui ready".utf8)
		message.withUnsafeBytes { raw in
			log(1, raw.baseAddress, raw.count)
		}
#endif
	}
}
