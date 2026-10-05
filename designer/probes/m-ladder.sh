#!/usr/bin/env bash
# LIVE_DX lane M — the consumer-deletion ladder, measured.
#
# per seam: the DELETED shape (arc-agent's real code, measured here) vs the
# SUBSTITUTED shape (the framework's conforming types, measured in the LIVE_DX
# demo — Sources/WebUIExample). every number in
# dx2-notes/m-consumer-deletion-ladder.md comes from this script; re-run it to
# reproduce them.
#
# provenance note: arc-agent is a MOVING tree. the numbers below are as of the
# sha this script prints; the plan's §1 figures came from a different (earlier)
# revision, and where the two disagree the measured value here wins and the
# discrepancy is recorded in the notes.
#
# usage:  bash designer/probes/m-ladder.sh [ARC_PATH] [WEBUI_PATH]

set -uo pipefail

ARC="${1:-$HOME/workspace/arc-agent}"
WEBUI="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEMO="$WEBUI/Sources/WebUIExample"
CHROME="$ARC/Sources/ArcTheme/ChromeSheet.swift"

echo "=== the ladder: deleted (arc) vs substituted (framework) ==="
echo "arc:    $ARC"
echo -n "arc sha: "; git -C "$ARC" log --oneline -1 2>/dev/null || echo "<not a git tree>"
echo "webui:  $WEBUI  ($(git -C "$WEBUI" log --oneline -1 2>/dev/null))"
echo "date:   $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo

# ─────────────────────────────────────────────────────────────────────────────
echo "### seam 1 — wiring (DX-12/14) ###"
SITES=$(grep -rho "wire(" "$ARC/Sources" --include="*.swift" | wc -l | tr -d ' ')
echo "arc: wire( occurrences: $SITES (one is the declaration at Actions.swift:1151)"
echo "     wire( REGISTRATION sites: $((SITES - 1))"
echo "arc: the hand btn() helper, Helpers.swift:74:"
awk 'NR>=74 && /^}/{print "     " NR-74+1 " lines"; exit}' "$ARC/Sources/ArcWebUI/Helpers.swift"
SAMPLE="queue"
M=$(grep -rho "data-component-id=\"$SAMPLE\"" "$ARC/Sources" --include="*.swift" | wc -l | tr -d ' ')
R=$(grep -rho "id: \"$SAMPLE\"" "$ARC/Sources" --include="*.swift" | wc -l | tr -d ' ')
echo "arc: one control ('$SAMPLE') is hand-stated in $M markup site(s) + $R registration site(s) = $((M + R)) touchpoints"
echo "framework: the demo's control call sites (one per interactive control):"
grep -c "demoControl(\|control(" "$DEMO/main.swift" | tr -d ' ' | sed 's/^/     /'
echo "framework: the routing attributes are EMITTED by control(_:handler:) — the id is stated once, at the call site"
echo

# ─────────────────────────────────────────────────────────────────────────────
echo "### seam 2 — the response shape (DX-14) ###"
echo -n "arc: hand-assembled FragmentUpdate( sites: "
grep -rho "FragmentUpdate(" "$ARC/Sources" --include="*.swift" | wc -l | tr -d ' '
echo -n "arc: files carrying them: "
grep -rl "FragmentUpdate(" "$ARC/Sources" --include="*.swift" | wc -l | tr -d ' '
echo "framework: the demo states INTENT as a type (occurrences):"
for t in ViewOutcome RegionInvalidations NoOutcome CombinedOutcome; do
	printf '     %-22s %s\n' "$t" "$(grep -rho "$t" "$DEMO/main.swift" | wc -l | tr -d ' ')"
done
echo -n "framework: hand-assembled FragmentUpdate( sites left in the demo: "
grep -rho "FragmentUpdate(" "$DEMO/main.swift" | wc -l | tr -d ' '
echo "     (the SWAP control uses the one-update shape on purpose — the union is the point; the rest state intent)"
echo

