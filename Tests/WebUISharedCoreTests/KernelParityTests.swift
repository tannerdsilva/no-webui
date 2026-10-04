import Foundation
import Testing
import WebUISharedCore

// MARK: - KernelParityTests (t4.2)
//
// the native side of the parity gate. three jobs:
//   1. recompute the corpus hashes and assert they equal the FROZEN golden
//      table below — any kernel behaviour change (even a rename, which
//      reorders nothing but is a deliberate corpus change) fails here;
//   2. write `.build/webui-kernel-corpus-native.json` — the same JSON
//      `webui_run_corpus` serves from the wasm — for the node probe
//      (designer/probes/c-parity.mjs) to compare against the island hashes;
//   3. pin the corpus shape (format name + case count + names).
//
// the golden table is generated once by KernelParity itself and frozen; it is
// the commit-time anchor that makes "native == island" meaningful (both sides
// are checked against the same stable numbers).

private let nativeArtifactPath = ".build/webui-kernel-corpus-native.json"

@Suite("parity: corpus shape")
struct KernelParityShapeTests {
	@Test("the corpus is the frozen case set, in order")
	func frozenNames() {
		let names = KernelCorpus.all.map { $0.name }
		#expect(names == [
			"normalize.trim",
			"normalize.collapse",
			"normalize.basic",
			"lex.words",
			"lex.custom",
			"aggregate.array",
			"aggregate.empty",
			"aggregate.incremental",
			"sort.stable",
			"sort.large",
			"filter.basic",
			"filter.page",
			"format.int",
			"format.grouped",
			"format.fixed",
			"format.percent",
			"date.iso",
			"date.weekday",
			"date.long",
			"date.roundtrip",
		])
	}

	@Test("the JSON the probe consumes is well-formed and complete")
	func jsonShape() throws {
		let json = KernelParity.resultsJSON()
		let object = try #require(try? JSONSerialization.jsonObject(with: Data(json.utf8)))
		let root = try #require(object as? [String: Any])
		#expect(root["format"] as? String == "kernel-corpus")
		#expect(root["count"] as? Int == KernelCorpus.all.count)
		let cases = try #require(root["cases"] as? [[String: Any]])
		#expect(cases.count == KernelCorpus.all.count)
		for (index, item) in cases.enumerated() {
			#expect(item["name"] as? String == KernelCorpus.all[index].name)
			let hash = try #require(item["hash"] as? String)
			#expect(hash.count == 16)
			// every hash in the ﬁle is a real FNV-1a of the recomputed result —
			// the native side never serializes a stale value.
			#expect(hash == FNV1a.hex(KernelCorpus.all[index].run()))
		}
	}

	@Test("refresh: write the native-corpus artifact for the node probe")
	func refreshArtifact() throws {
		let json = KernelParity.resultsJSON()
		let url = URL(fileURLWithPath: nativeArtifactPath)
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		try Data((json + "\n").utf8).write(to: url)
	}
}

@Suite("parity: golden hashes (native)")
struct KernelParityGoldenTests {
	@Test("native hashes equal the frozen golden table")
	func golden() throws {
		let hashes = KernelParity.hashes()
		// FROZEN at lane-c wave 3, t4.2 (kernel-corpus v1, 20 cases). regenerate via
		// KernelParity only when the corpus deliberately changes.
		let golden: [String: String] = [
			"normalize.trim": "ee16d71b01546c5f",
			"normalize.collapse": "266cdc48bb5f3e37",
			"normalize.basic": "3519e25c00c94aff",
			"lex.words": "6d99fe8ecaeae379",
			"lex.custom": "c6f9b86d8279ed4b",
			"aggregate.array": "f786de1de7e4dec4",
			"aggregate.empty": "079402c8f28a172f",
			"aggregate.incremental": "ecb17dae74312e5c",
			"sort.stable": "2815836feeb92222",
			"sort.large": "85fa1dfaeba2ca83",
			"filter.basic": "667204965acb8f81",
			"filter.page": "c56931173d5e46fd",
			"format.int": "f57edf4716e1b003",
			"format.grouped": "de8f6266aa6ecb12",
			"format.fixed": "d4153490f0b31c0c",
			"format.percent": "ffa2b00bd841174b",
			"date.iso": "abfe43a48c7ebcfd",
			"date.weekday": "dd209b93a9bb0eb9",
			"date.long": "0945bd63e76a37c4",
			"date.roundtrip": "e71a39e28b0de946",
		]
		#expect(hashes.count == golden.count)
		for (name, expected) in golden {
			let actual = try #require(hashes[name], "case \(name) present")
			#expect(actual == expected, "case \(name): \(actual) != \(expected)")
		}
	}
}
