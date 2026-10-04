import Testing
import Foundation
import WebUIIslandCore
import WebUISharedCore

// MARK: - the measurement-fed island budgets (CONTINUUM_DX W2, lane C — DX-3's island half)
//
// the hand-declared `IslandBudget` pins (probe + validate) must not drift from
// the measured artifacts. the settled invariant — each declared dimension must
// live in the MEASURED BAND:
//
//     measured ≤ declared ≤ ceil(measured × 1.05)
//
// i.e. never below the built artifact (a pin that lies) and never looser than
// the auto-pin convention lane B's DX-3 writes (measured × 1.05; §2.3). within
// the band a human may tighten; outside it the number has drifted and this
// check names the exact re-pin.
//
// measurement source: the stripped artifacts `plugin wasm-island` writes to
// `.build/out/Products/Release-webassembly-wasm32/` (raw = file size; gzip =
// `gzip -n -9 -c` — the same tool `WebUIBudgetPlugin` measures with). when the
// continuum manifest (lane B's DX-3 carrier for measured rows) is on disk, its
// `islands[]` rows are cross-checked too — rows absent today are noted, not
// failed (the t4.2 scan gap; see continuum-notes/c-to-b.md).
//
// arm it by running `swift package --disable-sandbox plugin wasm-island`
// (default product = validate) and `--product WebUIProbeIsland` before
// `swift test`; artifact-less runs skip (`.enabled(if:)`), which keeps a fresh
// clone's `swift test` order-independent.

// MARK: - file-scope helpers (trait conditions evaluate before suite init)

/// the package root, climbed from this file's compile-time path:
/// `<root>/Tests/WebUIIslandCoreTests/BudgetDriftTests.swift`.
private func budgetPackageRoot() -> URL {
	URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.deletingLastPathComponent()
}

private func budgetArtifactPath(_ product: String) -> String {
	budgetPackageRoot()
		.appendingPathComponent(".build/out/Products/Release-webassembly-wasm32/\(product).wasm")
		.path
}

private func budgetArtifactExists(_ product: String) -> Bool {
	FileManager.default.fileExists(atPath: budgetArtifactPath(product))
}

/// measure one artifact: raw = file size, gz = `gzip -n -9 -c` byte count
/// (matching the budget plugin's compression tool so the numbers are the
/// same numbers the gate would enforce).
func budgetMeasure(_ product: String) -> (raw: Int, gz: Int)? {
	let path = budgetArtifactPath(product)
	guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
	      let raw = attrs[.size] as? Int else { return nil }
	do {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["gzip", "-n", "-9", "-c", path]
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = Pipe()
		try process.run()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { return nil }
		return (raw, data.count)
	} catch {
		return nil
	}
}

/// the measured band: `[measured, ceil(measured × 1.05)]`, integer-exact.
func budgetBand(_ measured: Int) -> ClosedRange<Int> {
	measured...((measured * 105 + 99) / 100)
}

/// lane B's merged continuum manifest (the `generate` verb's output in the
/// plugin outputs tree — the same walk `WebUIBudgetPlugin.islandManifestURL`
/// does), when present.
func budgetManifestURL() -> URL? {
	let outputs = budgetPackageRoot().appendingPathComponent(".build/plugins/outputs")
	guard let packages = try? FileManager.default.contentsOfDirectory(
		at: outputs, includingPropertiesForKeys: nil) else { return nil }
	for package in packages {
		guard let targets = try? FileManager.default.contentsOfDirectory(
			at: package, includingPropertiesForKeys: nil) else { continue }
		for target in targets {
			let manifest = target
				.appendingPathComponent("destination")
				.appendingPathComponent("WebUIContinuumPlugin")
				.appendingPathComponent("ContinuumManifest.json")
			if FileManager.default.fileExists(atPath: manifest.path) { return manifest }
		}
	}
	return nil
}

// MARK: - the suite

@Suite struct BudgetDriftTests {

