import Dispatch
import Foundation
import Synchronization
import WebUI
import WebUIDesignSystem
import WebUIShowcaseContent
import WebUISmokeShared

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - WebUIBench
//
// the repo's first benchmark target — the number the plan's §12 row and D6's
// allocation gate read. it renders two pages that already exist (the hydration
// smoke view and the full showcase) and prints one row per page:
//
// - `µs/render`: wall time of one full page render, mean over the measured
//   iterations, and the fastest observed;
// - `bytes`: the rendered page's utf-8 byte count — the showcase row must equal
//   the artifact pin (`168,671`), so the bench cannot drift onto a page nobody
//   ships;
// - `allocs/render`: how many allocations one render performs. counted on
//   macOS through libmalloc's `malloc_logger` hook, in a pass of its own so the
//   hook never inflates the timed window; the hook is looked up at run time, so
//   a platform (or a libmalloc that stops exporting it) prints
//   `n/a (platform)` instead. never estimated, never synthesised;
// - `peak RSS`: `getrusage(RUSAGE_SELF).ru_maxrss`, converted from the
//   platform's unit (bytes on darwin, kibibytes on linux).

// MARK: - pages

/// one row: a page name and a render that returns its full html.
struct BenchPage {
	let name: String
	let render: () -> String
}

/// the two pages, each holding one router for the whole run — the shape a
/// long-lived server has, so a re-render is measured as a re-render.
///
/// the document wraps the snapshot exactly as `WebUIShowcase/main.swift` does:
/// the page body renders under its own `RenderContext`, the document around it
/// does not. that split is what keeps the showcase row's byte count equal to
/// the artifact pin rather than a few bytes off it.
private func benchPages() -> [BenchPage] {
	let smokeRouter = EventRouter()
	let smokeModel = HydrationViewModel()
	let smoke = BenchPage(name: "smoke (hydration view)") {
		// the server starts a render pass before every page: the mint counters
		// restart, so ids are `c0…cN` on every render (and, for the showcase,
		// identical to the artifact's throwaway-router render).
		smokeRouter.begin(.default)
		let body = RenderContext.$current.withValue(RenderContext(router: smokeRouter)) {
			HydrationView(model: smokeModel).markup
		}
		return WebUIDocument(title: "Hydration Gate", body: body, includeRuntime: false).markup.html
	}

	let showcaseRouter = EventRouter()
	let showcaseState = ShowcaseState()
	let showcase = BenchPage(name: "showcase (full page)") {
		showcaseRouter.begin(.default)
		let body = RenderContext.$current.withValue(RenderContext(router: showcaseRouter)) {
			ShowcasePage(state: showcaseState).markup
		}
		return WebUIDocument(title: "WebUI Showcase", body: body, includeRuntime: false).markup.html
	}

	return [smoke, showcase]
}

// MARK: - allocation counting

#if canImport(Darwin)

/// libmalloc calls this hook for every allocation, free and realloc it
/// performs — the mechanism Apple's own malloc tools drive.
private typealias MallocLoggerFn = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

/// `MALLOC_LOG_TYPE_ALLOCATE`: set on the events that hand memory out.
private let mallocLogTypeAllocate: UInt32 = 2

/// allocation events seen while the hook is installed.
private let mallocEventCount = Atomic<Int>(0)

/// the address of libmalloc's `malloc_logger` variable, or `nil` when the
/// running libmalloc does not export it.
private func mallocLoggerSlot() -> UnsafeMutablePointer<MallocLoggerFn?>? {
	guard let handle = dlopen(nil, RTLD_NOW),
		let symbol = dlsym(handle, "malloc_logger")
	else { return nil }
	return symbol.assumingMemoryBound(to: MallocLoggerFn?.self)
}

/// the allocation count of one render: the hook's events over `iterations`
/// renders, divided by `iterations`.
///
/// the counted renders run in their own pass — the hook calls back out of
/// libmalloc on every allocation, which would slow a window it was measuring.
private func allocationsPerRender(iterations: Int, render: () -> String) -> Int? {
	guard iterations > 0, let slot = mallocLoggerSlot() else { return nil }
	let handler: MallocLoggerFn = { type, _, _, _, _, _ in
		// the callback runs inside the allocator, so it may not allocate: it
		// does nothing but bump the counter.
		if type & mallocLogTypeAllocate != 0 {
			mallocEventCount.add(1, ordering: .relaxed)
		}
	}
	let before = mallocEventCount.load(ordering: .relaxed)
	slot.pointee = handler
	var sink = 0
	for _ in 0..<iterations { sink &+= render().utf8.count }
	slot.pointee = nil
	let after = mallocEventCount.load(ordering: .relaxed)
	// keep the render from being elided: its only observed effect is the count
	if sink == Int.min { print("") }
	return (after - before) / iterations
}

