#!/usr/bin/env bash
# designer/gates/scaffold-demo.sh — the DX-2 scaffold gate (lane B, W2).
#
# proves the scaffold verb end-to-end against a scratch home-dir CONSUMER app:
#   1. --bootstrap inserts the once-per-app inert continuum block
#      (framework path dep + WebUIAutobuildPlugin on the app target);
#   2. --add-island Feed appends the product + executableTarget (append-only
#      anchors) and generates Sources/Feed/main.swift — the 3-line runtime form
#      naming the macro-produced adapter Feed.FeedIsland (the string pinned in
#      BOTH this gate and lane D's expansion tests);
#   3. the developer writes the island logic (`Feed` + `Feed.FeedIsland`
#      conforming to IslandRuntimeSurface — here the hand-written equivalent,
#      the anti-shackle rule);
#   4. HOST: `swift build` of the consumer package compiles the generated main
#      natively (inert @main stub — the wasm bind is #if os(WASI) away);
#   5. WASM: `wasm-cross` cross-builds the same Sources/Feed via the swiftly
#      toolchain -> valid stripped embedded artifact (zero manual verbs — the
#      build did the cross-build, the gate re-invokes the verb only to prove
#      the fixture compiles for the wasm target as the autobuild would).
#
# the fixture's island logic is written by this script (the "developer's" file);
# the GENERATED main is not touched after scaffold.
set -euo pipefail

FRAMEWORK=${FRAMEWORK:-/tmp/continuum-fleet/lane-b}
DEMO=${DEMO:-$HOME/scaffold-demo-app}
TOOL=${TOOL:-$(find "$FRAMEWORK/.build" -name WebUIContinuumTool -type f | head -1)}
CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    --framework=*) FRAMEWORK="${arg#--framework=}" ;;
  esac
done

[ -n "$TOOL" ] || { echo "SCAFFOLDDEMO FAIL: WebUIContinuumTool binary not found"; exit 1; }
fail() { echo "SCAFFOLDDEMO FAIL: $1"; exit 1; }

if [ "$CLEAN" = 1 ]; then rm -rf "$DEMO"; fi
mkdir -p "$DEMO/Sources/App"
cat > "$DEMO/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "scaffold-demo-app",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
EOF
printf 'print("scaffold demo app")\n' > "$DEMO/Sources/App/main.swift"

echo "== step 1: BOOTSTRAP (once-per-app inert block) =="
"$TOOL" scaffold --bootstrap --name App --framework "$FRAMEWORK" --package-dir "$DEMO" >/dev/null
grep -q '.package(name: "no-webui"' "$DEMO/Package.swift" || fail "bootstrap did not add the dependency"
grep -q 'WebUIAutobuildPlugin' "$DEMO/Package.swift" || fail "bootstrap did not add the plugin"
echo "bootstrap: framework path dep + WebUIAutobuildPlugin on App OK"

echo "== step 2: ADD-ISLAND (append-only product+target + generated main) =="
"$TOOL" scaffold --add-island Feed --package-dir "$DEMO" >/dev/null
grep -q '.executable(name: "Feed"' "$DEMO/Package.swift" || fail "add-island did not append the product"
grep -q 'name: "Feed"' "$DEMO/Package.swift" || fail "add-island did not append the target"
[ -f "$DEMO/Sources/Feed/main.swift" ] || fail "add-island did not generate Sources/Feed/main.swift"
echo "add-island: product + executableTarget appended, main.swift generated"

# the generated main names the macro-produced adapter (pinned in BOTH suites).
grep -q 'IslandRuntime<Feed.FeedIsland>.run()' "$DEMO/Sources/Feed/main.swift" \
  || fail "generated main does not name the adapter Feed.FeedIsland"
grep -q 'GENERATED FILE — do not edit' "$DEMO/Sources/Feed/main.swift" \
  || fail "generated main lacks the generated-do-not-edit header"
echo "adapter pin: IslandRuntime<Feed.FeedIsland>.run() + generated header OK"

echo "== step 3: the developer writes the island logic (hand-written equivalent) =="
cat > "$DEMO/Sources/Feed/Feed.swift" <<'EOF'
// the developer's island logic — the hand-written equivalent of the
// @HotView-expanded adapter (anti-shackle rule 3). `Feed.FeedIsland`
// conforms to IslandRuntimeSurface, which is exactly what the generated main's
// IslandRuntime<Feed.FeedIsland>.run() binds. state/action at file scope so
// Codable rides the same `!hasFeature(Embedded)` guard the frame's probe uses.
import WebUIIslandCore
import WebUISharedCore

struct FeedState: IslandEmptyState {
    var count = 0
    init() {}
}

enum FeedAction: HotAction, Sendable {
    case increment
    case noop
}

#if !hasFeature(Embedded)
extension FeedState: Codable {}
extension FeedAction: Codable {}
#endif

