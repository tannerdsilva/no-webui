import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

// MARK: - the dx-2 `scaffold` verb (CONTINUUM_DX §2.2) — zero-manual-steps onboarding
//
// the explicit path for an EXISTING app (and for skeptical teams); new apps
// start from the template whose manifest already carries the inert block.
// two sub-surfaces + a preview:
//
//   scaffold --add-island <Name> [--package no-webui] [--print]
//     appends the two Package entries (product + executableTarget, beside their
//     sibling blocks — append-only anchors, never a reorder) and generates
//     Sources/<Name>/main.swift — the W2 THREE-LINE RUNTIME FORM
//     (CONTINUUM_DX DX-1, lane C): an inert @main stub plus the
//     webui_island_bind shim calling `IslandRuntime<<Type>.<Type>Island>.run()`.
//     the adapter type is the MACRO-PRODUCED one (lane D's expansion emits
//     `struct <Type>Island: ContinuumIsland` nested in `extension <Type>`), so
//     the generated main names `<Type>.<Type>Island` — pinned in BOTH suites:
//     lane D's expansion tests AND this tool's CLI tests reference the exact
//     string `Feed.FeedIsland`, so a rename breaks both loudly. zero
//     Package.swift edits for the SECOND island onward: the verb is
//     idempotent on an existing target (regenerates the main only) and the
//     autobuild plugin discovers new island dirs by scanning — no per-island
//     manifest-side magic (candidate (c) is dead).
//     every generated file carries the house `generated — do not edit` header.
//
//   scaffold --bootstrap --name <App> --framework <no-webui path> [--print]
//     the EXISTING-app path: inserts the once-per-app INERT continuum block —
//     the framework path dependency + `WebUIAutobuildPlugin` on the app target
//     — exactly the static block the acceptance template pre-carries. after
//     bootstrap, islands need no further manifest edits.
//
//   --print emits the snippet(s) without writing (teams that decline write
//     permission); the plugin is port-free (a command plugin, on demand).
//
// append-only + refusal semantics: the tool patches ONLY when it can anchor on
// the manifest's existing structure (a `products:`/`targets:`/`dependencies:`
// array with a matching close bracket); a malformed or unanchorable manifest
// is REFUSED with a named message, never partially patched. an already-present
// product/target/dependency is a no-op with an advisory, never a duplicate.

extension WebUIContinuumTool.Run {