#endif

// MARK: - measurement

/// the process's peak resident set size, in bytes.
private func peakResidentBytes() -> UInt64 {
	var usage = rusage()
	getrusage(RUSAGE_SELF, &usage)
	#if canImport(Darwin)
	// darwin reports bytes
	return UInt64(max(0, usage.ru_maxrss))
	#else
	// linux reports kibibytes
	return UInt64(max(0, usage.ru_maxrss)) * 1024
	#endif
}

/// one page's measured row.
struct Measurement {
	let name: String
	let bytes: Int
	let meanMicroseconds: Double
	let bestMicroseconds: Double
	/// nil where no allocation hook exists.
	let allocationsPerRender: Int?
}

private func measure(_ page: BenchPage, warmup: Int, iterations: Int) -> Measurement {
	// warm up: first-touch page faults, lazy metadata, and the string tables a
	// cold render builds must not land in the measured window.
	for _ in 0..<warmup {
		_ = page.render()
	}

	var samples = [UInt64]()
	samples.reserveCapacity(iterations)
	var bytes = 0
	for _ in 0..<iterations {
		let start = DispatchTime.now().uptimeNanoseconds
		let html = page.render()
		let elapsed = DispatchTime.now().uptimeNanoseconds - start
		bytes = html.utf8.count
		samples.append(elapsed)
	}

	let total = samples.reduce(0, +)
	let best = samples.min() ?? 0

	var allocations: Int?
	#if canImport(Darwin)
	allocations = allocationsPerRender(iterations: iterations, render: page.render)
	#endif

	return Measurement(
		name: page.name,
		bytes: bytes,
		meanMicroseconds: Double(total) / Double(max(iterations, 1)) / 1_000,
		bestMicroseconds: Double(best) / 1_000,
		allocationsPerRender: allocations
	)
}

// MARK: - table

private func pad(_ text: String, to width: Int, alignRight: Bool = false) -> String {
	guard text.count < width else { return text }
	let filler = String(repeating: " ", count: width - text.count)
	return alignRight ? filler + text : text + filler
}

/// `1,234,567` — a number a human can scan.
private func grouped(_ value: Int) -> String {
	let digits = String(value)
	var out = ""
	for (offset, character) in digits.reversed().enumerated() {
		if offset > 0, offset % 3 == 0 { out.append(",") }
		out.append(character)
	}
	return String(out.reversed())
}

private func formatMegabytes(_ bytes: UInt64) -> String {
	String(format: "%.1f MiB", Double(bytes) / (1024 * 1024))
}

private func printTable(_ rows: [Measurement], iterations: Int, warmup: Int) {
	let headers = ["page", "bytes", "µs/render", "best µs", "allocs/render", "peak RSS"]
	let rowsText: [[String]] = rows.map { row in
		[
			row.name,
			grouped(row.bytes),
			String(format: "%.1f", row.meanMicroseconds),
			String(format: "%.1f", row.bestMicroseconds),
			row.allocationsPerRender.map(grouped) ?? "n/a (platform)",
			formatMegabytes(peakResidentBytes()),
		]
	}

	var widths = headers.map(\.count)
	for row in rowsText {
		for (index, cell) in row.enumerated() {
			widths[index] = max(widths[index], cell.count)
		}
	}

	print("no-webui render bench — \(iterations) measured renders, \(warmup) warm-up")
	print("")
	print(zip(headers, widths).map { pad($0, to: $1) }.joined(separator: "  "))
	print(widths.map { String(repeating: "─", count: $0) }.joined(separator: "  "))
	for row in rowsText {
		let line = zip(row, widths)
			.enumerated()
			.map { index, pair in pad(pair.0, to: pair.1, alignRight: index > 0) }
			.joined(separator: "  ")
		print(line)
	}
	print("")
	print("notes: `allocs/render` counts libmalloc allocation events on macOS")
	print("(`malloc_logger`, counted in a pass of its own so the timing is not slowed);")
	print("a platform without that hook prints `n/a (platform)`. `peak RSS` is the")
	print("process high-water mark after the run, not a per-page resident set.")
}

// MARK: - main

let benchArguments = CommandLine.arguments
private func intArgument(_ name: String, default fallback: Int) -> Int {
	guard let index = benchArguments.firstIndex(of: name), index + 1 < benchArguments.count,
		let value = Int(benchArguments[index + 1]), value > 0
	else { return fallback }
	return value
}

let iterations = intArgument("--iterations", default: 100)
let warmup = intArgument("--warmup", default: 10)

let measurements = benchPages().map { measure($0, warmup: warmup, iterations: iterations) }
printTable(measurements, iterations: iterations, warmup: warmup)