enum Feed: Sendable {
    struct FeedIsland: IslandRuntimeSurface {
        typealias State = FeedState
        typealias Action = FeedAction
        static var name: String { "feed" }
        static var imports: [any HostCapability.Type] { [] }
        static var budget: IslandBudget { IslandBudget(maxBytes: 250_000, maxGzipBytes: 110_000) }
        static func reduce(state: inout State, action: Action) -> [HotEffect] {
            if case .increment = action { state.count += 1 }
            return []
        }
        static func decodeEvent(json: String) -> Action {
            // embedded-safe scalar probe (no Foundation substring APIs on wasm).
            json.utf8.firstIndex(where: { $0 == UInt8(ascii: "i") }) != nil ? .increment : .noop
        }
        static func regionHTML(state: State, renderCount: Int, eventCount: Int) -> String {
            "<div id=\"feed\" data-feed-count=\"\(state.count)\">count \(state.count)</div>"
        }
        static func stateToJSON(state: State, renderCount: Int, eventCount: Int) -> JSONValue {
            .object(["count": .number(Double(state.count))])
        }
        static func stateFromJSON(_ json: String) -> (state: State, renderCount: Int, eventCount: Int)? {
            (FeedState(), 0, 0)
        }
        static func consumeMountEnvelope(_ envelopeJSON: String, state: inout State) {}
    }
}
EOF

echo "== step 4: HOST compile (swift build of the consumer package) =="
swift build --package-path "$DEMO" > /tmp/scaffold-host.log 2>&1 \
  || { tail -30 /tmp/scaffold-host.log; fail "host build failed"; }
grep -q "Build complete" /tmp/scaffold-host.log || fail "host build did not complete"
echo "host: swift build OK (generated main compiles natively)"

echo "== step 5: WASM compile (wasm-cross over Sources/Feed, the autobuild path) =="
# the swiftly-hosted toolchain swiftc (a symlink — find -type f misses it, so
# take the latest toolchain's path directly, mirroring swiftcSelection()).
WASM_SWIFTC=""
for tc in "$HOME"/Library/Developer/Toolchains/*.xctoolchain; do
  [ -x "$tc/usr/bin/swiftc" ] && WASM_SWIFTC="$tc/usr/bin/swiftc"
done
[ -n "$WASM_SWIFTC" ] || WASM_SWIFTC="$HOME/.swiftly/bin/swiftc"
OBJ="$DEMO/.build/scaffold-wasm-obj"
OUT="$DEMO/.build/scaffold-feed.wasm"
rm -rf "$OBJ"
mkdir -p "$OBJ"
"$TOOL" wasm-cross \
  --graph "$FRAMEWORK" \
  --product Feed \
  --main-dir "$DEMO/Sources/Feed" \
  --obj "$OBJ" --out "$OUT" --swiftc "$WASM_SWIFTC" > /tmp/scaffold-wasm.log 2>&1 \
  || { tail -30 /tmp/scaffold-wasm.log; fail "wasm-cross failed"; }
[ -f "$OUT" ] || fail "no wasm artifact produced"
magic=$(head -c 8 "$OUT" | xxd -p)
[ "$magic" = "0061736d01000000" ] || fail "artifact is not valid wasm ($magic)"
grep -q "cross-built" /tmp/scaffold-wasm.log || fail "wasm-cross did not report success"
echo "wasm: wasm-cross OK ($(stat -f%z "$OUT") bytes, valid \\0asm stripped embedded)"

echo "== step 6: idempotent re-run (zero edits for the 2nd+ island) =="
"$TOOL" scaffold --add-island Feed --package-dir "$DEMO" >/dev/null || fail "idempotent re-run failed"
[ "$(grep -c '.executable(name: "Feed"' "$DEMO/Package.swift")" = "1" ] || fail "re-run duplicated the product entry"
echo "idempotent: re-run appended nothing, regenerated the main"

echo "== step 7: DX-8 verify — ONE verb, the FULL island verification path =="
# the plain getting-started path is zero-manual-verbs (`swift build` in step 4
# already cross-built + auto-pinned the island); `verify` is the ONE explicit
# belt-and-suspenders verb, running build -> cross-build -> measure/pin -> the
# budget row and printing a per-stage verdict over ITS OWN work dir. host build
# was proven in step 4, so --skip-swift-build keeps the gate fast; the
# cross-build + measure/pin + budget-row stages still run in full.
"$TOOL" verify \
  --package-dir "$DEMO" \
  --framework "$FRAMEWORK" \
  --skip-swift-build \
  --work-dir "$DEMO/.build/continuum-verify" > /tmp/scaffold-verify.log 2>&1 \
  || { tail -60 /tmp/scaffold-verify.log; fail "verify failed"; }
grep -q "verify: PASS" /tmp/scaffold-verify.log || { tail -60 /tmp/scaffold-verify.log; fail "verify did not PASS"; }
grep -q "\[verify\] 1/4 build: skipped" /tmp/scaffold-verify.log || fail "verify stage-1 marker missing"
grep -q "Feed" /tmp/scaffold-verify.log || fail "verify cross-build did not name the Feed island"
grep -q "budget: PASS" /tmp/scaffold-verify.log || fail "verify budget stage did not pass (WebUIBudgetPlugin must print budget: PASS over the measured pins)"
echo "verify: build → cross-build → measure/pin → budget row OK (one verb, zero manual steps)"

echo ""
echo "SCAFFOLDDEMO PASS — scaffold bootstraps an existing app, adds an island with the 3-line runtime form, the generated main compiles for BOTH host and wasm, and the DX-8 verify verb runs the full island verification path in one command."
