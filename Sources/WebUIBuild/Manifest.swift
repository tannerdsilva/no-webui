import Foundation
import WebUICore

// MARK: - the manifest

// SwiftPM cannot parameterize a plugin, so the manifest is a file convention the plugin
// discovers at `<target.directory>/Assets/webui-assets.json`. every path in it is relative
// to the manifest's own directory, so a manifest and the assets it names move together.

/// a target's declared assets: the entries ``WebUIAssetBuilder/embed(manifest:to:)`` turns
/// into one generated file.
public struct WebUIAssetManifest: Sendable {

	/// one declared asset.
	public struct Entry: Sendable {
		/// how the entry's payload is obtained.
		public enum Kind: String, Sendable {
			/// a single file on disk.
			case file
			/// an inline payload in the manifest itself.
			case text
			/// every file in a directory matching ``extensions``, emitted as one name-keyed bag.
			case directory
		}

		public let name: String
		public let kind: Kind
		/// the path relative to the manifest's directory (`file`, `directory` kinds).
		public let path: String?
		/// the inline payload (the `text` kind).
		public let text: String?
		/// which file names a `directory` entry includes, e.g. `[".woff2"]`.
		public let extensions: [String]
		public let contentType: String
		public let minify: Bool
		public let prose: ProsePolicy
	}

	/// the declared assets, in manifest order.
	public let entries: [Entry]

	/// the directory `path`s resolve against — the loaded manifest's own.
	let directory: URL

	// MARK: loading and validation

	/// read and validate a manifest at `url`. an unknown key, an unknown kind, a missing
	/// required field or an unreadable file fails naming the entry: silently ignoring a typo
	/// would ship a page that links an asset nobody embedded.
	public static func load(from url: URL) throws -> WebUIAssetManifest {
		let data: Data
		do {
			data = try Data(contentsOf: url)
		} catch {
			throw WebUIBuildError.malformedManifest("cannot read \(url.path)")
		}
		guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
			throw WebUIBuildError.malformedManifest("\(url.path) is not a json object")
		}
		try rejectUnknown(root, allowed: ["types"], context: "manifest")
		guard let rawEntries = root["types"] as? [[String: Any]] else {
			throw WebUIBuildError.malformedManifest("'types' must be an array of entries")
		}
		var entries: [Entry] = []
		for (index, raw) in rawEntries.enumerated() {
			entries.append(try Self.entry(from: raw, index: index))
		}
		return WebUIAssetManifest(entries: entries, directory: url.deletingLastPathComponent())
	}

	static let entryKeys: Set<String> = [
		"name", "kind", "path", "text", "extensions", "contentType", "minify", "prose",
	]

	static func entry(from raw: [String: Any], index: Int) throws -> Entry {
		// the name first: every later failure can then name the entry.
		guard let name = raw["name"] as? String, !name.isEmpty else {
			throw WebUIBuildError.malformedManifest("entry \(index) has no 'name'")
		}
		try rejectUnknown(raw, allowed: entryKeys, context: "entry \(name)")
		guard
			let kindRaw = raw["kind"] as? String,
			let kind = Entry.Kind(rawValue: kindRaw)
		else {
			let got = (raw["kind"] as? String) ?? "nothing"
			throw WebUIBuildError.malformedManifest(
				"entry \(name): 'kind' must be file, text or directory (got '\(got)')"
			)
		}
		guard let contentType = raw["contentType"] as? String else {
			throw WebUIBuildError.malformedManifest("entry \(name): 'contentType' is required")
		}
		let path = raw["path"] as? String
		let text = raw["text"] as? String
		let extensions = (raw["extensions"] as? [String]) ?? []
		if kind == .file, path == nil {
			throw WebUIBuildError.malformedManifest("entry \(name): kind 'file' needs 'path'")
		}
		if kind == .text, text == nil {
			throw WebUIBuildError.malformedManifest("entry \(name): kind 'text' needs 'text'")
		}
		if kind == .directory, path == nil || extensions.isEmpty {
			throw WebUIBuildError.malformedManifest(
				"entry \(name): kind 'directory' needs 'path' and 'extensions'"
			)
		}
		let prose: ProsePolicy
		switch raw["prose"] as? String ?? "off" {
		case "off": prose = .off
		case "check": prose = .check
		default:
			throw WebUIBuildError.malformedManifest("entry \(name): 'prose' must be 'off' or 'check'")
		}
		return Entry(
			name: name, kind: kind, path: path, text: text, extensions: extensions,
			contentType: contentType, minify: raw["minify"] as? Bool ?? false, prose: prose
		)
	}

	static func rejectUnknown(_ object: [String: Any], allowed: Set<String>, context: String) throws {
		for key in object.keys.sorted() where !allowed.contains(key) {
			throw WebUIBuildError.malformedManifest(
				"\(context): unknown key '\(key)' — allowed: \(allowed.sorted().joined(separator: ", "))"
			)
		}
	}
}

