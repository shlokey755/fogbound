#!/usr/bin/env bash
# Runs every headless test in this project against a local Godot 4.3
# binary. See docs/WALKTHROUGH.md "Testing" for how to get one.
#
# Usage: GODOT=/path/to/godot ./tests/run_all_tests.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

# Import assets first: sprite sheets are PNGs, and a fresh clone has no
# imported copies until the editor (or this) generates them.
echo "== Importing assets =="
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
echo

echo "== Pure-logic tests (PodGraph, ScoreTable) =="
"$GODOT" --headless --path . --script res://tests/test_pod_graph.gd

echo
echo "== Maze generator tests =="
"$GODOT" --headless --path . --script res://tests/test_maze_generator.gd

echo
echo "== Bot AI tests (navigation, mission, brain, simulated matches) =="
"$GODOT" --headless --path . --script res://tests/test_bots.gd

echo
echo "== Full scene boot smoketest (game.tscn, real autoloads, offline bot matches) =="
# --fixed-fps 60 runs physics as fast as the CPU allows, so the offline
# autoplay passes (several simulated minutes) take seconds, not minutes.
# A script that fails to parse leaves this scene idling forever instead of
# failing, hence the timeout and the explicit result check.
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
if ! timeout 300 "$GODOT" --headless --fixed-fps 60 --path . res://tests/boot_smoketest.tscn | tee "$LOG"; then
	echo "boot smoketest failed or timed out" >&2
	exit 1
fi
if ! grep -q "^ALL TESTS PASSED" "$LOG"; then
	echo "boot smoketest did not report ALL TESTS PASSED" >&2
	exit 1
fi

echo
echo "All test suites passed."
