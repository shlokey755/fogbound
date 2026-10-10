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
| Local Wi-Fi hotspot multiplayer | `autoload/net_local.gd`, `autoload/net_router.gd` | Done |
| Lobby (pod assignment, ready/start) | `scripts/lobby.gd`, `scripts/pod_card.gd` | Done, minimal UI |
| Online room-code multiplayer | `autoload/net_online.gd`, `server/` | **Scaffolded, not wired up** — see Phase 6 |
| Real art, audio, polish | — | **Not started** — placeholder flat colors only |

Three headless test suites cover the logic layer; see "Testing" below.

---

## 1. Project structure

```
autoload/     Singletons (always loaded, see project.godot [autoload]):
                game_state.gd   - match state + all tunable constants
                score_table.gd  - scoring tiers
                net_router.gd   - all game RPCs, transport-agnostic
                net_local.gd    - ENet hotspot transport
                net_online.gd   - WebRTC transport (NOT in [autoload] yet)
scenes/       .tscn files: main_menu, lobby, game, player, clue, pod_card, score_screen, touch_joystick
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
5. Place the exit at the floor cell closest to the outer border, and scatter fragment cells on any remaining floor tile outside both the fog room and the exit.

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

### Running it locally without real hotspot hardware

Use Godot's **Debug → Run Multiple Instances** (set to 2–4) so each instance is a genuinely separate process with its own peer id, all connecting over `localhost`. This is how `tests/boot_smoketest.tscn` effectively tests a single-process version of the same path (it instantiates `game.tscn` directly with `GameState` pre-populated, without going through real networking at all — see "Testing" below).

For real hardware testing: the host turns on its phone's Wi-Fi hotspot, other devices join that Wi-Fi, then enter the host's hotspot IP in the Join field. LAN broadcast discovery is attempted (`net_local.gd`'s `start_advertising`/`start_listening`) but isn't reliable on every hotspot — some block client-to-client broadcast entirely — so manual IP entry is the dependable path and is always available in the UI.

---

## 7. The lobby (`scripts/lobby.gd`, `scripts/pod_card.gd`)

Clients request to join a pod (`NetRouter.request_join_pod`, routed to the host via `rpc_id(1, ...)`); the host validates and rebroadcasts the full lobby state to everyone (`net_lobby_state`, reliable, `call_local` so the host's own UI updates too). This "client proposes, host decides, host broadcasts truth" pattern is the same shape as the rest of the networking and is worth keeping consistent — it means there's never a case where two clients have different ideas about who's in which pod.

`NetRouter.host_check_can_start()` encodes the design doc's section 6.3 start conditions (every pod ≥ 2 members, at least one pod exists) and is called both to enable/disable the host's Start button and to produce the human-readable reason shown in the status label when it's disabled.

---

## 8. Scoring (`autoload/score_table.gd`)

Ratio-based and data-driven (a `TIERS` array of `{min_ratio, points}`), so it isn't hardcoded to power-of-two team sizes. Worth reading the comment block in this file specifically — it resolves an edge case the design doc flagged but didn't fully nail down (open question 4 / section 14.4): a plain ratio computation would score 2-of-3 survivors as a "half team" (500 points) under the same formula that gives a 2-of-16 pod only 50 points, even though the 3-player team never had much to lose in the first place. The fix special-cases "pod is at the absolute minimum AND came from a team that was already close to the minimum" as the bare-minimum tier, while larger teams still fall through the ratio ladder normally.

---

## 9. Placeholder art (`scripts/maze_tileset_builder.gd`)

Rather than requiring you to open the editor and hand-author a `TileSet` resource before the project will even run, `MazeTileSetBuilder.build()` constructs one entirely in code: two tiles (floor, wall) as flat-color `ImageTexture`s, with the wall tile carrying both a collision polygon and an occlusion polygon (so the lighting system in section 5 above works immediately). `game_controller._paint_tilemap()` calls this only if `Maze.tile_set` is still unset in the scene, so swapping in real art later is a one-line change: assign a real `TileSet` to the `Maze` node in `game.tscn` via the editor, and delete the `if maze_layer.tile_set == null` fallback.

### Building real sprites (when you get there)

Follow design doc section 8 (sizes, the per-team palette-swap shader already stubbed in `shaders/`, the asset checklist). Suggested order:

1. Player sprite sheet (idle/walk/pulled/eliminated) at 16×16, drawn with a marker color (pure magenta) for the parts that should recolor per team — the shader in `shaders/` already does the swap, it just needs a real texture to operate on.
2. Floor/wall tiles at 16×16, built as a proper `TileSet` in the editor (with auto-tiling/terrain sets for walls so corners join correctly) — this replaces `MazeTileSetBuilder`.
3. Clue, console, and exit gate sprites.
4. UI icons (joystick, ping, tension ring, warning).

---

## 10. Testing

Three independent suites, none requiring the editor:

```bash
GODOT=/path/to/godot ./tests/run_all_tests.sh
```

| Suite | What it covers | How it runs |
|---|---|---|
| `tests/test_pod_graph.gd` | Chain/split/remove graph logic, score tiers | `godot --headless --script ...` (pure logic, no scene) |
| `tests/test_maze_generator.gd` | Determinism for a given seed, structural sanity (special cells are floor, border is solid, fragments don't overlap the fog room or exit) | Same, pure logic |
| `tests/boot_smoketest.tscn` + `tests/boot_game_smoketest.gd` | Actually instantiates `game.tscn` with real autoloads, spawns real players, builds a real tether link, runs ~2 seconds of physics | `godot --headless --path . res://tests/boot_smoketest.tscn` (a real scene boot, *not* `--script`, because `--script` mode does not run project autoloads — this is the one place that matters) |

All three currently pass against Godot 4.3-stable. If you add a new system, prefer extending the pure-logic suites (fast, no scene tree) and reserve the boot smoketest for things that only break when real nodes and autoloads are involved (like the `TileSet`-must-be-attached-before-touching-TileData ordering bug noted in `maze_tileset_builder.gd` — that class of bug is invisible to a pure unit test).

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
3. Use Run Multiple Instances to get 2+ players tethered together locally and deliberately snap a link.
4. Read `docs/DESIGN.md` sections 3 and 5 side-by-side with `tether_system.gd` — the code comments point back to specific design doc sections throughout.
5. Move on to real art (section 9 above) once the loop feels right — don't polish placeholder-art gameplay you might still rebalance.
6. Save online play (section 11) for last, after local play is confirmed fun. It's the highest-risk, most isolated piece.
