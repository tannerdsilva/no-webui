import WebUIClientRuntime

/// the in-page render brain: a wasi reactor (`_start` installs the runtime
/// wiring and returns — never `proc_exit`; all work happens through the
/// exported `webui_*` entries: P1 render prove-out, P2 handle_event).
@main
struct WebUIClient {
	static func main() {
		ClientExecutor.install()
		// P1-T1: --verify-render flag path renders the shared smoke view
	}
}
