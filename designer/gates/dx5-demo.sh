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
  cat > "$DEMO/Sources/DemoApp/main.swift" <<'EOF'
print("dx-demo app — islands cross-built by WebUIAutobuildPlugin inside this swift build")
EOF
  # the consumer island: the demo-owned reactor shell (see report/b-docs).
  cat > "$DEMO/Sources/FeedIsland/main.swift" <<'EOF'
import WebUIIslandCore
import WebUISharedCore

@main
struct FeedIsland {
    static func main() {}
}

#if os(WASI)
private let frameCapacity = 1 << 17
private let inputCapacity = 1 << 16
nonisolated(unsafe) private var retained = ProbeState()

@_expose(wasm, "webui_input_ptr")
func webuiInputPtr() -> Int { Int(bitPattern: InputBuffer.buffer) }
@_expose(wasm, "webui_frame_ptr")
func webuiFramePtr() -> Int { Int(bitPattern: FrameBuffer.buffer) }
@_expose(wasm, "webui_frame_len")
func webuiFrameLen() -> Int { FrameBuffer.length }
@_expose(wasm, "webui_render_region")
func webuiRenderRegion(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
    guard let ptr, len > 0 else { return 0 }
    _ = utf8Decode(ptr, len)
    writeFrame(ProbeIsland.regionHTML(state: retained, renderCount: 0, eventCount: 0))
    return webuiFramePtr()
}
@_expose(wasm, "webui_on_event")
func webuiOnEvent(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
    guard let ptr, len > 0 else { return 0 }
    let action = ProbeIsland.decodeEvent(json: utf8Decode(ptr, len))
    var state = retained
    let ops = ProbeIsland.reduceOps(state: &state, action: action)
    retained = state
    if !ops.isEmpty, let record = try? HotOpCodec.encodeBatch(ops) { writeFrameBytes(record) }
    return webuiFramePtr()
}
@_expose(wasm, "webui_take_ops")
func webuiTakeOps() -> UInt32 { UInt32(FrameBuffer.length) }

private func utf8Decode(_ ptr: UnsafeRawPointer, _ len: Int) -> String {
    let bytes = UnsafeRawBufferPointer(start: ptr, count: len)
    var out = ""; var i = 0
    while i < len {
        let b = bytes[i]; let scalar: UInt32; let width: Int
        if b < 0x80 { scalar = UInt32(b); width = 1 }
        else if (b & 0xE0) == 0xC0, i + 1 < len, (bytes[i + 1] & 0xC0) == 0x80 {
            scalar = (UInt32(b & 0x1F) << 6) | UInt32(bytes[i + 1] & 0x3F); width = 2
        } else if (b & 0xF0) == 0xE0, i + 2 < len, (bytes[i + 1] & 0xC0) == 0x80, (bytes[i + 2] & 0xC0) == 0x80 {
            scalar = (UInt32(b & 0x0F) << 12) | (UInt32(bytes[i + 1] & 0x3F) << 6) | UInt32(bytes[i + 2] & 0x3F); width = 3
        } else if (b & 0xF8) == 0xF0, i + 3 < len, (bytes[i + 1] & 0xC0) == 0x80, (bytes[i + 2] & 0xC0) == 0x80, (bytes[i + 3] & 0xC0) == 0x80 {
            scalar = (UInt32(b & 0x07) << 18) | (UInt32(bytes[i + 1] & 0x3F) << 12) | (UInt32(bytes[i + 2] & 0x3F) << 6) | UInt32(bytes[i + 3] & 0x3F); width = 4
        } else { out.unicodeScalars.append("\u{FFFD}"); i += 1; continue }
        if let v = Unicode.Scalar(scalar) { out.unicodeScalars.append(v) } else { out.unicodeScalars.append("\u{FFFD}") }
        i += width
    }
    return out
}
private func writeFrame(_ text: String) {
    let n = min(text.utf8.count, frameCapacity)
    text.withCString { c in FrameBuffer.buffer.copyMemory(from: UnsafeRawPointer(c), byteCount: n) }
    FrameBuffer.length = n
}
private func writeFrameBytes(_ bytes: [UInt8]) {
    bytes.withUnsafeBufferPointer { buf in
        FrameBuffer.buffer.copyMemory(from: UnsafeRawPointer(buf.baseAddress!), byteCount: buf.count)
    }
    FrameBuffer.length = bytes.count
}
private enum FrameBuffer {
    nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: frameCapacity, alignment: 16)
    nonisolated(unsafe) static var length = 0
}
private enum InputBuffer {
    nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: inputCapacity, alignment: 16)
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

echo ""
echo "DX5DEMO PASS — candidate (b) cross-builds the real island graph from a plain swift build in a home-dir app."
