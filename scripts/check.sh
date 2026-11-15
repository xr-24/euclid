#!/usr/bin/env bash
# Linux counterpart of check.ps1, for agents working in a Linux shell: the Godot core tests,
# the headless world smoke test and the gateway tests. Needs Node 22 and the Linux Godot 4.7.2
# build at .tools/godot/Godot_v4.7.2-stable_linux.x86_64 (or GODOT_BIN). EUCLID_CHECK_SCOPE=gateway
# skips the Godot steps, as in check.ps1. Logs go to .local/checks/.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT_BIN:-$root/.tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
logs="$root/.local/checks"
mkdir -p "$logs"

godot_check() {
	local marker=$1 name=$2
	shift 2
	local output status
	output=$("$godot" "$@" 2>&1)
	status=$?
	printf '%s\n' "$output" > "$logs/$name.log"
	if [ $status -ne 0 ] || grep -Eq '^(SCRIPT ERROR|ERROR):' <<<"$output" || ! grep -q "$marker" <<<"$output"; then
		printf '%s\n' "$output" | head -60
		echo "Godot check failed: $marker (full log: .local/checks/$name.log)"
		exit 1
	fi
	echo "$marker"
}

cd "$root"
if [ "${EUCLID_CHECK_SCOPE:-}" = "gateway" ]; then
	echo "Gateway-only check: skipping the Godot core and smoke tests."
elif [ ! -x "$godot" ]; then
	echo "No Linux Godot at $godot. Put the 4.7.2 Linux build there or set GODOT_BIN."
	exit 2
else
	godot_check CONSTRUCT_CORE_TESTS_OK core --headless --path world --script res://scripts/diagnostics/core_tests.gd --quit-after 1800
	godot_check CONSTRUCT_SMOKE_OK smoke --headless --path world --quit-after 3600 -- --smoke
	godot_check HOT_CHECK_OK hot --headless --path world --quit-after 3600 -- --hot-check
fi
if [ "${EUCLID_CHECK_SCOPE:-}" = "world" ]; then
	echo "World-only check: skipping the gateway tests, which do not read Godot scripts, shaders or scenes."
else
	GODOT_BIN="$godot" npm test || { echo "Gateway integration tests failed."; exit 1; }
fi
echo "All Euclid checks passed."
