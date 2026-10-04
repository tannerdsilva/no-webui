#!/usr/bin/env bash
# designer/gates/dx5-demo.sh — the DX-5 demo-or-kill runner (CONTINUUM_DX §2.5).
#
# proves candidate (b): a build-tool plugin cross-builds the REAL island graph
# inside a plain `swift build` of a HOME-DIRECTORY scratch app, producing the
# artifacts in the sandbox-writable plugin work dir. measures the cold/warm
# costs, the source-edit invalidation, the llbuild warm-skip, and the named
# missing-prereq diagnostic.
#
# usage:
#   bash designer/gates/dx5-demo.sh [--clean] [--framework /tmp/continuum-fleet/lane-b]
#
# the demo app lives at "$HOME/dx-demo" (a home-dir checkout — never /tmp, so
# the sandbox's write map is the real one a developer hits). reruns are
# idempotent: setup rewrites the app's sources, and the invalidation edit is
# reverted at the end.
set -euo pipefail

FRAMEWORK=${FRAMEWORK:-/tmp/continuum-fleet/lane-b}
DEMO=${DEMO:-$HOME/dx-demo}
CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    --framework=*) FRAMEWORK="${arg#--framework=}" ;;
  esac
done

ARTDIR="$DEMO/.build/plugins/outputs/dx-demo/DemoApp/destination/WebUIAutobuildPlugin"
PLUGIN_NAME=WebUIAutobuildPlugin
# ms-precision timing for a command (prints "label <ms>")
timed() { # label cmd...
  local label="$1"; shift
  python3 -c '
import subprocess, sys, time
label, cmd = sys.argv[1], sys.argv[2:]
t0 = time.monotonic()
r = subprocess.run(cmd)
print(f"{label} {int((time.monotonic()-t0)*1000)} ms")
sys.exit(r.returncode)
' "$label" "$@"
}

setup_app() {
  rm -rf "$DEMO"
  mkdir -p "$DEMO/Sources/DemoApp" "$DEMO/Sources/FeedIsland"
  cat > "$DEMO/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dx-demo",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DemoApp", targets: ["DemoApp"]),
        .executable(name: "FeedIsland", targets: ["FeedIsland"]),
    ],
    dependencies: [
        .package(name: "no-webui", path: "$FRAMEWORK"),
    ],
    targets: [
        .executableTarget(
            name: "DemoApp",
            dependencies: [
                .product(name: "WebUI", package: "no-webui"),
                .product(name: "WebUIDesignSystem", package: "no-webui"),
                .product(name: "WebUIServer", package: "no-webui"),
            ],
            plugins: [.plugin(name: "WebUIAutobuildPlugin", package: "no-webui")]
        ),
        .executableTarget(
            name: "FeedIsland",
            dependencies: [
                .product(name: "WebUIIslandCore", package: "no-webui"),
                .product(name: "WebUISharedCore", package: "no-webui"),
            ]
        ),
    ]
)
EOF
  # the consumer host: a WebUIServer that reads the island artifacts from the
  # WebUIAutobuildPlugin work dir (the DX-6b seam). zero manual verbs — a plain
  # `swift build` cross-built them, and this `swift run` serves them.
  cat > "$DEMO/Sources/DemoApp/main.swift" <<'EOF'
import Foundation
import Logging
import WebUI
import WebUIDesignSystem
import WebUIServer

@main
struct DemoApp {
    static func main() async throws {
        let port = CommandLine.arguments.firstIndex(of: "--port").flatMap {
            Int(CommandLine.arguments[$0 + 1])
        } ?? 9301
        // the autobuild work dir: the sandbox-writable zone the build command
        // wrote the islands into (never .build/out/Products on a home dir).
        let workDir = CommandLine.arguments.firstIndex(of: "--work-dir").map {
            $0 + 1
        }.flatMap { CommandLine.arguments.indices.contains($0) ? CommandLine.arguments[$0] : nil }
            ?? ".build/plugins/outputs/dx-demo/DemoApp/destination/WebUIAutobuildPlugin"

        let router = EventRouter()
        let body = RenderContext.$current.withValue(RenderContext(router: router)) {
            Div(class: "bench") {
                Heading("dx-demo — island served from the autobuild work dir", level: .h1)
                WebUIIsland("feed", args: .empty)
            }.render()
        }
        let page = WebUIDocument(
            title: "dx-demo seam",
            body: body
        ).render()
        let server = WebUIServer(
            render: { page },
            router: router,
            config: WebUIServerConfig(
                host: "127.0.0.1", port: port,
                islandWorkDirectory: URL(fileURLWithPath: workDir)
            )
        )
        print("dx-demo seam server on http://127.0.0.1:\(port) (island work dir: \(workDir))")
        try await server.start()
    }
}
EOF
  # the consumer island: the W2 3-line runtime form (CONTINUUM_DX DX-1, lane C).
  # the scaffold emits exactly this shape for a new island — the island adapter
  # type is the frame's ProbeIsland here (the demo's stand-in for a consumer's
  # hand-written `ContinuumIsland`).
  cat > "$DEMO/Sources/FeedIsland/main.swift" <<'EOF'
