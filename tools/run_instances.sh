#!/usr/bin/env bash
# Opens several Fogbound windows on ONE computer so you can test the hosted
# (hotspot) game without a second device. Window 1 hosts, the rest join it.
#
# Usage:   GODOT=/path/to/godot tools/run_instances.sh [WINDOWS]
#   WINDOWS  how many windows, 2 to 4 (default 2)
#
# Each window is small (640x360) and tiled in a grid. Click in a window to
# give it the keyboard, then use WASD/arrows to move that window's player.
# Everything after `--` goes to the game, not to Godot (see scripts/main_menu.gd).
set -euo pipefail

GODOT="${GODOT:-godot}"
COUNT="${1:-2}"
cd "$(dirname "$0")/.."

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 2 ] || [ "$COUNT" -gt 4 ]; then
	echo "WINDOWS must be a number from 2 to 4 (got '$COUNT')" >&2
	exit 1
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "Cannot find Godot. Set GODOT=/full/path/to/godot (see docs/PROCESS.md, step 1)." >&2
	exit 1
fi

# First run on a fresh clone: import the art so the sprites show up.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

NAMES=(Host Ann Ben Cy)
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

for ((i = 0; i < COUNT; i++)); do
	X=$(( (i % 2) * 660 ))
	Y=$(( (i / 2) * 420 ))
	if [ "$i" -eq 0 ]; then
		ROLE="--auto-host"
	else
		ROLE="--auto-join"
	fi
	"$GODOT" --path . --resolution 640x360 --position "$X,$Y" -- "$ROLE" "--name=${NAMES[$i]}" &
	PIDS+=($!)
	# Let the host open its room before the joiners start looking for it.
	[ "$i" -eq 0 ] && sleep 2
done

echo "Started $COUNT windows. In the host window: pick a level, wait for the others, press START."
echo "Joiners press Ready first. Close all windows (or press Ctrl+C here) to stop."
wait