	/// `scaffold --add-island <Name> | --bootstrap --name <App> --framework <path>`
	/// `        [--package no-webui] [--print]`
	static func scaffold(_ argv: [String]) throws {
		let packageDir = Args.option(argv, "--package-dir") ?? "."
		let packagePath = (packageDir as NSString).appendingPathComponent("Package.swift")
		let printOnly = Args.has(argv, "--print")

		if Args.has(argv, "--add-island") {
			let name = try Args.require(argv, "--add-island")
			let main = islandMainSource(name: name)
			let entriesText = islandProductEntry(island: name) + islandTargetEntry(island: name)
			if printOnly {
				print("// Package.swift — append beside the sibling blocks (append-only anchors):")
				print(entriesText)
				print("//")
				print("// Sources/\(name)/main.swift:")
				print(main, terminator: "")
				return
			}
			guard FileManager.default.fileExists(atPath: packagePath) else {
				WebUIContinuumTool.writeError("scaffold: Package.swift not found at \(packagePath)")
				exit(1)
			}
			var packageText = try String(contentsOfFile: packagePath, encoding: .utf8)
			let productExists = packageText.contains(".executable(name: \"\(name)\"")
			let targetExists = packageText.contains("name: \"\(name)\",")
			if productExists && targetExists {
				print("scaffold: island '\(name)' already in Package.swift — regenerating Sources/\(name)/main.swift only (no manifest edit)")
			} else {
				let inserted = insertPackageEntries(into: &packageText, island: name)
				if !inserted {
					WebUIContinuumTool.writeError("scaffold: cannot anchor on Package.swift's products/targets structure (expected a `products: [` / `targets: [` array) — refusing to patch; use --print to see the snippet and edit by hand")
					exit(1)
				}
				try packageText.write(toFile: packagePath, atomically: true, encoding: .utf8)
				print("scaffold: appended product + executableTarget for island '\(name)' (append-only)")
			}

			let sourcesDir = (packageDir as NSString).appendingPathComponent("Sources/\(name)")
			try FileManager.default.createDirectory(atPath: sourcesDir, withIntermediateDirectories: true)
			let mainPath = (sourcesDir as NSString).appendingPathComponent("main.swift")
			try main.write(toFile: mainPath, atomically: true, encoding: .utf8)
			print("scaffold: wrote Sources/\(name)/main.swift (generated — do not edit)")
			// DX-8: the one verb a getting-started path may name for island
			// verification — optional belt-and-suspenders; a plain `swift
			// build` already cross-builds + auto-pins (zero manual verbs).
			print("scaffold: next — write the island logic, then a plain `swift build` cross-builds + auto-pins it. optional one-shot check: `webui-continuum verify --package-dir . --framework <no-webui path>` (build -> cross-build -> measure/pin -> budget row).")
			return
		}

		if Args.has(argv, "--bootstrap") {
			let app = try Args.require(argv, "--name")
			let framework = try Args.require(argv, "--framework")
			if printOnly {
				print("// Package.swift — the once-per-app inert continuum block (DX-2 --bootstrap):")
				print(bootstrapDependencyLine(framework: framework))
				print(bootstrapPluginLine())
				return
			}
			guard FileManager.default.fileExists(atPath: packagePath) else {
				WebUIContinuumTool.writeError("scaffold: Package.swift not found at \(packagePath)")
				exit(1)
			}
			var packageText = try String(contentsOfFile: packagePath, encoding: .utf8)
			let inserted = insertBootstrapBlock(into: &packageText, app: app, framework: framework)
			if !inserted {
				WebUIContinuumTool.writeError("scaffold: cannot anchor on Package.swift for --bootstrap (expected the app target '\(app)' inside `targets:` and a `dependencies:` array) — refusing to patch; use --print to see the block and edit by hand")
				exit(1)
			}
			try packageText.write(toFile: packagePath, atomically: true, encoding: .utf8)
			print("scaffold: bootstrapped '\(app)' with the once-per-app continuum block (framework path dep + WebUIAutobuildPlugin)")
			return
		}

		WebUIContinuumTool.writeError("scaffold: use --add-island <Name> or --bootstrap --name <App> --framework <no-webui path> (add --print to preview without writing)")
		exit(2)
	}

	// MARK: entry emission

	/// the generated island main — the three-line runtime form. the adapter
	/// type is the macro-produced `<Type>.<Type>Island` (lane D's expansion
	/// names it exactly so); `webui_island_bind` is the runtime's lazy-binding
	/// entry, resolved at wasm link time.
	static func islandMainSource(name: String) -> String {
		"""
		// GENERATED FILE — do not edit.
		// generated by WebUIContinuumTool scaffold --add-island \(name) (CONTINUUM_DX DX-2).
		// the wasm reactor bind for the \(name) island. write the island logic
		// beside this file — `@HotView("\(name.lowercased())") struct \(name)` with
		// State/Action/reduce — the macro emits the \(name).\(name)Island adapter
		// this bind runs.

		import WebUIIslandCore
		import WebUISharedCore

		@main
		struct \(name)IslandMain {
		    static func main() {}
		}

		#if os(WASI)
		@_silgen_name("webui_island_bind")
		func webuiIslandBind() {
		    IslandRuntime<\(name).\(name)Island>.run()
		}
		#endif
		"""
	}

	/// the island product entry, as appended inside `products:` (4-space indent,
	/// matching the house style).
	static func islandProductEntry(island: String) -> String {
		"        .executable(name: \"\(island)\", targets: [\"\(island)\"]),\n"
	}

	/// the island executable target entry, as appended inside `targets:`.
	static func islandTargetEntry(island: String) -> String {
		"        .executableTarget(\n"
			+ "            name: \"\(island)\",\n"
			+ "            dependencies: [\n"
			+ "                .product(name: \"WebUIIslandCore\", package: \"no-webui\"),\n"
			+ "                .product(name: \"WebUISharedCore\", package: \"no-webui\"),\n"
			+ "            ]\n"
			+ "        ),\n"
	}

	/// the bootstrap dependency line (append inside `dependencies:`).
	static func bootstrapDependencyLine(framework: String) -> String {
		"        .package(name: \"no-webui\", path: \"\(framework)\"),\n"
	}

	/// the bootstrap plugin line (append inside the app target).
	static func bootstrapPluginLine() -> String {
		"            plugins: [.plugin(name: \"WebUIAutobuildPlugin\", package: \"no-webui\")],\n"
	}