import WebUIIslandCore
import WebUISharedCore

@main
struct FeedIsland {
    static func main() {}
}

#if os(WASI)
@_silgen_name("webui_island_bind")
func webuiIslandBind() {
    IslandRuntime<ProbeIsland>.run()
}
#endif
EOF
}

fail() { echo "DX5DEMO FAIL: $1"; exit 1; }

echo "== setup =="
setup_app
if [ "$CLEAN" = 1 ]; then rm -rf "$DEMO/.build"; fi

echo "== step A: COLD — plain swift build (home-dir app, no flags) =="
timed "cold" swift build --package-path "$DEMO" > /tmp/dxdemo-cold.log 2>&1 || fail "cold build failed — see /tmp/dxdemo-cold.log"
grep -q "Build complete" /tmp/dxdemo-cold.log || fail "cold build did not complete"
CROSS_LINES=$(grep -c "\[WebUIAutobuild\] .* cross-built" /tmp/dxdemo-cold.log || true)
echo "cold: $CROSS_LINES island cross-build log lines"

echo "== step A2: artifact assertions (sandbox-writable plugin work dir) =="
for island in WebUIProbeIsland WebUIValidateIsland FeedIsland; do
  artifact="$ARTDIR/$island.wasm"
  [ -f "$artifact" ] || fail "missing artifact $artifact"
  magic=$(head -c 8 "$artifact" | xxd -p)
  [ "$magic" = "0061736d01000000" ] || fail "$island.wasm bad magic: $magic"
  size=$(stat -f%z "$artifact")
  echo "ARTIFACT $island.wasm: $size bytes (valid wasm, stripped embedded)"
done

echo "== step B: WARM — no edits; llbuild must skip the cross-build commands =="
timed "warm" swift build --package-path "$DEMO" > /tmp/dxdemo-warm.log 2>&1 || fail "warm build failed"
grep -q "Build complete" /tmp/dxdemo-warm.log || fail "warm build did not complete"
RE_RAN=$(grep -c "\[WebUIAutobuild\] .* cross-built" /tmp/dxdemo-warm.log || true)
echo "warm: $RE_RAN cross-build re-runs (expect 0)"
[ "$RE_RAN" = "0" ] || fail "warm build re-ran cross-builds: $RE_RAN (llbuild inputs/outputs not declared?)"

echo "== step C: INVALIDATE — edit the consumer island source; only it rebuilds =="
BEFORE_MTIME=$(stat -f%m "$ARTDIR/FeedIsland.wasm")
PROBE_MTIME=$(stat -f%m "$ARTDIR/WebUIProbeIsland.wasm")
printf '\n// invalidation probe (runner)\n' >> "$DEMO/Sources/FeedIsland/main.swift"
timed "invalidate" swift build --package-path "$DEMO" > /tmp/dxdemo-inv.log 2>&1 || fail "invalidate build failed"
RE_RAN=$(grep -c "\[WebUIAutobuild\] .* cross-built" /tmp/dxdemo-inv.log || true)
grep -q "FeedIsland: cross-built" /tmp/dxdemo-inv.log || fail "FeedIsland was not re-cross-built after its source edit"
AFTER_MTIME=$(stat -f%m "$ARTDIR/FeedIsland.wasm")
[ "$AFTER_MTIME" != "$BEFORE_MTIME" ] || fail "FeedIsland.wasm mtime unchanged after source edit"
[ "$(stat -f%m "$ARTDIR/WebUIProbeIsland.wasm")" = "$PROBE_MTIME" ] || fail "unrelated island WebUIProbeIsland was rebuilt (input set too broad)"
echo "invalidate: FeedIsland re-cross-built (re-runs: $RE_RAN); probe untouched"

echo "== step D: NAMED PREREQ DIAGNOSTIC — missing wasm swiftc =="
printf '\n// diagnostic probe (runner)\n' >> "$DEMO/Sources/FeedIsland/main.swift"
set +e
WEBUI_WASM_SWIFTC=/nonexistent/wasm-swiftc swift build --package-path "$DEMO" > /tmp/dxdemo-diag.log 2>&1
DIAG_EXIT=$?
set -e
[ "$DIAG_EXIT" != 0 ] || fail "missing-prereq build unexpectedly succeeded"
grep -q "\[WebUIAutobuild\] cannot cross-build" /tmp/dxdemo-diag.log || fail "missing-prereq failure did not carry the named WebUIAutobuild diagnostic"
grep -qiE "swiftc|swiftly" /tmp/dxdemo-diag.log || fail "named diagnostic does not name the requirement (swiftly/swiftc)"
echo "diagnostic: build failed (exit $DIAG_EXIT) with the named requirement, e.g.:"
grep -m1 "\[WebUIAutobuild\] cannot cross-build" /tmp/dxdemo-diag.log | head -1

