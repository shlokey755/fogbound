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
| Levels (6 difficulty classes + a secret level), per-level themes | Implemented, tested |
| Seeded puzzle rooms joined by tunnels | Implemented, tested |
| Developer commentary pickups | Implemented |
| Character sprites (4 looks, team-colour shader), game icon | Generated pixel art, implemented |
| Tile art, prop art, audio | Placeholder flat-color rectangles / none — see [`docs/ART_WALKTHROUGH.md`](docs/ART_WALKTHROUGH.md) |

All three automated test suites pass against Godot 4.3-stable (see [Testing](#testing) below).

## Levels, secrets and commentary

- **Levels:** the lobby has a level picker (The Antechamber → The Labyrinth Proper). Each level sets maze size, fragment count, a colour theme, and how many puzzle rooms it has. The maze itself is freshly generated from the match seed every game. See `autoload/level_data.gd`.
- **Puzzle rooms and tunnels:** every level places a few small rooms at seeded positions and joins them to the fog room with a chain of tunnels. The first fragments sit in those rooms, in tunnel order, so the trail is also the order the exit code is read in. All of it derives from the match seed, so every player builds the same layout without any extra networking.
- **Secret level:** escape *The Labyrinth Proper* with your whole team still holding hands (a 1200-point finish) to unlock `???`. The unlock is saved per device (`autoload/save_data.gd`).
- **Developer commentary:** a few glowing pickups are hidden in maze dead ends each match. Walking into one shows a short original note about how the game was designed. They are local and cosmetic, and never affect scoring. Notes are in `autoload/commentary_data.gd`.

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
shaders/      Palette-swap shader for team colors
assets/       Character sprite sheets and game icon (generated); tiles/props are still placeholders
tools/        Python generators for the sprites and icon (tools/make_sprites.py, tools/make_icon.py)
server/       Node.js WebSocket signalling server for the (unwired) online mode
tests/        Headless automated tests, runnable without the editor
docs/         Design document, build walkthrough, and art implementation walkthrough
```

## Testing

Three independent suites, runnable headlessly without opening the editor:

```bash
GODOT=/path/to/godot ./tests/run_all_tests.sh
```

This runs, in order: `PodGraph`/`ScoreTable` logic tests, `MazeGenerator` determinism/structure tests, and a full `game.tscn` boot smoketest (spawns real players, builds a real tether link, generates a real maze — using the actual autoloads, not mocks). All three currently pass against Godot 4.3-stable.

## Replacing the art

`docs/ART_WALKTHROUGH.md` explains how to swap in your own sprites, tiles, props and icon, step by step, with a "see it change" check for each one. Short version: repaint the character sheets (96×128, keep the magenta scarf markers) over the files in `assets/sprites/characters/`, then run `godot --headless --path . --import`.

## Design document

The full design — mechanics, scoring, networking architecture (including the online mode), art pipeline, and open design questions — lives in [`docs/DESIGN.md`](docs/DESIGN.md).
