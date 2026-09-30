import Foundation
import PackagePlugin

/// a shipped-surface budget breach is a gate failure, never a warning — the
/// numbers below are the reason "it is very fast" is a checked property rather
/// than a memory (plan d12 / E2).
struct BudgetError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// one pinned ceiling: what the artifact is, its raw bytes, its gzip bytes.
private struct Ceiling {
    let label: String
    let raw: Int
    let gz: Int?
}

@main
struct WebUIBudgetPlugin: CommandPlugin {

    /// ceilings are deliberately loose enough to absorb a copy edit and tight
    /// enough that a structural regression trips them. every number carries the
    /// measurement it came from so the next person can tell drift from noise.
    ///
    /// measured 2026-09-29 (pre-compression):
    ///   engine 42,440 raw · sheet 346,163 raw (working file; served minified is
    ///   ~308,930) · shell 1,514 raw · island 164 kb stripped.
    /// the sheet is measured as the WORKING file, which is larger than what ships,
    /// so this budget is conservative on purpose.
    private static let ceilings: [Ceiling] = [
        Ceiling(label: "webui-engine.js", raw: 48_000, gz: 18_000),
        Ceiling(label: "design-system.css", raw: 380_000, gz: 55_000),
        Ceiling(label: "webui-shell.js", raw: 4_000, gz: 2_000),
    ]

    /// a capability island is a per-capability artifact; the ceiling is per file,
    /// and absence is reported rather than failed (islands are opt-in, d3/d6).
    private static let islandCeiling = 200_000

    /// artifacts the architecture has retired. if one is still on disk it is a
    /// stale build product, not a shipped surface — reported so nobody ships it
    /// by accident, but not a breach (it cannot ship: `.build/out` is gitignored).
    /// `NEXT_ARCHITECTURE.md` §3 records the monolith as dropped from the default
    /// path; this list is where that decision becomes operational.
    private static let retiredArtifacts: Set<String> = ["WebUIClient.wasm"]

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let assets = context.package.directoryURL
            .appendingPathComponent("designer")
            .appendingPathComponent("assets")

        var breaches: [String] = []
        var rows: [(String, Int, String, String, String)] = []

        for ceiling in Self.ceilings {
            let url = assets.appendingPathComponent(ceiling.label)
            guard let data = FileManager.default.contents(atPath: url.path) else {
                breaches.append("\(ceiling.label): missing at \(url.path)")
                continue
            }
            let raw = data.count
            let gz = gzipSize(of: url)
            let rawVerdict = raw <= ceiling.raw ? "ok" : "OVER"
            if rawVerdict == "OVER" {
                breaches.append("\(ceiling.label): \(raw) raw bytes > \(ceiling.raw) pinned")
            }
            var gzVerdict = "—"
            if let gz, let limit = ceiling.gz {
                gzVerdict = gz <= limit ? "ok" : "OVER"
                if gzVerdict == "OVER" {
                    breaches.append("\(ceiling.label): \(gz) gzip bytes > \(limit) pinned")
                }
            }
            rows.append((
                ceiling.label,
                raw,
                gz.map(String.init) ?? "n/a",
                "\(rawVerdict)/\(gzVerdict)",
                "raw≤\(ceiling.raw) gz≤\(ceiling.gz.map(String.init) ?? "-")"
            ))
        }

        // islands: report every artifact, enforce the per-file ceiling on each.
        let islandDir = context.package.directoryURL
            .appendingPathComponent(".build")
            .appendingPathComponent("out")
            .appendingPathComponent("Products")
            .appendingPathComponent("Release-webassembly-wasm32")
        var islandRows: [(String, Int, String)] = []
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: islandDir, includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for entry in entries where entry.pathExtension == "wasm" {
                let size = (try? entry.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let name = entry.lastPathComponent
                let verdict: String
                if Self.retiredArtifacts.contains(name) {
                    verdict = "stale"
                } else if size <= Self.islandCeiling {
                    verdict = "ok"
                } else {
                    verdict = "OVER"
                    breaches.append("\(name): \(size) > \(Self.islandCeiling) pinned")
                }
                islandRows.append((name, size, verdict))
            }
        }

        // report. plain concatenation — never `String(format:)` with `%s`, because a
        // Swift String is not a C string and passing one is undefined behaviour (it
        // segfaulted this plugin on its first run).
        func pad(_ text: String, _ width: Int) -> String {
            text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
        }
        func padLeft(_ text: String, _ width: Int) -> String {
            text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
        }

        print("── webui shipped-surface budget ─────────────────────────────────")
        print("  " + pad("artifact", 20) + padLeft("raw", 10) + padLeft("gzip", 10)
              + "  " + pad("verdict", 12) + "pinned")
        for (label, raw, gz, verdict, pinned) in rows {
            print("  " + pad(label, 20) + padLeft(String(raw), 10) + padLeft(gz, 10)
                  + "  " + pad(verdict, 12) + pinned)
        }
        if islandRows.isEmpty {
            print("  islands: none built (opt-in — run `plugin wasm-island` to produce one)")
        } else {
            for (name, size, verdict) in islandRows {
                print("  " + pad(name, 20) + padLeft(String(size), 10) + padLeft("—", 10)
                      + "  " + pad(verdict, 12) + "per-file ≤ \(Self.islandCeiling)")
            }
        }
        print("─────────────────────────────────────────────────────────────────")
        if islandRows.contains(where: { $0.2 == "stale" }) {
            let names = islandRows.filter { $0.2 == "stale" }.map(\.0).joined(separator: ", ")
            print("stale: \(names) — retired by NEXT_ARCHITECTURE.md §3. not shipped (.build/out is")
            print("       gitignored); delete .build/out/Products/Release-webassembly-wasm32/ to clear.")
        }

        guard breaches.isEmpty else {
            throw BudgetError("budget breached:\n" + breaches.map { "  • \($0)" }.joined(separator: "\n"))
        }
        print("budget: PASS — every shipped surface is within its pinned ceiling, so the\nnext item (compression) fails loudly if it does not actually help.")
    }

    /// gzip byte count for a file, or nil when `gzip` is unavailable. the plugin
    /// sandbox permits spawning; if it does not, the compressed column degrades to
    /// `n/a` and only the raw ceilings are enforced rather than the gate lying.
    private func gzipSize(of url: URL) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gzip", "-9", "-c", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data.count
    }
}