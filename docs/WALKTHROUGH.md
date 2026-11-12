# Fogbound: Build Walkthrough

This walks through the project in the order you'd want to build or study it: what each system does, why it's built the way it is, how to run and test it, and what's left before it's a finished game. It assumes you've read `docs/DESIGN.md` for the mechanics themselves — this document is about the code.

---

## 0. What's in this repo right now

The minimum viable version from the design doc (section 16) is implemented and passing its tests:

| System | File(s) | State |
|---|---|---|
| Seeded maze generation | `scripts/maze_generator.gd` | Done, unit-tested |
| Lighting-based fog of war | `scripts/fog_controller.gd`, `scripts/player.gd` | Done |
| Spring-damper tether, 4-state tension, rope wrapping, snag buffer | `scripts/tether_system.gd` | Done |
| Pod splitting (connected-components graph) | `scripts/pod_graph.gd` | Done, unit-tested |
| 2-member elimination rule | `scripts/game_controller.gd` | Done |
| Clue fragments + console unlock | `scripts/clue.gd`, `scripts/clue_spawner.gd` | Done (one clue type: symbol tablets) |
| Exit + tiered scoring | `scripts/game_controller.gd`, `autoload/score_table.gd` | Done, unit-tested |
| Local Wi-Fi hotspot multiplayer, room discovery | `autoload/net_local.gd`, `scripts/net_discovery.gd`, `autoload/net_router.gd` | Done, tested with two processes |
| Host/Join screens and the host-run lobby | `scripts/main_menu.gd`, `scripts/join_screen.gd`, `scripts/lobby.gd` | Done |
| Online room-code multiplayer | `autoload/net_online.gd`, `server/` | **Scaffolded, not wired up** — see Phase 6 |
| Level table, per-level themes, secret level | `autoload/level_data.gd`, `autoload/save_data.gd` | Done, tested |
| Seeded puzzle rooms + tunnel chain | `scripts/maze_generator.gd` | Done, unit-tested |
| Developer commentary pickups | `autoload/commentary_data.gd`, `scripts/commentary_*.gd` | Done |
| Character sprites, team palette shader, icon | `scripts/player_sprites.gd`, `shaders/`, `tools/`, `assets/` | Done (generated art) |
| Offline mode + bots | `scripts/offline_setup.gd`, `scripts/bot_*.gd` | Done, tested — see section 8b |
| Tile art, prop art, audio | — | **Not started** — see `docs/ART_WALKTHROUGH.md` |

Headless test suites cover the logic layer and a real two-process hosted game; see "Testing" below.

---

## 1. Project structure

```
autoload/     Singletons (always loaded, see project.godot [autoload]):
                game_state.gd   - match state + all tunable constants
                score_table.gd  - scoring tiers
                net_router.gd   - all game RPCs, transport-agnostic
                net_local.gd    - ENet hotspot transport + room discovery
                save_data.gd    - per-device save (unlocks, player name)
                level_data.gd   - the level table
                net_online.gd   - WebRTC transport (NOT in [autoload] yet)
scenes/       .tscn files: main_menu, join_screen, lobby, offline_setup, game, player, clue, score_screen, touch_joystick
scripts/      Gameplay logic (see table above)
shaders/      Palette-swap shader for team colors
assets/       Placeholder art (currently just flat-color rectangles built in code)
server/       Node.js WebSocket signalling server for online mode
tests/        Headless tests, runnable without the editor
docs/         DESIGN.md (the full design) and this file
```

Everything in `autoload/` is a singleton Godot creates automatically at boot, in the order listed in `project.godot`. `GameState` has no dependencies and loads first; `NetRouter` and `NetLocal` reference `GameState`.

---

## 2. Core constants and why they live in one place

`autoload/game_state.gd` holds every tunable number from the design doc — tile size, move speed, vision radii, tether spring/damping constants, pull caps, minimum team size — as named constants with the design doc section they came from in a comment. This matters for two reasons:

1. **Host/client agreement.** The tether physics only work if host and every client compute from the same constants. Keeping them as compiled constants (not something sent over the network) means there's nothing to desync.
2. **Playtesting.** Section 12 of the design doc calls for an offline sandbox with sliders for `k`, `c`, `L0`, `D_max`. Because these all live in one file as named constants, wiring up a debug panel later is a matter of exposing that one file's values, not hunting through the codebase.