	// MARK: text anchors (append-only)

	/// insert the island's product + target just before the close of the
	/// `products:` / `targets:` arrays (append-only: never reorder, never
	/// rewrite a sibling block). returns false when the anchors are missing.
	static func insertPackageEntries(into text: inout String, island: String) -> Bool {
		// both anchors must exist up front (refuse before mutation).
		guard let productsRange = arrayBodyRange(text, header: "products:"),
		      let targetsRange = arrayBodyRange(text, header: "targets:") else {
			return false
		}
		let productOK = insertBeforeClose(
			of: productsRange, in: &text,
			needle: ".executable(name: \"\(island)\"",
			fallbackNeedle: ".executable(",
			entry: islandProductEntry(island: island)
		)
		guard productOK else { return false }
		// the targets array shifted by the product insertion; re-anchor.
		guard let targetsAgain = arrayBodyRange(text, header: "targets:") else { return false }
		let targetOK = insertBeforeClose(
			of: targetsAgain, in: &text,
			needle: "name: \"\(island)\",",
			fallbackNeedle: nil,
			entry: islandTargetEntry(island: island)
		)
		guard targetOK else { return false }
		return true
	}

	/// insert the bootstrap dependency + plugin. returns false when no anchor.
	static func insertBootstrapBlock(into text: inout String, app: String, framework: String) -> Bool {
		// 1. the dependency into the dependencies array. the whole block is
		//    idempotent: a re-run sees the dependency and skips it.
		guard let depsRange = arrayBodyRange(text, header: "dependencies:") else { return false }
		let depOK = insertBeforeClose(
			of: depsRange, in: &text,
			needle: ".package(name: \"no-webui\"",
			// no fallback kind requirement: an EMPTY top-level dependencies
			// array is a valid append-only anchor (line-start anchoring has
			// already selected the package-level array, never a target's).
			fallbackNeedle: nil,
			entry: bootstrapDependencyLine(framework: framework)
		)
		guard depOK else { return false }

		// 2. the plugin into the app target block. re-anchor after the edit.
		guard let targetRange = targetBlockRange(text, name: app) else { return false }
		let pluginOK = insertBeforeClose(
			of: targetRange, in: &text,
			needle: ".plugin(name: \"WebUIAutobuildPlugin\"",
			fallbackNeedle: nil,
			entry: bootstrapPluginLine(),
			ensureTrailingComma: true
		)
		guard pluginOK else { return false }
		return true
	}

	// MARK: scanner helpers

	/// every occurrence of `header` that begins a line (a top-level array
	/// declaration — `targets:` on its own line, not the inner `targets: [...]`
	/// of an executable product's entry). line-start anchoring is what keeps
	/// the scaffold from editing the wrong array.
	static func lineStartOccurrences(_ text: String, header: String) -> [Range<String.Index>] {
		var out: [Range<String.Index>] = []
		var searchStart = text.startIndex
		while let range = text[searchStart...].range(of: header) {
			// the text from the last newline up to the header must be
			// whitespace only (`.executable(name: "App", targets: […]` has a
			// non-space before `targets`, so ONLY the top-level array line
			// matches).
			var cursor = range.lowerBound
			var atLineStart = true
			while cursor > text.startIndex {
				let prev = text.index(before: cursor)
				let c = text[prev]
				if c == "\n" || c == "\r" { break }
				if c != " " && c != "\t" { atLineStart = false; break }
				cursor = prev
			}
			if atLineStart {
				out.append(range)
			}
			searchStart = range.upperBound
		}
		return out
	}

	/// the character range of a top-level array's body: from just after the
	/// header's `[` to just before the matching `]` — paren/bracket depth
	/// counted, strings skipped, so the close of the OUTER array is found (not
	/// a nested one). `occurrence` picks WHICH line-start match (0 = the first
	/// top-level `dependencies:` — which for a manifest is the package-level
	/// one, since target-level `dependencies:` follow it in file order).
	static func arrayBodyRange(
		_ text: String, header: String, occurrence: Int = 0
	) -> Range<String.Index>? {
		let matches = lineStartOccurrences(text, header: header)
		guard occurrence < matches.count else { return nil }
		let headerRange = matches[occurrence]
		guard let open = text[headerRange.upperBound...].firstIndex(of: "[") else { return nil }
		var depth = 0
		var index = open
		var close: String.Index? = nil
		var inString = false
		while index < text.endIndex {
			let c = text[index]
			if inString {
				if c == "\\" {
					index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
					continue
				}
				if c == "\"" { inString = false }
			} else {
				if c == "\"" { inString = true }
				else if c == "[" { depth += 1 }
				else if c == "]" {
					depth -= 1
					if depth == 0 { close = index; break }
				}
			}
			index = text.index(after: index)
		}
		guard let close else { return nil }
		return text.index(after: open)..<close
	}

