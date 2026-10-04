// MARK: - KernelParity (t4.2)
//
// the parity runner: turns every kernel corpus case into an FNV-1a hash of
// its canonical result. the SAME source executes natively (swift test) and
// inside the probe island's wasm (`webui_run_corpus` export calls this), and
// the two hash sets must be equal — that is the t4.2 gate. this file is the
// single source of truth for both sides; the sidecar protocol:
//
//   native:  KernelParityTests asserts KernelParity.hashes() == golden and
//            writes `.build/webui-kernel-corpus-native.json`
//   island:  WebUIProbeIsland.webui_run_corpus() serves the same JSON
//   probe:   designer/probes/c-parity.mjs compares the two sets

public struct KernelParityCase: Sendable {
	public let name: String
	public let hash: String
}

public enum KernelParity {
	/// "kernel-corpus" — the wire format version the probe sanity-checks.
	public static let formatName = "kernel-corpus"

	/// run every corpus case and hash its canonical result. deterministic and
	/// order-stable; the golden table in KernelParityTests freezes its output.
	public static func results() -> [KernelParityCase] {
		KernelCorpus.all.map { caseItem in
			KernelParityCase(name: caseItem.name, hash: FNV1a.hex(caseItem.run()))
		}
	}

	/// name → hash, for map-style comparison.
	public static func hashes() -> [String: String] {
		var out: [String: String] = [:]
		for result in results() { out[result.name] = result.hash }
		return out
	}

	/// the JSON payload both placements emit: an ordered `cases` array (order
	/// is part of the contract), plus the format name and case count.
	public static func resultsJSON() -> String {
		let computed = results()
		let cases: [JSONValue] = computed.map { result in
			.object([
				"name": .string(result.name),
				"hash": .string(result.hash),
			])
		}
		return JSONValue.object([
			"format": .string(formatName),
			"count": .number(Double(computed.count)),
			"cases": .array(cases),
		]).serialize()
	}
}
