import Foundation
import PackagePlugin

/// a shipped-surface budget breach is a gate failure, never a warning — the
/// numbers below are the reason "it is very fast" is a checked property rather
/// than a memory (plan d12 / E2).
struct BudgetError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// one pinned ceiling for a shipped surface.
private struct Ceiling {
    /// the key `WebUIAssetTool` writes into `AssetsManifest.json`.
    let surface: String
    /// the working file, measured only when no manifest is available.
    let label: String
    /// bytes as served (the minified sheet), or as written for the fallback.
    let raw: Int
    /// gzip bytes as served. this is the number that reaches a client.
    let gz: Int?
}

@main
struct WebUIBudgetPlugin: CommandPlugin {

    /// ceilings carry roughly 5-15% headroom over the measured value: loose enough to
    /// absorb a copy edit, tight enough that a structural regression trips them. every
    /// number names the measurement it came from so the next person can tell drift from
    /// noise rather than guessing.
    ///
    /// measured 2026-09-29 (post-compression), verified against a live WebUIExample and
    /// reported by the asset tool's manifest:
    ///   engine  42,440 raw / 10,547 gz
    ///   sheet  321,262 SERVED (minified) / 44,991 gz   [working file is 346,163]
    ///   shell    1,514 raw /    554 gz
    ///   island 164,447 stripped (WebUIValidateIsland)  [doc: "164 kb" — matches]
    ///
    /// re-pinned 2026-09-30: the engine grew 1,678 raw bytes across three deliberate commits
    /// (client-owned theme switching, `on.afterPatch`/`on.ready`, `htmlAttributes` + the
    /// server-rendered scheme stop being stripped), tripping this gate — which is what it is
    /// for. measured 44,118 raw / 10,898 gz, so the gzip pin holds (the additions compress
    /// well: raw +4%, gz +3%) and only the raw ceiling moves.
    ///
    /// the sheet's `raw` is the MINIFIED size, not the working file: the two differ by
    /// ~8% and a budget on the wrong number is a false sense of safety. this plugin
    /// learned that the hard way — its first pin was taken from the working file's gzip
    /// and failed immediately.
    ///
    /// `NEXT_ARCHITECTURE.md` §5 quotes the sheet at "~40 kb gz" and 308,930 served bytes;
    /// measured are 44,991 gz and 321,262. those doc figures are stale.
    ///
    /// the theming work (T8/T9) will add tokens and therefore grow the sheet, which should
    /// trip this gate and force a deliberate re-pin rather than a silent drift.
    private static let ceilings: [Ceiling] = [
        // re-pinned d0 (t0.4, 2026-10-03): the engine grew to 52,433 raw /
        // 12,744 gz after the oct-2 wire work (lanes' seam growth), tripping
        // the former 46,000 / 11,600 pin — the mechanism working as designed.
        // re-pinned i1 (2026-10-03): the anticipated second trip — the merged
        // wave-1 tree (base + lane e's op apply / coalescer / echo) measured
        // 56,818 raw / 13,602 gz (the gz pin tripped by 2 bytes). deliberate
        // re-pin at ~5-6% headroom, orchestrator-side at integration.
        Ceiling(surface: "engine", label: "webui-engine.js", raw: 60_000, gz: 14_500),
        Ceiling(surface: "sheet", label: "design-system.css", raw: 335_000, gz: 49_500),
        Ceiling(surface: "shell", label: "webui-shell.js", raw: 1_700, gz: 650),
    ]

    /// a capability island is a per-capability artifact; the ceiling is per file,
    /// and absence is reported rather than failed (islands are opt-in, d3/d6).
    ///
    /// re-measured 2026-09-30: 164,670 stripped (WebUIValidateIsland) — the ~21% headroom
    /// intact, so the pin did not move. it HAD been breaching at 7,168,189, and that was a
    /// build-mode regression, not a size decision: the island was being cross-built with the
    /// FULL wasm sdk, because the leaf had lost its embedded-cleanliness (`firstRange(of:)`
    /// arriving with the attribute model, which the embedded stdlib does not carry) and the
    /// embedded compile therefore failed. the plugin defaults to
    /// `swift-6.4.0-RELEASE_wasm-embedded` now and the leaf is scalar-clean again; keep
    /// island-bound code free of the APIs named in `WebUIIslandPlugin`'s doc comment.
    private static let islandCeiling = 200_000

