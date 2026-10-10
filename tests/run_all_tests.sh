#!/usr/bin/env bash
# Runs every headless test in this project against a local Godot 4.3
# binary. See docs/WALKTHROUGH.md "Testing" for how to get one.
#
# Usage: GODOT=/path/to/godot ./tests/run_all_tests.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

echo "== Pure-logic tests (PodGraph, ScoreTable) =="
"$GODOT" --headless --path . --script res://tests/test_pod_graph.gd

echo
echo "== Maze generator tests =="
"$GODOT" --headless --path . --script res://tests/test_maze_generator.gd

echo
echo "== Full scene boot smoketest (game.tscn, real autoloads) =="
"$GODOT" --headless --path . res://tests/boot_smoketest.tscn

echo
echo "All test suites passed."
