import Logging
import Synchronization

// MARK: - RenderDiagnostics

/// framework warnings about a render that cannot work as written.
///
/// these name host-configuration facts, not per-request ones, so a latch keeps
/// each distinct warning to one line per process: a misconfigured page under load
/// cannot flood a log, and the one line it does get is the one that matters. the
/// alternative the framework shipped before was silence — a `405` with an empty
/// body and nothing anywhere to say why.
enum RenderDiagnostics {
    private static let warned = Mutex<Set<String>>([])

    /// emit `message` at most once per process, keyed by `key`.
    static func warnOnce(_ key: String, _ message: String) {
        let isFirst = warned.withLock { seen in
            seen.insert(key).inserted
        }
        guard isFirst else { return }
        Logger(label: "webui.render").warning("\(message)")
    }
}