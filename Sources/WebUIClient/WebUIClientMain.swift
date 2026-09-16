import WebUIClientRuntime
import WebUISmokeShared
import Synchronization

/// the in-page render brain: a wasi reactor (`_start` installs the runtime
/// wiring and returns — never `proc_exit`; all work happens through the
/// exported `webui_*` entries: P1 render prove-out, P2 handle_event).
@main
struct WebUIClient {
	static func main() {
		ClientExecutor.install()
		let args = CommandLine.arguments
		if args.contains("--verify-render") {
			// hydration probe: print exactly what the server's
			// --print-hydration-ssr emits so the gate can byte-diff the two.
			print(HydrationView().render())
			return
		}
		if args.contains("--verify-pump") {
			// executor probe: a spawned task must run to completion under one
			// pump cycle (the 6.4 cooperative global executor's drain).
			let flag = Mutex(false)
			Task { flag.withLock { $0 = true } }
			ClientExecutor.pump()
			print(flag.withLock { $0 } ? "PUMP OK" : "PUMP FAIL")
			return
		}
		if args.contains("--verify-event") {
			// resident-router probe: boot registers proof-inc as c0; a
			// synthesized click must dispatch through the pump and return the
			// counter fragment (c0 first registered → "c0").
			ClientRuntime.boot()
			let updates = ClientRuntime.handleEvent("{\"component\":\"c0\",\"event\":\"click\",\"data\":{}}")
			let html = updates.first?.html ?? "?"
			print("updates=\(updates.count) fragment=\(html)")
			print(html == "<div id=\"client-counter\" class=\"proof__value\">1</div>" ? "EVENT OK" : "EVENT FAIL")
			return
		}
	}
}
