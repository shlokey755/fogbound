# Fogbound

A 2D cooperative multiplayer maze game built in Godot 4.3. Up to 16 players split into teams, spawn in a foggy room with heavily diminished vision, and stay physically tethered to their teammates ("holding hands") while exploring the maze for clue fragments. Pull your tether too tight and it snaps permanently, fracturing your team. Decode the exit sequence and escape with as many teammates still attached as you can — the more intact your team, the higher you score.

This repository is a playable **minimum viable version** of the design in [`docs/DESIGN.md`](docs/DESIGN.md): seeded maze generation, lighting-based fog of war, a spring-damper tether with a 4-state tension machine (green/yellow/red/critical), permanent snapping with corner-wrap and a snag-forgiveness buffer, pod splitting via a connected-components graph, the 2-member elimination rule, clue fragments decoded at a console, and local Wi-Fi hotspot multiplayer. Online room-code play (WebRTC) is scaffolded but not wired in — see [`docs/WALKTHROUGH.md`](docs/WALKTHROUGH.md) for why and how to finish it.

## Status

| Piece | State |
|---|---|
| Maze generation, fog, tether physics, pod graph, scoring | Implemented, unit-tested |
| Local hotspot multiplayer (ENet) | Implemented |
| Lobby (pod assignment, ready/start) | Implemented, minimal UI |
| Online room-code multiplayer (WebRTC + signalling server) | Scaffolded, **not wired up** |
| Art (sprites, tiles, audio) | Placeholder flat-color rectangles only |

All three automated test suites pass against Godot 4.3-stable (see [Testing](#testing) below).

## Requirements

- [Godot 4.3](https://godotengine.org/download) (the project targets 4.3 specifically; later 4.x versions will likely work but haven't been verified here)
- Node.js 18+ only if you want to run the (unwired) online signalling server in `server/`

## Running it

1. Open `project.godot` in the Godot editor, or run headless:
   ```
   godot --path . res://scenes/main_menu.tscn
   ```
2. One device/instance clicks **Host (hotspot)**. If you're testing on one PC, use Godot's *Debug → Run Multiple Instances* option (set it to 2–4) so each instance is a separate process with its own peer id.
3. Other instances/devices type the host's IP and click **Join**.
   - On real phones: the host turns on its Wi-Fi hotspot, the others connect to it, then join using the host's hotspot IP (shown on the host's screen once it starts hosting).
   - Local-network broadcast discovery is attempted automatically but isn't reliable on every hotspot — manual IP entry always works as a fallback.
4. In the lobby, form pods (minimum 2 players each) and the host starts the match once every pod meets the minimum.
5. Move with WASD/arrow keys (desktop) or the on-screen joystick (touch). Walk into clue tablets to read them, bring your pod's combined knowledge to the console in the fog room, then get everyone to the exit gate while it's still unlocked.

See `docs/WALKTHROUGH.md` for a full build-up explanation of every system, in the order you'd want to build or study it.

## Project layout

```
autoload/     Singletons: game state, score table, networking (local + online scaffold)
scenes/       .tscn scene files (menu, lobby, game, player, clue, pod card, score screen)
scripts/      Gameplay logic: maze generator, tether system, pod graph, fog, clues, UI
shaders/      Palette-swap shader for team colors (placeholder art pipeline)
assets/       Placeholder sprites/tiles (flat-color rectangles — see docs/WALKTHROUGH.md "Art")
server/       Node.js WebSocket signalling server for the (unwired) online mode
tests/        Headless automated tests, runnable without the editor
docs/         Design document and build walkthrough
```

## Testing

Three independent suites, runnable headlessly without opening the editor:

```bash
GODOT=/path/to/godot ./tests/run_all_tests.sh
```

This runs, in order: `PodGraph`/`ScoreTable` logic tests, `MazeGenerator` determinism/structure tests, and a full `game.tscn` boot smoketest (spawns real players, builds a real tether link, generates a real maze — using the actual autoloads, not mocks). All three currently pass against Godot 4.3-stable.

## Design document

The full design — mechanics, scoring, networking architecture (including the online mode), art pipeline, and open design questions — lives in [`docs/DESIGN.md`](docs/DESIGN.md).