    /// artifacts the architecture has retired. if one is still on disk it is a stale
    /// build product, not a shipped surface — reported so nobody ships it by accident,
    /// but not a breach (it cannot ship: `.build/out` is gitignored).
    /// `NEXT_ARCHITECTURE.md` §3 records the monolith as dropped from the default path;
    /// this list is where that decision becomes operational.
    private static let retiredArtifacts: Set<String> = ["WebUIClient.wasm"]

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let packageDir = context.package.directoryURL
        let assets = packageDir
            .appendingPathComponent("designer")
            .appendingPathComponent("assets")

        let manifest = Self.servedManifest(in: packageDir)
        var breaches: [String] = []
        var rows: [(String, String, Int, String, String, String)] = []

        for ceiling in Self.ceilings {
            var raw: Int
            var gz: Int?
            var source: String

            if let served = manifest?[ceiling.surface],
               let servedRaw = served["raw"], let servedGz = served["gz"] {
                raw = servedRaw
                gz = servedGz > 0 ? servedGz : nil
                source = "served"
            } else {
                // no manifest yet (nothing built, or the tool predates it): measure the
                // working file. it is LARGER than what ships, so this is conservative —
                // and the row says so, because a proxy silently mistaken for the real
                // number is how the first pin went wrong.
                let url = assets.appendingPathComponent(ceiling.label)
                guard let data = FileManager.default.contents(atPath: url.path) else {
                    breaches.append("\(ceiling.label): missing at \(url.path)")
                    continue
                }
                raw = data.count
                gz = gzipSize(of: url)
                source = "working*"
            }

            if raw > ceiling.raw {
                breaches.append("\(ceiling.surface): \(raw) raw bytes > \(ceiling.raw) pinned")
            }
            var gzVerdict = "—"
            if let gz, let limit = ceiling.gz {
                gzVerdict = gz <= limit ? "ok" : "OVER"
                if gzVerdict == "OVER" {
                    breaches.append("\(ceiling.surface): \(gz) gzip bytes > \(limit) pinned")
                }
            }
            let rawVerdict = raw <= ceiling.raw ? "ok" : "OVER"
            rows.append((
                ceiling.surface,
                "\(rawVerdict)/\(gzVerdict)",
                raw,
                gz.map(String.init) ?? "n/a",
                source,
                "raw≤\(ceiling.raw) gz≤\(ceiling.gz.map(String.init) ?? "-")"
            ))
        }

        // consumer manifests: one row per entry the embed plugin declared, with the manifest's
        // own pins. a breach here is defense in depth — the build that produced the receipt
        // would already have failed — but the row is what makes a consumer's bytes visible
        // next to the framework's own.
        var consumerRows: [(String, String, Int, String, String, String)] = []
        for receiptFile in Self.embedReceipts(in: packageDir) {
            guard
                let data = FileManager.default.contents(atPath: receiptFile.path),
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let embedded = root["embedded"] as? [[String: Any]]
            else { continue }
            let label = (root["manifest"] as? String)
                .map { URL(fileURLWithPath: $0).lastPathComponent } ?? "webui-assets.json"
            for entry in embedded {
                let type = (entry["type"] as? String) ?? "?"
                let raw = entry["raw"] as? Int ?? 0
                let gz = entry["gz"] as? Int ?? 0
                var verdict = "ok"
                if let ceiling = entry["ceilingBytes"] as? Int, raw > ceiling {
                    verdict = "OVER"
                    breaches.append("\(label)/\(type): \(raw) raw bytes > \(ceiling) pinned")
                }
                if let ceiling = entry["ceilingGzipBytes"] as? Int, gz > ceiling {
                    verdict = "OVER"
                    breaches.append("\(label)/\(type): \(gz) gzip bytes > \(ceiling) pinned")
                }
                let pinned = [
                    (entry["ceilingBytes"] as? Int).map { "raw≤\($0)" },
                    (entry["ceilingGzipBytes"] as? Int).map { "gz≤\($0)" },
                ].compactMap { $0 }.joined(separator: " ")
                consumerRows.append((
                    "\(label)/\(type)",
                    verdict,
                    raw,
                    gz > 0 ? String(gz) : "n/a",
                    "manifest",
                    pinned.isEmpty ? "unpinned" : pinned
                ))
            }
        }