// MARK: - embedding a manifest

public extension WebUIAssetBuilder {

	/// write every entry of `manifest` as generated swift in one file, returning one receipt
	/// per entry (the directory bag's stamp is a build record — the digest of its sorted
	/// name+bytes stream — not a url address; a bag is not one servable asset).
	@discardableResult
	static func embed(manifest: WebUIAssetManifest, to url: URL) throws -> [Emitted] {
		var blocks: [[String]] = []
		var receipts: [Emitted] = []
		for entry in manifest.entries {
			switch entry.kind {
			case .text:
				let bytes = Array(try prepare(entry.text ?? "", entry: entry).utf8)
				let variant = gzip(Data(bytes))
				let stamp = String(sha256Hex(bytes).prefix(12))
				blocks.append(shippedTypeBlock(
					typeName: entry.name, contentType: entry.contentType,
					stamp: stamp, body: bytes, variant: variant,
					includeText: isTextContent(entry.contentType)
				))
				receipts.append(Emitted(
					typeName: entry.name, bytes: bytes.count, gzipBytes: variant?.count, stamp: stamp
				))

			case .file:
				let path = manifest.directory.appendingPathComponent(entry.path ?? "")
				guard let raw = try? Data(contentsOf: path) else {
					throw WebUIBuildError.missingAsset(entry: entry.name, path: path.path)
				}
				let bytes: [UInt8]
				if isTextContent(entry.contentType) {
					guard let text = String(data: raw, encoding: .utf8) else {
						throw WebUIBuildError.malformedManifest(
							"entry \(entry.name): \(path.lastPathComponent) is declared \(entry.contentType) but is not utf-8"
						)
					}
					bytes = Array(try prepare(text, entry: entry).utf8)
				} else {
					// binary: the minifier and the prose guard have nothing to read.
					bytes = Array(raw)
				}
				let variant = gzip(Data(bytes))
				let stamp = String(sha256Hex(bytes).prefix(12))
				blocks.append(shippedTypeBlock(
					typeName: entry.name, contentType: entry.contentType,
					stamp: stamp, body: bytes, variant: variant,
					includeText: isTextContent(entry.contentType)
				))
				receipts.append(Emitted(
					typeName: entry.name, bytes: bytes.count, gzipBytes: variant?.count, stamp: stamp
				))

			case .directory:
				let dir = manifest.directory.appendingPathComponent(entry.path ?? "")
				guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
					throw WebUIBuildError.missingAsset(entry: entry.name, path: dir.path)
				}
				var files: [(name: String, bytes: [UInt8])] = []
				for name in names.sorted() where entry.extensions.contains(where: { name.hasSuffix($0) }) {
					let fileURL = dir.appendingPathComponent(name)
					guard let raw = try? Data(contentsOf: fileURL) else {
						throw WebUIBuildError.missingAsset(entry: entry.name, path: fileURL.path)
					}
					files.append((name: name, bytes: Array(raw)))
				}
				blocks.append(directoryBlock(
					typeName: entry.name, contentType: entry.contentType, files: files
				))
				var joined: [UInt8] = []
				for file in files.sorted(by: { $0.name < $1.name }) {
					joined.append(contentsOf: Array(file.name.utf8))
					joined.append(contentsOf: file.bytes)
				}
				receipts.append(Emitted(
					typeName: entry.name,
					bytes: files.reduce(0) { $0 + $1.bytes.count },
					gzipBytes: nil,
					stamp: String(sha256Hex(joined).prefix(12))
				))
			}
		}

		let header = [
			"// generated by WebUIBuild — do not edit.",
			"//",
			"// the types `webui-assets.json` declares. each `WebUIShippedAsset` conformance is a",
			"// `WebUIAsset(<Type>.self, path: \"/ui/…\")`; a directory bag is decoded file by file.",
		]
		try assemble(header: header, blocks: blocks).write(to: url, atomically: true, encoding: .utf8)
		return receipts
	}

	/// minify (if asked), then judge the prose gate — the same order, and the same two
	/// implementations, the single-payload front door uses.
	static func prepare(_ text: String, entry: WebUIAssetManifest.Entry) throws -> String {
		let payload = entry.minify ? minifyCSS(text) : text
		try check(
			payload: payload,
			typeName: entry.name,
			language: proseLanguage(for: entry.contentType),
			policy: entry.prose
		)
		return payload
	}

	/// whether a content type is text-shaped: its bytes are characters a minifier and the
	/// prose guard can read. this also decides the emitted `text` convenience — a font or a
	/// wasm blob gets no meaningless text accessor.
	static func isTextContent(_ contentType: String) -> Bool {
		let lowered = contentType.lowercased()
		return lowered.hasPrefix("text/")
			|| lowered.contains("javascript")
			|| lowered.contains("json")
			|| lowered.contains("css")
			|| lowered.contains("xml")
	}
}