#!/usr/bin/env bash
# Two real Godot processes play a hosted game over this machine's loopback:
# one hosts, one finds the room and joins. It covers what no single-process
# test can: discovery, ENet connect, lobby sync, match start, snapshots.
# Runs in real time (about 15 s). Needs no second device.
#
# Usage: GODOT=/path/to/godot ./tests/net_e2e.sh
set -uo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

# Odd ports so this never clashes with a Fogbound you have open (7777/7778).
PORTS=(--game-port=27777 --discovery-port=27778)
HOST_LOG="$(mktemp)"
CLIENT_LOG="$(mktemp)"
trap 'kill $HOST_PID 2>/dev/null; rm -f "$HOST_LOG" "$CLIENT_LOG"' EXIT

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

timeout 120 "$GODOT" --headless --path . res://tests/net_e2e.tscn -- \
	--role=host --auto-host --name=Hosty "${PORTS[@]}" >"$HOST_LOG" 2>&1 &
HOST_PID=$!
sleep 3   # let the host open its room before the client starts looking

timeout 120 "$GODOT" --headless --path . res://tests/net_e2e.tscn -- \
	--role=client --auto-join --name=Clienty "${PORTS[@]}" >"$CLIENT_LOG" 2>&1
CLIENT_STATUS=$?
wait "$HOST_PID"
HOST_STATUS=$?

echo "---- host ----";   grep -E "^(PASS|FAIL|E2E|SCRIPT ERROR|ERROR)" "$HOST_LOG"
echo "---- client ----"; grep -E "^(PASS|FAIL|E2E|SCRIPT ERROR|ERROR)" "$CLIENT_LOG"

if [ "$HOST_STATUS" -ne 0 ] || [ "$CLIENT_STATUS" -ne 0 ] \
		|| ! grep -q "^E2E host OK" "$HOST_LOG" || ! grep -q "^E2E client OK" "$CLIENT_LOG"; then
	echo "net e2e FAILED (host exit $HOST_STATUS, client exit $CLIENT_STATUS). Full logs follow." >&2
	cat "$HOST_LOG" "$CLIENT_LOG" >&2
	exit 1
fi
echo "net e2e passed."