        // islands: report every artifact, enforce the per-file ceiling on each.
        let islandDir = packageDir
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
        print("  " + pad("surface", 10) + padLeft("raw", 10) + padLeft("gzip", 10)
              + "  " + pad("verdict", 12) + pad("source", 18) + "pinned")
        for (surface, verdict, raw, gz, source, pinned) in rows {
            print("  " + pad(surface, 10) + padLeft(String(raw), 10) + padLeft(gz, 10)
                  + "  " + pad(verdict, 12) + pad(source, 18) + pinned)
        }
        for (surface, verdict, raw, gz, source, pinned) in consumerRows {
            print("  " + pad(surface, 28) + padLeft(String(raw), 10) + padLeft(gz, 10)
                  + "  " + pad(verdict, 12) + pad(source, 18) + pinned)
        }
        if islandRows.isEmpty {
            print("  islands: none built (opt-in — run `plugin wasm-island` to produce one)")
        } else {
            for (name, size, verdict) in islandRows {
                print("  " + pad(name, 10) + padLeft(String(size), 10) + padLeft("—", 10)
                      + "  " + pad(verdict, 12) + pad("", 18) + "per-file ≤ \(Self.islandCeiling)")
            }
        }
        print("─────────────────────────────────────────────────────────────────")
        if manifest == nil {
            print("source `working*` = measured from the working file because no")
            print("  AssetsManifest.json was found; those numbers are LARGER than what ships.")
            print("  run `swift build` to produce it and re-run this gate.")
        }
        if islandRows.contains(where: { $0.2 == "stale" }) {
            let names = islandRows.filter { $0.2 == "stale" }.map(\.0).joined(separator: ", ")
            print("stale: \(names) — retired by NEXT_ARCHITECTURE.md §3. not shipped (.build/out is")
            print("       gitignored); delete .build/out/Products/Release-webassembly-wasm32/ to clear.")
        }

        guard breaches.isEmpty else {
            throw BudgetError("budget breached:\n" + breaches.map { "  • \($0)" }.joined(separator: "\n"))
        }
        print("budget: PASS — every shipped surface is within its pinned ceiling.")
    }

    // MARK: - the served manifest

    /// `WebUIAssetTool` writes the served byte counts next to the generated assets, which
    /// live in a plugin-work path whose hash SwiftPM owns. found by walking the known
    /// shape rather than guessing the hash.
    private static func servedManifest(in packageDir: URL) -> [String: [String: Int]]? {
        let outputs = packageDir
            .appendingPathComponent(".build")
            .appendingPathComponent("plugins")
            .appendingPathComponent("outputs")
        guard let packages = try? FileManager.default.contentsOfDirectory(
            at: outputs, includingPropertiesForKeys: nil
        ) else { return nil }
        for package in packages {
            guard let targets = try? FileManager.default.contentsOfDirectory(
                at: package, includingPropertiesForKeys: nil
            ) else { continue }
            for target in targets {
                let manifest = target
                    .appendingPathComponent("destination")
                    .appendingPathComponent("WebUIAssetPlugin")
                    .appendingPathComponent("AssetsManifest.json")
                guard let data = FileManager.default.contents(atPath: manifest.path),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let served = root["served"] as? [String: [String: Int]]
                else { continue }
                return served
            }
        }
        return nil
    }

    /// every `EmbedReceipt.json` the embed plugin wrote — found by walking the known
    /// plugin-output shape rather than guessing the package hash swiftpm owns.
    private static func embedReceipts(in packageDir: URL) -> [URL] {
        let outputs = packageDir
            .appendingPathComponent(".build")
            .appendingPathComponent("plugins")
            .appendingPathComponent("outputs")
        guard let packages = try? FileManager.default.contentsOfDirectory(
            at: outputs, includingPropertiesForKeys: nil
        ) else { return [] }
        var found: [URL] = []
        for package in packages {
            guard let targets = try? FileManager.default.contentsOfDirectory(
                at: package, includingPropertiesForKeys: nil
            ) else { continue }
            for target in targets {
                let receipt = target
                    .appendingPathComponent("destination")
                    .appendingPathComponent("WebUIEmbedPlugin")
                    .appendingPathComponent("EmbedReceipt.json")
                if FileManager.default.fileExists(atPath: receipt.path) {
                    found.append(receipt)
                }
            }
        }
        return found
    }

    /// gzip byte count for a file, or nil when `gzip` is unavailable. the plugin sandbox
    /// permits spawning; if it does not, the compressed column degrades to `n/a` and only
    /// the raw ceilings are enforced rather than the gate lying.
    private func gzipSize(of url: URL) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gzip", "-n", "-9", "-c", url.path]
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