# ─────────────────────────────────────────────────────────────────────────────
echo "### seam 3 — the push layer (DX-13/16) ###"
echo "arc: actor PushDeduper (WebUIHost.swift:15):"
awk 'NR>=15 && NR<=40 && /^}/{print "     " NR-15+1 " lines"; exit}' "$ARC/Sources/ArcWebUI/WebUIHost.swift"
echo -n "arc: IntervalService.swift: "
wc -l < "$ARC/Sources/ArcWebUI/IntervalService.swift" | tr -d ' '
echo "arc: poll/timer vocabulary across the tree:"
grep -rho "Timer\.publish\|scheduledTimer\|DispatchSourceTimer\|Task\.sleep\|asyncAfter\|IntervalService\|startPolling" "$ARC/Sources" --include="*.swift" | sort | uniq -c | sort -rn | sed 's/^/     /'
echo "arc: recorded wire cost of one nav click (whole-#app replace): 136195 B  (plan §1 item 3 — the audit's measurement)"
echo -n "framework: a region push, measured live by g-regions.mjs: "
grep -hoE "frame [0-9]+ B <= html [0-9]+ B" /tmp/i2-g-regions.log 2>/dev/null | head -1 || echo "<run g-regions.mjs first>"
echo -n "framework: the demo's four-driver live-data block (the whole surface): "
awk '/MARK: - the four live-region drivers/{f=1} f{print}' "$DEMO/main.swift" | grep -c "" | tr -d ' '
echo "     lines (RegionTick + the custom struct region + the LiveState actor + DemoRegions + its 4 drivers + 2 html helpers)"
echo

# ─────────────────────────────────────────────────────────────────────────────
echo "### seam 4 — the theme pipeline (DX-15a) ###"
echo "arc: the hand-built tooling"
wc -l < "$ARC/Sources/ArcAssetTool/main.swift" 2>/dev/null | tr -d ' ' | sed 's/^/     ArcAssetTool\/main.swift      /'
find "$ARC/Plugins" -name "*.swift" 2>/dev/null | while read -r f; do wc -l < "$f" | tr -d ' ' | awk -v n="$(basename "$f")" '{printf "     %-28s %s lines\n", n, $1}'; done
echo -n "arc: + the Package.swift block for them: "
awk '/ArcAssetTool|ArcAssetPlugin/{c++} END{print c+0 " manifest mentions"}' "$ARC/Package.swift"
echo "framework: the consumer surface that replaces it"
echo "     the demo target's plugin line:                1  (plugins: [.plugin(name: \"WebUIThemePlugin\")])"
printf '     the catalog + the hand-written twin:          %s lines\n' "$(grep -c "" "$DEMO/DemoTheme.swift" | tr -d ' ')"
printf '     the sheet wiring (emit + serve + link):       %s sites\n' "$(grep -rho "demoThemeSheet()" "$DEMO/main.swift" | wc -l | tr -d ' ')"
echo

# ─────────────────────────────────────────────────────────────────────────────
echo "### seam 5 — styling: colliding classes (DX-15b) ###"
if [ -f "$CHROME" ]; then
	echo -n "arc: ${CHROME#$ARC/}: "; wc -l < "$CHROME" | tr -d ' ' | sed 's/$/ lines/'
	echo -n "     rule blocks ({ count): "; grep -o "{" "$CHROME" | wc -l | tr -d ' '
	echo "     the 9 DS classes it re-skins, with their mention counts:"
	for c in chip kv toast modal-overlay log-line md swatch inline-edit tool-btn; do
		printf '       %-14s %s\n' "$c" "$(grep -coE "\.$c([^a-zA-Z0-9_-]|$)" "$CHROME")"
	done
	echo -n "     classes shadowing the DS union: "; SHADOWED=0
	for c in chip kv toast modal-overlay log-line md swatch inline-edit tool-btn; do
		n=$(grep -coE "\.$c([^a-zA-Z0-9_-]|$)" "$CHROME"); [ "$n" -gt 0 ] && SHADOWED=$((SHADOWED + 1))
	done
	echo "$SHADOWED of 9"
else
	echo "arc: ${CHROME#$ARC/} NOT FOUND"
fi
echo -n "framework: the shadow lint over the demo tree: "
if [ -x "$WEBUI/.build/out/Products/Debug/WebUIContinuumTool" ]; then
	"$WEBUI/.build/out/Products/Debug/WebUIContinuumTool" shadow --sources "$DEMO" --demo 2>&1 | tail -1 | sed 's/\[WebUIContinuumTool\] //'
else
	echo "(build WebUIContinuumTool to run the lint)"
fi
echo
echo "=== end of the ladder ==="