If you're tuning feel, start here.

---

## 3. Maze generation (`scripts/maze_generator.gd`)

A recursive-backtracker (DFS) maze carved onto an odd-sized grid, seeded with `RandomNumberGenerator`. The build order matters:

1. Carve a central "fog room" first (an open rectangle, not a corridor maze).
2. Seed the DFS from multiple points around the fog room's perimeter, so corridors radiate outward in several directions instead of the fog room being a dead end.
3. Run the DFS over the rest of the grid.
4. Knock out a handful of extra walls to add loops (a perfect maze — no loops — is usually less fun and makes a single snapped tether catastrophic, since there'd be only one path back together).
5. Place the seeded puzzle rooms and tunnels (see below).
6. Place the exit at the floor cell closest to the outer border. Fragments go in the puzzle rooms first (in tunnel order), and any remainder on random floor tiles outside the fog room, the exit and the rooms.

### Puzzle rooms and seeded tunnels

`generate(seed, w, h, fragment_count, commentary_count, puzzle_room_count, puzzle_room_size)` takes the room count and size from the level's `with_puzzles(...)` entry in `autoload/level_data.gd`. Everything below draws from the same seeded `rng` as the rest of the maze, so a seed always gives the same layout on every client:

1. **Place rooms.** Pick odd-aligned top-left corners at random and keep a room if it stays 2 cells clear of the border, the fog room and the rooms already placed. If the maze is too crowded it simply places fewer.
2. **Order them into a chain.** Starting from the fog room, hop to the nearest remaining room, or randomly the second-nearest, so the trail isn't always the obvious one. The result is `maze.puzzle_rooms`.
3. **Carve tunnels.** For each hop, carve an L-shaped one-cell-wide tunnel between room anchors (odd-coordinate cells, so tunnels stay on the corridor lattice). A seeded coin flip chooses horizontal-first or vertical-first. The cells are recorded in `maze.tunnel_paths[i]`.
4. **Put fragments at the room centres** in chain order, so fragment *i* is both the *i*-th symbol of the exit code and the *i*-th room on the trail.

With `puzzle_room_count = 0` no RNG is consumed, so seeds that existed before this feature build exactly the maze they used to (there's a test for that). The tests also sweep 40 seeds per property: rooms are floor, off the border, off the fog room, non-overlapping, and every room, fragment and the exit are reachable from the spawn.

**Why this is `class_name MazeGenerator extends RefCounted` and not a `Node`:** it has no scene tree dependency. Every client calls `generate()` with the same seed (sent once by the host at match start) and gets an identical grid back — see `test_maze_generator.gd`'s determinism test. This is also why it's cheap to unit-test: no scene instantiation needed, just construct one and call `generate()`.

The grid itself (`maze.grid[y][x]`, 0 = floor, 1 = wall) and the special cells (`spawn_cell`, `console_cell`, `exit_cell`, `fragment_cells`) are public fields read directly by `game_controller.gd` and `tether_system.gd` (for the `AStarGrid2D` rope-wrapping lookup).

**Assumption carried over from the design doc (section 2, "Assumption A1"):** spawn and the console are both in the fog room; fragments are in the outer maze; the exit is at the perimeter. If you want the alternate layout (spawn at the perimeter, exit in the fog room), the swap is isolated to `_place_special_cells()`.

---

## 4. The tether: spring-damper physics, tension states, snapping

This is the mechanically interesting part of the game, and it's split across two files on purpose.

### `scripts/pod_graph.gd` — pure graph logic

Players are nodes, alive links are edges. `recompute_pods()` does a flood fill (BFS) to find connected components after every snap or disconnect. This file knows nothing about physics, positions, or Godot's scene tree — it's just `Dictionary`s of integer peer ids. That's deliberate: it means `test_pod_graph.gd` can construct a graph, snap a link, and assert on the resulting pods without ever touching a scene, a player node, or the physics engine.

### `scripts/tether_system.gd` — the physics, host-only

Each link runs this every physics tick (host only — clients never compute tether physics themselves, they just render the host's tension state):

1. **Effective rope length.** If there's a clear line of sight between the two players, the rope length is just the straight-line distance. If not (the rope would pass through a wall), an `AStarGrid2D` path is found and "pulled taut" — walked from one end, repeatedly jumping to the farthest waypoint still in clear sight, the way you'd pull a real rope snagged on a corner straight. This is `_rope_path()` / `_pull_taut()`.
2. **Tension** is that effective length divided by `D_max` (6 m / 96 px), producing a 0–1+ value.
3. **State machine** (green/yellow/red/critical) with hysteresis, so the color doesn't flicker right at a boundary.
4. **Spring-damper force** (`F = -k(d - L0) - c(v_rel)`, only applied while stretched past `L0`, never pushing) converts into a `pull_velocity` added to the player's own input velocity, capped by the current tension state's pull cap.
5. **Snapping.** At Critical, a timer starts. If the rope is "snagged" (wrapped around a corner — detected as `path.size() > 2`), the player gets the 1.5 s grace buffer from the design doc before the link snaps; an unsnagged link at 100% snaps immediately. This is the single biggest usability fix over a naive "distance > max → snap": without it, a tether that's taut around a corner (not actually over-stretched, just geometrically long) would snap unfairly.

Snapping is **permanent** — `PodGraph.snap_link()` removes the edge and it's never re-added. This matches design doc section 14, open question 2, which flags the tension between "permanently splits" and "scramble to reconnect" in the original notes; this build resolves it as no re-linking in v1.

The A* path lookup is the expensive part, so it's throttled to every third physics tick (`_snag_check_counter % 3`) rather than every tick — with up to 15 links active in a full 16-player chain, running `AStarGrid2D.get_point_path()` 15 times every single tick would be wasteful, and a few ticks of staleness on a path recalculation is imperceptible.

**Where the host/client split actually happens:** `game_controller.gd`'s `_physics_process` only calls into `tether_system` if `GameState.is_host() or not multiplayer.has_multiplayer_peer()` (the second clause lets you run `game.tscn` directly in the editor, offline, for fast iteration without spinning up networking at all). Clients receive tension state and snap events over RPC (`net_router.gd`) and just draw the line and play the effects — they never compute a pull.

---

## 5. Fog and vision (`scripts/fog_controller.gd`, `scripts/player.gd`)

Rather than a flat screen-space shader, this uses Godot's actual 2D lighting: each player has a `PointLight2D`, walls carry `OccluderPolygon2D` data (built automatically by `MazeTileSetBuilder`, see below), and `CanvasModulate` darkens everything outside lit areas. This gives wall-blocked vision — you can't see around a corner — essentially for free, instead of hand-rolling raycasting.

`FogController` owns an `Area2D` sized to match the generated maze's fog room rect (set up once by `game_controller._build_maze()`, since the fog room's exact size depends on the maze dimensions). Entering/exiting that area flips each `Player.in_fog` flag, and `Player._update_light_radius()` tweens the light's `texture_scale` toward `VISION_FOG` or `VISION_NORMAL` (plus the lantern bonus, if carrying one) using a simple `lerp` each tick rather than a `Tween` node, which is cheap enough to run unconditionally and avoids managing tween lifetimes for up to 16 players.

---

## 6. Networking

### Why there are two transport files and a router

`autoload/net_local.gd` wraps `ENetMultiplayerPeer` (LAN/hotspot). `autoload/net_online.gd` is a parallel implementation using `WebRTCMultiplayerPeer` plus a signalling server (not currently loaded as an autoload — see Phase 6). Both ultimately just set `multiplayer.multiplayer_peer` to a different peer object; everything above that line — all gameplay RPCs — is identical regardless of which transport is active, because they all go through Godot's `multiplayer` API rather than talking to either transport directly.

`autoload/net_router.gd` is where every game-level RPC lives: lobby state, start-match, per-tick input, snapshots, link-snap events, fragment reads, match-finished. Centralizing these (instead of scattering `@rpc` functions across player/game scripts) makes the authority rules easy to audit in one place — every RPC that mutates shared state checks `GameState.is_host()` and uses `multiplayer.get_remote_sender_id()` rather than trusting a peer id passed in the payload, which matters because a malicious or buggy client could otherwise claim to be any peer.

### Authority split

The host (`GameState.is_host()`) runs maze generation output validation, tether physics, the pod graph, clue notebooks, console/exit checks, and scoring. Clients send input (`net_input`, unreliable — stale packets are just dropped, the next one supersedes it) and receive position snapshots (`net_snapshot`, unreliable, ~20 Hz) plus reliable events for anything that must not be dropped: link snaps, fragment reads, match-finished.

### The hosted flow, end to end

1. **Wi-Fi first, outside the game.** Every phone joins the hotspot in its own settings.
2. **Host game** (`NetLocal.host_game()`): opens an ENet server on UDP 7777, binds UDP 7778 to answer room-finding probes, and opens the lobby with the host in Pod A.
3. **Join game** (`scripts/join_screen.gd`): `NetLocal.start_scan()` sends probes every 1.5 s; each reply becomes a row in the room list. Tapping a row calls `NetLocal.join_game(ip, port)`.
4. The lobby (section 7) runs on the host. START sends `net_start_match` to everyone, and every device loads `game.tscn`.
5. In the game, the host simulates everything. A joiner only sends its direction (`net_input`) and draws what the host's 20 Hz snapshots say.

### How a joiner finds the host (`scripts/net_discovery.gd`)

The first version had the host *announce* itself by broadcast, and joiners listen. That is the first thing phone hotspots and routers drop, and a joiner would just see an empty list. So it is reversed: the **joiner asks, the host answers**.

- The joiner sends a short probe (`FOGBOUND?|1`) by unicast to: this machine, the limited broadcast, each local subnet's broadcast, and *every address in its own /24* (a hotspot network is tiny: about 250 packets of 12 bytes, once every 1.5 s).
- The host answers each probe directly with one line: `FOGBOUND|1|host_id|room|players|max|level|port|started`.
- Rooms are keyed by a random `host_id`, so one room answering from two addresses is listed once, and a room that stops answering leaves the list after 5 s.
- Several joiners on one machine do not fight over a listening port, because only the host binds one.

`NetDiscovery` is pure functions (no sockets), so `tests/test_net_discovery.gd` checks the wire format and address maths without a network. The manual address box on the join screen remains as a fallback for networks that block even unicast probing.

### What clients draw

Clients spawn every player (so they can draw them) but never move a body themselves. A snapshot is: for each player `id, x, y, eliminated`, then for each rope `a, b, state, tension` (`state` 255 means snapped). `Player.set_net_target()` glides each body to its latest position; clients draw ropes as straight lines coloured by the state the host sent (the host's own lines also bend around corners, which is not sent). The HUD line ("Pod 2 | Tablets 1/8 | ...") is built from the same data. When a pod opens the exit, only that pod's members are told (`net_pod_unlocked`), so a rival pod's progress stays private.

### Running it on one machine

`tools/run_instances.sh 2` (or `.bat` on Windows) opens several windows: window 1 runs `--auto-host`, the rest `--auto-join`, each with a `--name=`. Those are game arguments after `--` (see `scripts/main_menu.gd`); `--game-port=` and `--discovery-port=` move the ports (the automated test uses them so it never collides with a game you have open).

For real hardware: see `docs/PROCESS.md`, "Testing on real phones".

---

## 7. The lobby (`scripts/lobby.gd`, `autoload/net_router.gd`)

The lobby UI is built in code (`Lobby._build_ui`) so the same script serves the host and clients: the host gets a level dropdown, a seed box and START; clients get a read-only level line and a Ready toggle. Both get the room banner, the pod list with Join buttons, **New pod**, **Leave** and a status line.

All lobby state lives on the host (`GameState.teams`, `player_names`, `player_ready`, `level_id`, `room_title`). A client only ever sends a *request* (`request_join_pod`, `request_set_ready`, `request_set_name`, ...); the host validates it using `multiplayer.get_remote_sender_id()` and then re-broadcasts the **whole** lobby (`net_lobby_state`, a few hundred bytes). Sending everything every time means a device that joins late, or misses a packet, is fixed by the next update. Everyone defaults into Pod A, so the common case is: join, ready, host presses START.

A subtlety that cost a bug: an RPC addressed to your own id never runs. So the host's own button presses do not RPC to itself; `NetRouter.join_pod()` and friends apply them directly when `GameState.is_host()`.

`NetRouter.host_check_can_start()` encodes the design doc's section 6.3 start conditions (everyone in a pod, every pod at least 2, every client ready) and returns the reason shown under the pod list while START is blocked.

---

## 8. Scoring (`autoload/score_table.gd`)

Ratio-based and data-driven (a `TIERS` array of `{min_ratio, points}`), so it isn't hardcoded to power-of-two team sizes. Worth reading the comment block in this file specifically — it resolves an edge case the design doc flagged but didn't fully nail down (open question 4 / section 14.4): a plain ratio computation would score 2-of-3 survivors as a "half team" (500 points) under the same formula that gives a 2-of-16 pod only 50 points, even though the 3-player team never had much to lose in the first place. The fix special-cases "pod is at the absolute minimum AND came from a team that was already close to the minimum" as the bare-minimum tier, while larger teams still fall through the ratio ladder normally.

---

## 8b. Offline mode and bots

### Offline is the host path

With no multiplayer peer set, Godot gives the process an `OfflineMultiplayerPeer`: `has_multiplayer_peer()` is true, the unique id is 1 and `is_server()` is true. `call_local` RPCs run, `call_remote` ones do not. So the host-authoritative match (tether system, pods, scoring) runs **unchanged**; offline mode only adds a few fields to `GameState`:

| Field | Meaning |
|---|---|
| `offline_mode` | True for a match started from the offline setup screen |
| `human_id` | Always 1: the player driven by input |
| `bots` | `peer_id -> {"skill": int}`; bots take ids 2 and up |
| `is_bot(id)`, `human_team_id()` | Helpers; `human_team_id()` is -1 when not offline |

`OfflineSetup.configure_match(level, mates, rivals, rival_size, skill, seed, autoplay=false)` fills those in, builds the teams (team 0 is "Your pod", rivals are "Rivals A/B/C"), and calls the same `NetRouter.net_start_match` a hosted match uses. `autoplay = true` makes your slot a bot too, so a whole match plays itself; the tests use it to run complete matches headlessly.

### Bot AI (`scripts/bot_*.gd`)

| File | Job |
|---|---|
| `bot_nav.gd` | Cell/pixel conversion and a grid line-of-sight test |
| `bot_knowledge.gd` | One per team: the set of tiles the team has seen, plus A* over only those tiles. This is what makes bots fog-fair: they cannot path through a corridor nobody has looked at |
| `bot_mission.gd` | Picks a pod leader's goal. Priority: exit (once unlocked) > console (once every fragment is read) > nearest unread fragment > nearest unexplored frontier > wait. Goals are sticky so the leader does not dither between two equal choices |
| `bot_brain.gd` | Steering for one bot: walks cell centre to cell centre, squares up at corners, repaths every 0.5 s, detects being stuck. Leaders slow down as pod rope tension rises; followers run to close the gap, then hold still a short distance away |
| `bot_controller.gd` | Per tick, per pod: picks the leader (you, if you are in the pod, else the first living member), points followers at their chain neighbour, and once the exit is open and the leader is near it, sends the whole pod onto the gate together |

Skill table (`BotBrain.SKILLS`):

| Skill | Top speed (x move speed) | Sight (tiles) | Starts easing off at rope tension |
|---|---|---|---|
| Easy | 0.70 | 2 | 62% |
| Normal | 0.85 | 3 | 50% |
| Hard | 1.00 | 4 | 42% |

Easy is slow and short-sighted; Hard is fast and looks far, but starts easing off the rope earliest. In the tests a Hard pod finishes faster than an Easy one, and the longest rope any bot pod reached was 40 px of the 96 px maximum, so none came near a snap.

### Offline-only choices

- **Players pass through each other.** Collision exceptions are added between all players in offline matches only, so bots can never deadlock each other or you in a one-tile corridor. Hosted matches are unchanged.
- **Rival pods are hidden.** Their lights are off and their ropes are not drawn for you.
- **Match end.** Offline, the match ends when your pod escapes or is eliminated (a rival pod being eliminated does not end it).

### MVP gaps this work had to fix

Playing alone exposed things the hotspot MVP never needed:

| Gap | Fix |
|---|---|
| No camera: the world sat at a fixed offset | A smoothed `Camera2D` follows the local player |
| Keyboard input never stopped on key release | Keys send one zero vector on release |
| On-screen joystick did nothing for the host | `NetRouter.send_input` applies directly when you are the host |
| The host never saw its own fragment reveals | `net_fragment_revealed` is now `call_local` |
| Match never ended when a pod was eliminated | `_eliminate_small_pods` re-checks the end condition |
| Console/exit only reacted on entry | Overlapping bodies are re-checked every 0.25 s |
| Menus overflowed the 320x180 viewport | `CompactTheme` shrinks the font |
| Out-of-maze space rendered grey | Default clear colour is near-black |

And making hosted play testable exposed more (found by the two-process test and the lobby tests):

| Gap | Fix |
|---|---|
| Joining devices never spawned any `Player` nodes (an empty screen) | Every device spawns every player; clients only follow snapshots (`Player.set_net_target`) |
| Clients never saw ropes or knew when their exit opened | Snapshots carry each rope's state; `net_pod_unlocked` tells a pod's own members |
| The host's own lobby clicks did nothing (an RPC to yourself never runs) | The host applies its own requests directly |
| A player could end up listed in two pods | One `_host_move_to_pod` removes you from every other pod first |
| A late joiner saw a stale lobby | The host re-broadcasts the whole lobby after every change |
| The host could select a level id that does not exist (`get_level` silently falls back to level 0) | `host_set_level` checks the id itself |
| A test window's `--name=` overwrote your saved player name | `--name=` lasts for that run only |

### Known limitations

- Bots are not added to hosted/online matches. If you do, ids 2.. would collide with real peer ids.
- Rival bots never interact with you (no blocking, no stealing fragments).
- The secret level can be unlocked from an offline win.

---

## 9. Placeholder art (`scripts/maze_tileset_builder.gd`)

Rather than requiring you to open the editor and hand-author a `TileSet` resource before the project will even run, `MazeTileSetBuilder.build()` constructs one entirely in code: three tiles (floor, wall, puzzle-room floor) as flat-color `ImageTexture`s, with the wall tile carrying both a collision polygon and an occlusion polygon (so the lighting system in section 5 above works immediately). `game_controller._paint_tilemap()` calls this only if `Maze.tile_set` is still unset in the scene, so swapping in real art later is a one-line change: assign a real `TileSet` to the `Maze` node in `game.tscn` via the editor, and delete the `if maze_layer.tile_set == null` fallback.

Character sprites and the icon are no longer placeholders: they are generated pixel art (`tools/make_sprites.py`, `tools/make_icon.py`) wired up through `PlayerSprites` and the team palette shader. **For how to replace any of this art with your own, see `docs/ART_WALKTHROUGH.md`.**

### Building the rest of the art

Follow design doc section 8 (sizes, the per-team palette-swap shader already stubbed in `shaders/`, the asset checklist). Suggested order:

1. ~~Player sprite sheet~~ — done (4 characters, 8 animations, magenta marker scarf recoloured per team).
2. Floor/wall tiles at 16×16, built as a proper `TileSet` in the editor (with auto-tiling/terrain sets for walls so corners join correctly) — this replaces `MazeTileSetBuilder`.
3. Clue, console, and exit gate sprites.
4. UI icons (joystick, ping, tension ring, warning).

---

## 10. Testing

Everything is headless and none of it needs the editor:

```bash
GODOT=/path/to/godot ./tests/run_all_tests.sh
```

| Suite | What it covers | How it runs |
|---|---|---|
| `tests/test_pod_graph.gd` | Chain/split/remove graph logic, score tiers | `godot --headless --script ...` (pure logic, no scene) |
| `tests/test_maze_generator.gd` | Determinism for a given seed, structural sanity (special cells are floor, border is solid, fragments don't overlap the fog room or exit), commentary placement, and the seeded puzzle rooms / tunnel chain (45 checks across many seeds) | Same, pure logic |
| `tests/test_net_discovery.gd` | The room-finding message format (round trip, garbage rejected, names cannot break it) and the address maths (private ranges, the /24 scan list) | Same, pure logic |
| `tests/test_bots.gd` | Bot navigation and line of sight, fog-fair knowledge, mission priorities and stickiness, steering hysteresis, solo bots finishing every level, two-bot rope sims (longest rope per skill), the skill table | `--script`, pure logic over a generated maze |
| `tests/boot_smoketest.tscn` + `tests/boot_game_smoketest.gd` | Real scenes with real autoloads: every level in `LevelData`, the character sprite pipeline, the secret-level unlock, offline mode (config, the 16-player cap, wiring, two complete autoplay matches, elimination), the Host/Join/Offline menu, the host's lobby rules, the snapshot wire format, the HUD line, the score screen | `godot --headless --fixed-fps 60 --path . res://tests/boot_smoketest.tscn` (a real scene boot, *not* `--script`, because `--script` mode does not run project autoloads. `--fixed-fps 60` runs physics as fast as the CPU allows) |
| `tests/net_e2e.sh` | **Two real processes** over this machine's loopback, driving the real menu, join screen, lobby and game: discovery finds the room, the joiner connects, names/pods/level sync, Ready gates START, the joiner spawns with a camera, its key press moves its player on the host and on its own screen, and the rope is drawn on the joiner | Real time (about 15 s) on ports 27777/27778 |

A parse error in the smoketest script leaves its scene idling instead of failing, so `run_all_tests.sh` wraps it in a timeout and requires `ALL TESTS PASSED` in the output. If you add a new system, prefer extending the pure-logic suites (fast, no scene tree) and reserve the boot smoketest for things that only break when real nodes and autoloads are involved (like the `TileSet`-must-be-attached-before-touching-TileData ordering bug noted in `maze_tileset_builder.gd`). Use the e2e test for anything that only shows up with two processes.

What is not covered: real phones and real hotspots. Discovery uses plain UDP; a hotspot that isolates devices from each other will stop it (and the game) no matter what the code does. Test on one before shipping.

---

## 11. Phase 6: wiring up online room-code play

`autoload/net_online.gd` is a complete reference implementation of the design doc's section 4.3 (WebSocket signalling + WebRTC P2P + STUN/TURN), and `server/server.js` is a working ~60-line Node signalling server. Neither is wired into the running game yet. To finish this phase:

1. **Add the `webrtc-native` GDExtension** for whichever platforms you're exporting to (Android, desktop — the Web export has WebRTC built in already). Check the extension's release page against your exact Godot version before committing to this; this is the single riskiest unknown in the whole project, which is why it's deliberately last.
2. **Add `NetOnline` to `[autoload]` in `project.godot`.**
3. **Point `SIGNAL_URL` in `net_online.gd`** at a deployed instance of `server/server.js` (any small Node host works for development; verify current free-tier terms before relying on one).
4. **Add a "Create Online Room" / "Join by code" path** in `main_menu.gd` alongside the existing hotspot buttons, calling `NetOnline.host_room()` / `NetOnline.join_room(code)` instead of `NetLocal.host_game()` / `join_game()`.
5. **Nothing downstream needs to change.** `net_router.gd`, `game_controller.gd`, `tether_system.gd` — all of it talks to `multiplayer.multiplayer_peer` generically and has no idea whether that peer is ENet or WebRTC. This is the payoff of the transport split described in section 6 above.

Explicitly out of scope even after this phase (see design doc section 4.9 and open question 7): TURN credential fetching from a trusted endpoint (hardcoding long-lived TURN credentials client-side isn't safe for a public release — you'd want a short-lived credential endpoint), reconnect-on-drop, host migration, and mixed local+online rooms in a single match (one transport per match, by design).

---

## 12. Suggested order if you're picking this up fresh

1. Run the test suite (section 10) to confirm your Godot install works with the project.
2. Open `game.tscn` directly in the editor and run it standalone (no networking) to see the maze/fog/tether loop with one player.
3. Run `tools/run_instances.sh 2` to get 2+ players tethered together locally and deliberately snap a link.
4. Read `docs/DESIGN.md` sections 3 and 5 side-by-side with `tether_system.gd` — the code comments point back to specific design doc sections throughout.
5. Move on to real art (section 9 above) once the loop feels right — don't polish placeholder-art gameplay you might still rebalance.
6. Save online play (section 11) for last, after local play is confirmed fun. It's the highest-risk, most isolated piece.
