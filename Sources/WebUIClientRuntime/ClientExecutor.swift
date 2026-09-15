import WebUICore

/// the client executor owns the swift_task job FIFO and the pump loop.
/// in P2-T1 `install()` wires `swift_task_enqueueGlobal_hook` to capture jobs
/// into the FIFO and `webui_pump()` drains them on a budget; until then this
/// is a compiling placeholder that both hosts (native + wasm) link so the
/// reactor and its tests build from day one.
public enum ClientExecutor {
	/// install the host pump wiring. no-op until P2-T1 wires the runtime hook.
	public static func install() {
		// P2-T1: capture jobs into the FIFO; export webui_pump() -> Bool
	}
}
