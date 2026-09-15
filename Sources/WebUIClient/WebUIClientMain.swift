import WebUIClientRuntime
import WebUISmokeShared

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
	}
}
