# Fogbound

A 2D cooperative multiplayer maze game built in Godot 4.3. Up to 16 players split into teams, spawn in a foggy room with heavily diminished vision, and stay physically tethered to their teammates ("holding hands") while exploring the maze for clue fragments. Pull your tether too tight and it snaps permanently, fracturing your team. Decode the exit sequence and escape with as many teammates still attached as you can — the more intact your team, the higher you score.

This repository is a playable **minimum viable version** of the design in [`docs/DESIGN.md`](docs/DESIGN.md): seeded maze generation, lighting-based fog of war, a spring-damper tether with a 4-state tension machine (green/yellow/red/critical), permanent snapping with corner-wrap and a snag-forgiveness buffer, pod splitting via a connected-components graph, the 2-member elimination rule, clue fragments decoded at a console, and local Wi-Fi hotspot multiplayer with an automatic room list. Online room-code play (WebRTC) is scaffolded but not wired in — see [`docs/WALKTHROUGH.md`](docs/WALKTHROUGH.md) for why and how to finish it.

## Status

| Piece | State |
|---|---|
| Maze generation, fog, tether physics, pod graph, scoring | Implemented, unit-tested |
| Local hotspot multiplayer (ENet): Host game, room list, host-run lobby with level choice | Implemented, tested with two real processes (not yet on real phones) |
| Offline mode: you + bot teammates, optional rival bot pods, 3 skill levels | Implemented, tested (full simulated matches) |
| Lobby (names, pods, ready, host picks level and seed) | Implemented, tested |
| Online room-code multiplayer (WebRTC + signalling server) | Scaffolded, **not wired up** |
| Levels (6 difficulty classes + a secret level), per-level themes | Implemented, tested |
| Seeded puzzle rooms joined by tunnels | Implemented, tested |
| Developer commentary pickups | Implemented |
| Character sprites (4 looks, team-colour shader), game icon | Generated pixel art, implemented |
| Tile art, prop art, audio | Placeholder flat-color rectangles / none — see [`docs/ART_WALKTHROUGH.md`](docs/ART_WALKTHROUGH.md) |