echo "== step E: recursion-guard backstop (direct wasm-cross, WEBUI_ISLAND_NESTED=1) =="
TOOL="$(find "$FRAMEWORK/.build/out/Products" -name WebUIContinuumTool -type f 2>/dev/null | head -1)"
if [ -z "$TOOL" ]; then
  TOOL="$(find "$DEMO/.build" -name WebUIContinuumTool -type f 2>/dev/null | head -1)"
fi
[ -n "$TOOL" ] || fail "WebUIContinuumTool binary not found"
GUARD_OUT=$(WEBUI_ISLAND_NESTED=1 "$TOOL" wasm-cross --graph "$FRAMEWORK" --product WebUIProbeIsland --obj /tmp/dxdemo-guard-obj --out /tmp/dxdemo-guard-out.wasm 2>&1 || true)
echo "$GUARD_OUT" | grep -q "recursion guard set" || fail "recursion guard did not short-circuit: $GUARD_OUT"
[ ! -f /tmp/dxdemo-guard-out.wasm ] || fail "guard run wrote an artifact"
echo "guard: WEBUI_ISLAND_NESTED=1 short-circuits the cross-build (no artifact, no recursion)"

echo "== step F: SERVING SEAM — the consumer's served page reads the work-dir artifacts (DX-6b) =="
# the app's DemoApp (WebUIServer) serves the islands the autobuild put in the
# work dir; fetch the existing URL convention + the merged manifest.
DEMO_BIN="$(find "$DEMO/.build" -name DemoApp -type f 2>/dev/null | head -1)"
[ -n "$DEMO_BIN" ] || fail "DemoApp binary not found after the seam build"
SEAM_PORT=9319
"$DEMO_BIN" --port "$SEAM_PORT" --work-dir "$ARTDIR" > /tmp/dxdemo-seam.log 2>&1 &
SEAM_PID=$!
cleanup_seam() { kill "$SEAM_PID" 2>/dev/null; wait "$SEAM_PID" 2>/dev/null; }
trap cleanup_seam EXIT
READY=0
for _ in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:$SEAM_PORT/" >/dev/null 2>&1; then READY=1; break; fi
  sleep 0.25
done
[ "$READY" = 1 ] || fail "seam server did not come up — see /tmp/dxdemo-seam.log"
# the page itself references the island region.
curl -sf "http://127.0.0.1:$SEAM_PORT/" > /tmp/dxdemo-seam-page.html || fail "seam page fetch failed"
grep -q 'data-webui-island="feed"' /tmp/dxdemo-seam-page.html || fail "seam page does not render the island region"
# the existing URL convention serves the work-dir artifact byte-for-byte.
curl -sf "http://127.0.0.1:$SEAM_PORT/__assets/webui-feed.wasm" > /tmp/dxdemo-seam-feed.wasm || fail "seam island fetch failed (webui-feed.wasm)"
cmp -s /tmp/dxdemo-seam-feed.wasm "$ARTDIR/FeedIsland.wasm" || fail "served island bytes != work-dir artifact (seam)"
[ "$(head -c 4 /tmp/dxdemo-seam-feed.wasm | xxd -p)" = "0061736d" ] || fail "served island is not valid wasm (seam)"
# the merged manifest carries the measured islands rows (DX-3) + the
# generate-path sections.
curl -sf "http://127.0.0.1:$SEAM_PORT/ui/continuum-manifest.json" > /tmp/dxdemo-seam-manifest.json || fail "seam manifest fetch failed"
python3 - "$ARTDIR/ContinuumManifest.json" /tmp/dxdemo-seam-manifest.json <<'PY'
import json, sys
work = json.load(open(sys.argv[1]))["islands"]
served_text = open(sys.argv[2]).read()
served = json.loads(served_text)
assert served["kind"] == "continuum-engine-slice"
assert served["version"] == 2, served["version"]
assert "attributeAllowlist" in served and "components" in served and "union" in served, "generate path must stay authoritative"
assert served["islands"], "islands[] must be merged"
by_name = {r["name"]: r for r in served["islands"]}
for row in work:
    assert row["name"] in by_name, f"missing island {row['name']}"
    got = by_name[row["name"]]
    for key in ("maxBytes", "maxGzipBytes", "raw", "gz", "sha", "url"):
        assert key in got, f"island {row['name']} missing {key}"
print("seam manifest: generate path +", len(served["islands"]), "measured islands merged (version 2)")
PY
[ $? -eq 0 ] || fail "seam manifest merge assertion failed"
kill "$SEAM_PID" 2>/dev/null || true
wait "$SEAM_PID" 2>/dev/null || true
trap - EXIT
echo "seam: served page + island artifact + merged manifest all read from the autobuild work dir (zero manual verbs)"

echo ""
echo "DX5DEMO PASS — candidate (b) cross-builds the real island graph from a plain swift build in a home-dir app."
