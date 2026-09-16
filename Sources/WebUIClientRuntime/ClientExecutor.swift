import WebUICore

/// the cooperative job pump for the 6.4 wasm runtime.
///
/// the swift runtime built with SWIFT_THREADING_NONE runs a cooperative global
/// executor: every job (`Task`, `async let`, task-group children) enqueues into
/// its internal priority queue, and nothing executes until the host drains it.
/// the blessed drain entry point (verified against the 6.4 runtime sources) is
/// `swift_task_donateThreadToGlobalExecutorUntil(condition, context)`, which
/// claims jobs via `swift_job_run(job, generic)` until the queue is empty. one
/// `pump()` call runs a spawned handler — and every continuation it awaits
/// (group children, yields, mailbox hops) — to quiescence. no hook installation
/// is required; the 6.4 executor owns the queue (the 6.2-era
/// `swift_task_enqueueGlobal_hook` fifo pattern is obsolete here).
public enum ClientExecutor {
#if os(WASI)
	private static let pumpCondition: @convention(c) (UnsafeMutableRawPointer?) -> Bool = { _ in false }

	@_silgen_name("swift_task_donateThreadToGlobalExecutorUntil")
	private static func donateThreadToGlobalExecutorUntil(
		_ condition: @convention(c) (UnsafeMutableRawPointer?) -> Bool,
		_ context: UnsafeMutableRawPointer?
	)
#endif

	/// drain the runtime job queue one cycle (until it quiesces). the browser
	/// chamber calls this via the exported `webui_pump` after every bridge
	/// entry; the always-false condition keeps the loop running and the
	/// executor returns on its own when the queue is empty. on the host this
	/// is a no-op (the platform's own executor runs).
	public static func pump() {
#if os(WASI)
		donateThreadToGlobalExecutorUntil(pumpCondition, nil)
#endif
	}

	/// boot seam — the 6.4 cooperative executor needs no hook wiring; retained
	/// so the reactor's install path is explicit.
	public static func install() {
		// no-op: the runtime drains through `pump()`
	}
}