All automated test suites pass against Godot 4.3-stable (see [Testing](#testing) below).

New to game development? Start with [`docs/PROCESS.md`](docs/PROCESS.md): a mentor-style, step-by-step guide to running the project and changing its art, rules and levels.

## Play offline (bots)

No network, no friends needed: **Play offline (bots)** on the main menu opens a setup screen.

| Setting | Range | Default | Meaning |
|---|---|---|---|
| Level | any unlocked level | The Understreets | Same level table as hosted play |
| Bot mates | 1-7 | 2 | Bots chained to you in your pod |
| Rivals | 0-3 | 1 | Rival bot pods racing you to the same exit |
| Rival size | 2-5 | 3 | Players per rival pod |
| Skill | Easy / Normal / Hard | Normal | Bot speed, how far they look, how early they ease off the rope |
| Seed | number or blank | random | Same seed + level = same maze |

The total is capped at 16 players, like a hosted match. Controls are the same as hosted play (WASD/arrows or the on-screen joystick); **Menu** (top-right) or Esc leaves the match.

- **You are the pod leader.** Your bot teammates follow you along the chain and stop a short distance behind, so the rope stays slack unless you sprint. Run too far, too fast and the rope still snaps, exactly as in a hosted match.
- **Bots play fair.** They only know the tiles their team has actually seen (same fog rules as you), read the same fragments, decode at the same console, and must all stand on the exit together to score. A bot-led pod collects fragments, uses the console, then walks to the exit, slowing before its own rope gets tight.
- **Rivals are a race, not a fight.** Rival pods can lose members to snaps and be eliminated like any pod. Their lights and ropes are hidden from you (their pods are only visible when they are inside your lit area).
- **The match ends** when your pod escapes or is eliminated; the score screen shows every pod, with yours marked "(you)".

Under the hood offline mode is not a separate game: with no network peer Godot's default `OfflineMultiplayerPeer` makes your process its own host (peer id 1), so the normal host-authoritative match runs unchanged and bots take peer ids 2 and up. See `docs/WALKTHROUGH.md` section 8b.

## Levels, secrets and commentary

- **Levels:** the lobby has a level picker (The Antechamber → The Labyrinth Proper). Each level sets maze size, fragment count, a colour theme, and how many puzzle rooms it has. The maze itself is freshly generated from the match seed every game. See `autoload/level_data.gd`.
- **Puzzle rooms and tunnels:** every level places a few small rooms at seeded positions and joins them to the fog room with a chain of tunnels. The first fragments sit in those rooms, in tunnel order, so the trail is also the order the exit code is read in. All of it derives from the match seed, so every player builds the same layout without any extra networking.
- **Secret level:** escape *The Labyrinth Proper* with your whole team still holding hands (a 1200-point finish) to unlock `???`. The unlock is saved per device (`autoload/save_data.gd`).
- **Developer commentary:** a few glowing pickups are hidden in maze dead ends each match. Walking into one shows a short original note about how the game was designed. They are local and cosmetic, and never affect scoring. Notes are in `autoload/commentary_data.gd`.

## Requirements

- [Godot 4.3](https://godotengine.org/download) (the project targets 4.3 specifically; later 4.x versions will likely work but haven't been verified here)
- Node.js 18+ only if you want to run the (unwired) online signalling server in `server/`

## Running it

1. Open `project.godot` in the Godot editor and press **F5**, or run from a terminal:
   ```
   godot --path . 
   ```
   The window opens at 1280x720 (the game draws at 320x180 and scales up), so it fits a laptop screen.
2. The main menu has three buttons:
   - **Play offline (bots)**: alone, nothing to set up.
   - **Host game**: you are the host. Others join you.
   - **Join game**: lists the rooms found on your Wi-Fi/hotspot. Tap one to join.
3. Move with WASD/arrow keys (desktop) or the on-screen joystick (touch). Walk into clue tablets to read them, bring your pod's combined knowledge to the console in the fog room, then get everyone to the exit gate while it's still unlocked.

### Hosting over a phone hotspot

1. Turn on the hotspot on one phone (the host) and connect the other phones to it **in the phones' own Wi-Fi settings**. The game does not do this part.
2. Host phone: open Fogbound and tap **Host game**. You land in the lobby; the banner shows your room name and the address other devices could type.
3. Other phones: tap **Join game**. The host's room appears in the list within a couple of seconds; tap it.
4. In the lobby the **host picks the level and (optionally) a seed**. Everyone sees the choice live. Everyone starts in Pod A; tap **New pod** or another pod's **Join** to split into teams (every pod needs 2+ players).
5. Joiners tap **Ready**. When the status line says "Everyone is ready", the host taps **START**.

If the room list stays empty (some hotspots block device-to-device discovery), type the host's address into the box on the join screen. The host's lobby banner shows it. A phone that joins after the match has started is turned away, and a host that leaves ends the game for everyone.

### Testing hosted play on one laptop

You do not need phones to try the hosted flow. This opens 2 to 4 windows on your computer: window 1 hosts, the others find it and join.

```bash
GODOT=/path/to/godot tools/run_instances.sh 2      # Windows: tools\run_instances.bat
```

In the host window pick a level; in the other window tap **Ready**; then press **START** in the host window. Click inside a window to give it the keyboard (WASD/arrows). Each window shows its own player's view.

Only one hosting game fits on a machine at a time (it uses UDP ports 7777 and 7778). Joining windows can be as many as you like.

### Why "Play offline" might be missing

The offline mode was built on a feature branch that was merged into another branch first, so it did not reach `main` right away. If your menu has no **Play offline (bots)** button, you are running a copy from before pull request #3 was merged: pull the latest `main` and it will be there.

## Project layout

```
autoload/     Singletons: game state, score table, networking (local + online scaffold)
scenes/       .tscn scene files (menu, join screen, lobby, game, player, clue, score screen, ...)
scripts/      Gameplay logic: maze generator, tether system, pod graph, fog, clues, UI, bot AI (bot_*.gd), offline setup, LAN lobby and room discovery (net_discovery.gd)
shaders/      Palette-swap shader for team colors
assets/       Character sprite sheets and game icon (generated); tiles/props are still placeholders
tools/        Python generators for the sprites and icon, and run_instances.sh/.bat to open several game windows for testing
server/       Node.js WebSocket signalling server for the (unwired) online mode
tests/        Headless automated tests, runnable without the editor
docs/         Design document, build walkthrough, and art implementation walkthrough
```

## Testing

Everything runs headlessly, without opening the editor:

```bash
GODOT=/path/to/godot ./tests/run_all_tests.sh
```

This runs, in order: `PodGraph`/`ScoreTable` logic tests, `MazeGenerator` determinism/structure tests, `NetDiscovery` tests (the room-finding message format and address maths), bot AI tests (navigation, fog-fair knowledge, mission priorities, steering, and simulated matches), a full `game.tscn` boot smoketest (real players, a real tether, a real maze, complete offline bot matches, the menu, lobby rules, snapshot format, HUD and score screen), and finally a **two-process hosted game** (`tests/net_e2e.sh`): one Godot process hosts, a second finds the room by discovery, joins, readies up, and walks around in the host's match. All use the actual autoloads, not mocks, and take about a minute in total.

Not covered by any test: real phones and real hotspots. Different hotspots filter traffic differently, so try one before relying on it (see `docs/PROCESS.md`, "Testing on real phones").

## Replacing the art

`docs/ART_WALKTHROUGH.md` explains how to swap in your own sprites, tiles, props and icon, step by step, with a "see it change" check for each one. Short version: repaint the character sheets (96×128, keep the magenta scarf markers) over the files in `assets/sprites/characters/`, then run `godot --headless --path . --import`.

## Design document

The full design — mechanics, scoring, networking architecture (including the online mode), art pipeline, and open design questions — lives in [`docs/DESIGN.md`](docs/DESIGN.md).