	@Test(
		"probe: declared IslandBudget lives in the measured band (raw + gz)",
		.enabled(if: budgetArtifactExists("WebUIProbeIsland"))
	)
	func probeBudgetIsMeasurementFed() {
		assertBand(
			product: "WebUIProbeIsland",
			island: "probe",
			maxBytes: ProbeIsland.budget.maxBytes,
			maxGzipBytes: ProbeIsland.budget.maxGzipBytes
		)
	}

	@Test(
		"validate: declared IslandBudget lives in the measured band (raw + gz)",
		.enabled(if: budgetArtifactExists("WebUIValidateIsland"))
	)
	func validateBudgetIsMeasurementFed() {
		assertBand(
			product: "WebUIValidateIsland",
			island: "validate",
			maxBytes: ValidateIsland.budget.maxBytes,
			maxGzipBytes: ValidateIsland.budget.maxGzipBytes
		)
	}

	/// the shared assertion: band membership for raw + gz, naming the exact
	/// re-pin when a dimension drifted, plus the DX-3 manifest cross-check.
	private func assertBand(product: String, island: String, maxBytes: Int, maxGzipBytes: Int?) {
		guard let measured = budgetMeasure(product) else {
			Issue.record("\(product): artifact present but unmeasurable — check \(budgetArtifactPath(product))")
			return
		}
		let rawBand = budgetBand(measured.raw)
		let gzBand = budgetBand(measured.gz)

		if !rawBand.contains(maxBytes) {
			Issue.record("\(product) [\(island)]: declared maxBytes \(maxBytes) is outside the measured band \(rawBand.lowerBound)...\(rawBand.upperBound) — re-pin IslandBudget(maxBytes: \(rawBand.upperBound), maxGzipBytes: \(maxGzipBytes.map { _ in "\(gzBand.upperBound)" } ?? "<nil>")) (measured \(measured.raw) raw / \(measured.gz) gz)")
		}
		if let maxGzipBytes, !gzBand.contains(maxGzipBytes) {
			Issue.record("\(product) [\(island)]: declared maxGzipBytes \(maxGzipBytes) is outside the measured band \(gzBand.lowerBound)...\(gzBand.upperBound) — re-pin IslandBudget(maxBytes: \(rawBand.upperBound), maxGzipBytes: \(gzBand.upperBound)) (measured \(measured.raw) raw / \(measured.gz) gz)")
		}

		// lane B's DX-3 measured rows, when present: measurement agreement +
		// tightening-only declarations (the red-team fold: pins never silently
		// loosen past the auto-pin).
		guard let manifestURL = budgetManifestURL(),
		      let data = FileManager.default.contents(atPath: manifestURL.path),
		      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let islands = root["islands"] as? [[String: Any]]
		else {
			print("note: \(product): no ContinuumManifest.json in the plugin outputs — DX-3 row cross-check skipped")
			return
		}
		let row = islands.first { row in
			guard let name = row["name"] as? String else { return false }
			let n = name.lowercased(), p = product.lowercased()
			return p.contains(n) || n.contains(p)
		}
		guard let row else {
			print("note: \(product): no islands[] row (manifest islands[] empty — DX-3 measured rows not on disk yet) — cross-check skipped")
			return
		}
		if let rowRaw = row["raw"] as? Int {
			#expect(rowRaw == measured.raw, "\(product): DX-3 manifest raw \(rowRaw) ≠ measured \(measured.raw) — measurement disagreement")
		}
		if let rowMax = row["maxBytes"] as? Int {
			#expect(maxBytes <= rowMax, "\(product): declared maxBytes \(maxBytes) exceeds the DX-3 auto-pin \(rowMax) — declarations are tightening-only")
		}
		if let rowMaxGz = row["maxGzipBytes"] as? Int, let maxGzipBytes {
			#expect(maxGzipBytes <= rowMaxGz, "\(product): declared maxGzipBytes \(maxGzipBytes) exceeds the DX-3 auto-pin \(rowMaxGz) — declarations are tightening-only")
		}
	}
}