	/// insert `entry` before the array's closing bracket, but only when the
	/// `needle` is not already present (idempotence — SKIPS, advisory printed,
	/// and the caller's guard still passes so a re-run is a no-op, not a
	/// duplicate). `fallbackNeedle` requires an existing entry of the same kind
	/// (e.g. any `.executable(`) so the shape is recognized before appending.
	/// the insertion point is the end of the last non-whitespace line inside
	/// the body — the array's own close is OUTSIDE the returned range, so the
	/// entry lands between the last sibling and the closing bracket.
	static func insertBeforeClose(
		of body: Range<String.Index>,
		in text: inout String,
		needle: String,
		fallbackNeedle: String?,
		entry: String,
		ensureTrailingComma: Bool = false
	) -> Bool {
		let bodyText = String(text[body])
		if bodyText.contains(needle) {
			// already present — advisory, treated as success (idempotent).
			print("scaffold: \(needle) already present — skipped (idempotent)")
			return true
		}
		if let fallbackNeedle, !bodyText.contains(fallbackNeedle) {
			return false
		}
		// anchor after the LAST newline inside the body so the entry starts on
		// its own line, above the array's closing bracket (which sits after
		// body's trailing whitespace).
		let anchor: String.Index? = bodyText.lastIndex(of: "\n").map {
			let after = text.index(body.lowerBound, offsetBy: bodyText.distance(from: bodyText.startIndex, to: $0))
			return text.index(after: after)
		} ?? nil
		guard let anchor else { return false }
		// when the previous line is a closing bracket (e.g. the app target's
		// `dependencies: [...]` array), Swift needs a comma before the new
		// labeled argument line: append one to the `]` if it is not already
		// comma-terminated.
		if ensureTrailingComma {
			var cursor = text.index(before: anchor)
			// skip trailing whitespace on the previous line backwards
			while text[cursor] == " " || text[cursor] == "\t" || text[cursor] == "\n" {
				cursor = text.index(before: cursor)
			}
			if text[cursor] != "," {
				// insert the comma right after the last non-comma token char.
				var commaAt = text.index(after: cursor)
				// avoid double-comma when the line already ends with one.
				if text[commaAt] != "," {
					text.insert(",", at: commaAt)
				}
			}
		}
		text.insert(contentsOf: entry, at: anchor)
		return true
	}

	/// the character range of a target block body `name: "<app>",` up to its
	/// close paren, so the plugin line can be appended inside it. the search is
	/// restricted to the `targets:` array body so a PRODUCT entry's
	/// `name: "App"` (inside `products:`/`.executable(...)`) cannot match —
	/// only the actual `executableTarget`/`target` declaration.
	static func targetBlockRange(_ text: String, name: String) -> Range<String.Index>? {
		guard let targetsBody = arrayBodyRange(text, header: "targets:") else { return nil }
		let scope = text[targetsBody]
		guard let needleRange = scope.range(of: "name: \"\(name)\",") else { return nil }
		let needleStart = text.index(targetsBody.lowerBound, offsetBy: scope.distance(from: scope.startIndex, to: needleRange.lowerBound))
		// walk back to the open paren of the enclosing `.executableTarget( ... )`
		// / `.target( ... )` block — the first `(` at or before the name.
		var open: String.Index? = nil
		var cursor = needleStart
		while cursor > text.startIndex {
			cursor = text.index(before: cursor)
			if text[cursor] == "(" { open = cursor; break }
		}
		guard let open else { return nil }
		var depth = 0
		var index = open
		var inString = false
		while index < text.endIndex {
			let c = text[index]
			if inString {
				if c == "\\" {
					index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
					continue
				}
				if c == "\"" { inString = false }
			} else {
				if c == "\"" { inString = true }
				else if c == "(" { depth += 1 }
				else if c == ")" {
					depth -= 1
					if depth == 0 { return text.index(after: open)..<index }
				}
			}
			index = text.index(after: index)
		}
		return nil
	}
}
