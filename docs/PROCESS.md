# Fogbound: The Process Guide

A mentor-style, step-by-step guide for someone with **zero game-development experience** who wants to understand this project and change it: the art, the rules, the levels, and the rest.

You do not need to read it top to bottom. Read parts 0 to 3 once (about 40 minutes), then use the rest as a cookbook: find the thing you want to change, follow the recipe, check the result.

You already know Python and web development (BCA), so this guide explains game ideas with analogies from those.

---

## Contents

| Part | What it gives you |
|---|---|
| 0 | How to work (the loop, the golden rules) |
| 1 | Setup: install, open, run, run the tests |
| 2 | The mental model: Godot in web/Python terms |
| 3 | A tour of the project: what every file is for |
| 4 | How Fogbound was made, phase by phase, and what went wrong |
| 5 | Your first five changes (about 10 minutes each) |
| 6 | Changing the rules (recipes) |
| 7 | Changing and adding levels |
| 8 | Changing the art, sound and UI |
| 9 | Network play: testing on one laptop and on real phones |
| 10 | Tests: what they protect, what to do when one fails |
| 11 | Git: saving your work and undoing mistakes |
| 12 | When something breaks (debugging) |
| 13 | A four-week learning roadmap and practice ladder |
| 14 | Glossary and cheat sheet |

A note on honesty: everything marked **Verified** was tried on the real project while writing this guide (the edit was made in a throwaway copy and the full test suite was run). Anything marked **Not tested here** is a pointer to official documentation, not a promise.

---

## 0. How to work

### The loop

Every change, however small, follows the same five steps:

| Step | Do | Why |
|---|---|---|
| 1. Predict | Write down what you expect to see change | If you cannot predict it, you have not understood the line you are editing |
| 2. Change | Edit **one** thing | Two changes at once means you cannot tell which one did it |
| 3. Run | Press F5 (or run the launcher), play offline with a fixed seed | A fixed seed gives you the same maze every time, so differences are your change |
| 4. Test | `./tests/run_all_tests.sh` | The tests catch the changes that look fine but break something far away |
| 5. Save or undo | `git commit` if you like it, `git restore <file>` if you do not | You can always get back to a working game |

### Golden rules

1. **Change one thing at a time, then run it.** The most common beginner trap is editing five files and then having a game that will not start.
2. **Use a fixed seed.** On the offline setup screen type `1234` in the Seed box. The maze, the clue positions and the exit code are then identical every run, so "before" and "after" are comparable.
3. **Work on a branch, never on `main`.** `git switch -c my-experiment` (see part 11). If it goes wrong, you delete the branch and nothing is lost.
4. **Read the red text.** Godot tells you the file and line of nearly every error (part 12).
5. **Numbers first, code later.** Most of what you will want to change (speed, rope length, scoring, level size) is a number in a table. You can do a lot without writing a single new line of code.

---

## 1. Setup

### 1.1 What to install

| Tool | What for | Where | Needed? |
|---|---|---|---|
| Godot **4.3** (the standard version, not ".NET") | Runs and edits the game | godotengine.org/download | Yes |
| Git | Saves your work, undo | git-scm.com | Yes |
| A text editor (VS Code is fine) | Reading code and docs | code.visualstudio.com | Optional: Godot has its own script editor |
| Python 3 + Pillow (`pip install pillow`) | Only to re-run the sprite and icon generators | python.org | Only for art recipes in part 8 |
| An image editor: Aseprite (paid), LibreSprite (free), Piskel (in the browser) | Drawing pixel art by hand | aseprite.org, libresprite.github.io, piskelapp.com | Only if you draw your own art |

Godot has no installer: you download a zip, unzip it, and run the program. Put it somewhere you will remember. Note its path; you will use it as `GODOT=/path/to/godot` for the test scripts.

Use **4.3** exactly. Later 4.x versions will likely work, but 4.3 is what this project was built and tested on.

### 1.2 Get the project

```bash
git clone https://github.com/shlokey755/fogbound.git
cd fogbound
git switch -c my-first-changes        # always work on your own branch
```

### 1.3 Open it in Godot

1. Start Godot. The **Project Manager** window opens.
2. Click **Import**, browse to the `fogbound` folder, pick `project.godot`, click **Open**, then **Import & Edit**.
3. The first open takes a little while: Godot is **importing** the art (turning the PNGs into its own format, stored in a hidden `.godot/` folder). That is normal.
4. Press **F5** (the Play button, top right). The game window opens with the main menu.

**Expected result:** a 1280x720 window with the title FOGBOUND and three buttons: **Play offline (bots)**, **Host game**, **Join game**, plus a Name box.

If there is no **Play offline (bots)** button, your copy of the code is older than pull request #3. Run `git switch main && git pull`, then create your branch again.

### 1.4 Play it once

1. Click **Play offline (bots)**.
2. On the setup screen type `1234` in **Seed**, leave the rest, click **START**.
3. Move with **WASD or the arrow keys**. The screen is dark: you can only see a small circle around you (that is the fog). A thin line (the rope) connects you to your teammates.
4. Walk into the small blue squares (clue tablets) to read them. A tablet shows a symbol. Read all of them (between you and your teammates), then one of you walks into the console in the middle of the fog room (the starting room). That unlocks the exit gate for your pod. Then **everyone in your pod must stand in the exit gate at the same moment**, at the edge of the maze, to escape.
5. The text in the top-left corner always tells you what to do next ("Pod 3 | Tablets 2/5 | Find the tablets").
6. Try to snap the rope: run away from your teammates. Notice the line go green, yellow, red. At 96 pixels it snaps for good.

Spend ten minutes here. You cannot change what you have not played.

### 1.5 Run the tests (this proves your setup works)

```bash
GODOT=/path/to/godot ./tests/run_all_tests.sh
```

On Windows use Git Bash (it comes with Git), or run the commands inside the script by hand.

**Expected result:** a long list of `PASS:` lines and the last line `All test suites passed.` It takes about a minute. If this fails on a fresh clone, fix that first (part 12) before changing anything.

### 1.6 Two ways to edit

| Way | How | Good for |
|---|---|---|
| In a text editor | Open the file, change it, save, press F5 in Godot | Numbers, text, code |
| In the Godot editor | Double-click a `.tscn` scene, click a node, change it in the **Inspector** panel on the right | Colours, sizes, labels, positions |

Both change the same files on disk. `.gd` files are scripts; `.tscn` files are scenes, and they are plain text too, so Git shows you exactly what you changed.

---

## 2. The mental model

### 2.1 Godot in web/Python terms

| Godot word | What it is | Web / Python analogy |
|---|---|---|
| **Node** | One object in the game (a sprite, a label, a camera, a timer) | A DOM element |
| **Scene** (`.tscn`) | A saved tree of nodes you can reuse | A component / an HTML page |
| **Script** (`.gd`) | Code attached to a node | The JavaScript attached to an element |
| **GDScript** | Godot's language | Python-like: indentation, `func` instead of `def`, `var x: int = 3` |
| **Autoload** | A script Godot loads once at startup and keeps forever, reachable by name from anywhere | A global module or singleton (`GameState.MOVE_SPEED`) |
| **Signal** | "Something happened" event that other code can listen to | `addEventListener`, a callback |
| **Inspector** | The side panel showing a node's properties | DevTools' element properties |
| **`res://`** | The project folder as the game sees it | The site root `/` |
| **`user://`** | A per-user folder for saves | `localStorage` |
| **Frame / physics tick** | The game loop runs the same function many times a second (here 60 physics ticks a second) | `requestAnimationFrame` |
| **Export** | Building a phone/PC app from the project | `npm run build` |

Two functions you will see everywhere:

```gdscript
func _ready() -> void:            # runs once, when the node enters the game
    ...
func _physics_process(delta):     # runs 60 times a second; delta = seconds since last time
    ...
```

`delta` is why speeds are written as "pixels per second": movement per tick = speed x delta.

### 2.2 The three ideas that matter most in Fogbound

**1. Units.** One tile is 16 pixels and counts as 1 metre. The screen is only 320 x 180 pixels (20 x 11 tiles), scaled up to fit your window. So "64" for speed means 64 pixels per second = 4 tiles per second. Almost every number in the game is in pixels.

**2. The host decides everything.** In a multiplayer game somebody has to be the referee. In Fogbound it is the **host**: it runs the physics, the rope, the scoring. Other devices only send "I am pressing right" and draw what the host tells them. Offline mode reuses this: with no network, your own computer is its own host and the bots are players that press buttons by themselves. That is why one set of rules serves offline, laptop and phone play.

**3. The seed.** A seed is a number that decides the "random" maze. Same seed, same level, same maze, on every device. That is why the other phones do not need the maze sent to them: each builds it from the seed.

### 2.3 How a match flows

```
Main menu
  |-- Play offline -> setup screen ----------------------\
  |-- Host game ----> lobby (host picks level) -----------+--> game.tscn --> score screen --> menu
  '-- Join game ----> room list -> lobby (waits for host)-/
```

Inside `game.tscn`: build the maze from the seed, spawn every player, link them with ropes in a chain, then every 1/60 s the host moves players, stretches ropes, checks who is in the console or the exit, and every 1/20 s sends everyone a snapshot of positions and rope states.

---

## 3. A tour of the project

### 3.1 The folders

| Folder | Contains | You edit it when you want to change... |
|---|---|---|
| `autoload/` | Always-loaded singletons: constants, scoring, levels, saves, networking | **Rules and numbers** (this is where you will spend most time) |
| `scenes/` | `.tscn` files: menu, lobby, game, player, clue, score screen | Layout, labels, simple visuals |
| `scripts/` | The logic: maze, rope physics, fog, bots, screens | Behaviour that numbers cannot express |
| `shaders/` | One small program that recolours the scarf by team | Team colours technique |
| `assets/` | Sprite sheets and icon images | **Art** |
| `tools/` | Python scripts that generate the art, and the multi-window launcher | Re-generating art, testing |
| `tests/` | Automatic checks | When you add a rule or a feature |
| `server/` | The (not yet connected) online room-code server | Only when you do online play |
| `docs/` | Design document, build walkthrough, art walkthrough, and this guide | Explanations |

### 3.2 The files that matter

| File | One-line purpose | Change it to... |
|---|---|---|
| `autoload/game_state.gd` | **All the tunable numbers** (speed, vision, rope, minimum team) and the match state | Make the game easier/harder |
| `autoload/score_table.gd` | Points for how intact your team stays | Change scoring |
| `autoload/level_data.gd` | The table of levels (size, number of tablets, colours) | Add or tweak levels |
| `autoload/commentary_data.gd` | The text of the "developer commentary" notes | Write your own notes |
| `autoload/save_data.gd` | What is saved on this device (unlocked levels, your name) | Rarely |
| `autoload/net_router.gd` | Every network message in one place: lobby, start, input, snapshots | Add a networked feature |
| `autoload/net_local.gd` | Host/join over Wi-Fi and the room finder | Network troubleshooting |
| `scripts/net_discovery.gd` | The room-finding message format and address maths | Rarely |
| `scripts/game_controller.gd` | The referee: builds the match, snaps, scoring, HUD, snapshots | Match rules, the HUD line |
| `scripts/tether_system.gd` | The rope: spring physics, colours' thresholds, snapping | Rope feel |
| `scripts/pod_graph.gd` | "Who is still connected to whom" | Almost never |
| `scripts/maze_generator.gd` | Builds a maze from a seed | Maze shape |
| `scripts/player.gd` | One player's body, animation, light | Player behaviour |
| `scripts/player_sprites.gd` | Knows the sprite-sheet layout and team colours | Add a character or animation |
| `scripts/fog_controller.gd` | The darkness and the light around players | Fog look |
| `scripts/clue.gd`, `clue_spawner.gd` | The tablets | Clue behaviour |
| `scripts/bot_*.gd` | The computer players | Bot behaviour |
| `scripts/main_menu.gd`, `join_screen.gd`, `lobby.gd`, `offline_setup.gd`, `score_screen.gd` | The screens | UI behaviour |
| `scripts/compact_theme.gd` | The UI font size for the tiny 320 x 180 screen | UI size |
| `scripts/maze_tileset_builder.gd` | Makes the flat-colour floor/wall tiles in code | Replace with real tile art |
| `scenes/main_menu.tscn` | Title and button text | Menu wording |
| `scenes/game.tscn` | The game world: console, exit, camera, HUD | Visuals of the console/exit |
| `project.godot` | Project settings (window size, autoload list) | Window size |
| `tools/make_sprites.py` | Draws the four characters | Re-colour or redesign characters |
| `tools/run_instances.sh` / `.bat` | Opens several game windows | Testing |
| `tests/run_all_tests.sh` | Runs every test | Always |

### 3.3 Where do I look for X?

| I want to find... | Look in |
|---|---|
| "Why is the player this fast?" | `GameState.MOVE_SPEED` in `autoload/game_state.gd` |
| "Where is the rope length?" | `TETHER_L0` and `TETHER_DMAX` in the same file |
| "Where does the rope turn red?" | `EDGES` in `scripts/tether_system.gd`, colours in `_tension_color` in `scripts/game_controller.gd` |
| "Where are points decided?" | `autoload/score_table.gd` |
| "Where do players get eliminated?" | `_eliminate_small_pods` in `scripts/game_controller.gd` |
| "Where is the top-left text?" | `hud_text` in `scripts/game_controller.gd` |
| "Where are the menu words?" | `scenes/main_menu.tscn` |
| "What do host and joiner say to each other?" | `autoload/net_router.gd` (search for `@rpc`) |

Searching is your best tool. In VS Code press Ctrl+Shift+F; in Godot press Ctrl+Shift+F too (Find in Files).

---
## 4. How Fogbound was made

This is the build story, in the order things were added. Knowing the order tells you which parts are old and stable and which are newer.

### 4.1 The idea

From `docs/DESIGN.md`: a 2D top-down maze for up to 16 players. You start in a dark "fog room" where you can see only a tiny circle around you. Everybody on your team is tied to a neighbour by a rope. Walk too far from your neighbour and the rope stretches, turns red, and **snaps for good**. Read clue tablets scattered through the maze, type the code at the console in the fog room, and escape through the exit gate. The more of your team is still attached when you escape, the more points you get.

The one-line pitch: *nobody can see far, nobody can let go, and one wrong sprint can cut your team in half.*

### 4.2 The phases

| Phase | What was built | Main files | Why it came in this order |
|---|---|---|---|
| 1. MVP | A seeded maze with a central fog room; darkness and light; a spring-like rope with four colours (green, yellow, red, critical) that can snap; "pods" (groups still connected); the rule that a pod of one is eliminated; clue tablets, the console and the exit; scoring tiers; LAN multiplayer with a basic lobby | `maze_generator.gd`, `fog_controller.gd`, `tether_system.gd`, `pod_graph.gd`, `game_controller.gd`, `score_table.gd`, `net_*.gd` | The game is only worth building the rest of if the rope feels good, so the rope came first |
| 2. Content | A table of six levels plus a hidden seventh; four characters; the icon; "developer commentary" pickups; small seeded puzzle rooms joined by tunnels | `level_data.gd`, `tools/make_sprites.py`, `player_sprites.gd`, `commentary_data.gd`, `maze_generator.gd` | Content is cheap once the systems exist, and it turns "a tech demo" into "a game" |
| 3. Offline mode with bots | You plus computer teammates, optionally rival computer pods, three skill levels | `offline_setup.gd`, `bot_*.gd` | You cannot test a multiplayer game alone unless something else plays |
| 4. Hosted play made real | A Host button, a Join button with a room list that fills itself, a lobby where the host chooses the level, laptop-friendly testing, a two-process automated test | `net_local.gd`, `net_discovery.gd`, `lobby.gd`, `join_screen.gd`, `tools/run_instances.*`, `tests/net_e2e.*` | The first hosted version was never actually playable: joining devices saw an empty screen |

### 4.3 Decisions you should know about (and why)

| Decision | Why | Consequence for you |
|---|---|---|
| **All tunable numbers in one file** (`autoload/game_state.gd`) | The host and every device must agree on the physics, and balance work means changing numbers often | To tune the game you mostly edit one file |
| **The host runs the rules, others draw** | Two devices computing physics separately drift apart; one referee cannot disagree with itself | Never put game rules in code that clients run (`player.gd` is a good example of what is host-only) |
| **Same seed on every device builds the same maze** | Sending a 51 x 51 maze to 15 phones is wasteful | If you change the maze generator, every device must run the same version of it |
| **Offline mode is not a separate game** | With no network, Godot's default peer makes your computer its own host. Bots are players with ids 2, 3, ... that press buttons by themselves | A rule change applies to offline and hosted play at once |
| **Fog is made with Godot's 2D lights** | Walls then block sight "for free" | If you change wall tiles you must keep their light occluders (part 8) |
| **Scoring is a ratio, not a head-count** | It works for teams of any size, not just 2, 4, 8, 16 | If you change the tiers, mind the special case for tiny teams (part 6) |
| **Characters are generated by a Python script** | There was no artist; the script is reproducible and easy to tweak | You can re-colour a character by changing a tuple and re-running the script (part 8) |
| **Joiners ask for rooms; hosts answer** | Phone hotspots drop broadcast announcements first | An empty room list usually means the network, not the game (part 9) |
| **Tests check real scenes, not mocks** | The worst bugs are the ones that only appear when real nodes and autoloads exist together | Tests are slower but trustworthy; run them |

### 4.4 Bugs that were found, and what they teach

These are real bugs from this project's history. Each one is a pattern you will meet again.

| Bug | Symptom | Cause | Lesson |
|---|---|---|---|
| Joining devices showed an empty screen | Hosted play was unplayable on every device except the host | Only the host created the `Player` nodes; clients were supposed to draw snapshots of nodes that did not exist | If something shows nothing, ask "who creates this?". Found only when a second process joined |
| Host's own lobby button did nothing | Host could not choose a pod | In Godot an RPC addressed to yourself never runs | Code that works for "other people" can silently skip "me" |
| JSON turned numbers into the wrong type | Lookups of player 1 failed even though player 1 was there | `JSON.parse_string` makes every number a float and every key a string | When data crosses a network, check types on the other side. `NetRouter._parse_json_with_ints` fixes it |
| Unknown level accepted | Host could set a level number that did not exist | `LevelData.get_level()` silently returns level 0 for an unknown id, so "it exists" looked true | A "safe" fallback can hide bad input. Check the id itself |
| A test script that did not parse hung forever | Test run never finished | Godot runs a scene with a broken script as an empty scene | The runner now has a time limit and demands the text `ALL TESTS PASSED` |
| `--script` tests could not see the autoloads | A test crashed on `GameState` | `godot --script` does not start the project's singletons | Pure-logic tests use `--script`; anything that needs the singletons runs as a real scene |
| An offline button that was not there | The user ran `main` and saw no Offline button | The feature branch was merged into another feature branch instead of `main` | In Git, check **what a pull request merges into** (part 11) |
| `--name=Ann` overwrote the saved name | A throwaway test window renamed the real player | The test shortcut used the same save path as normal play | Test shortcuts must not leave marks on real data |

### 4.5 Where to read more

| Read | When |
|---|---|
| `docs/DESIGN.md` | You want the design intent: numbers, rules, open questions |
| `docs/WALKTHROUGH.md` | You want a code-level tour of every system |
| `docs/ART_WALKTHROUGH.md` | You are about to replace art |
| Comments at the top of each `.gd` file | They explain why that file exists |

---
## 5. Your first five changes

Each one takes about ten minutes, needs no new code, and follows the loop from part 0. Do them in order. For each: set the offline seed to `1234` (so the maze is identical), play for a minute before the change, then after.

> To see ropes quickly: **Play offline**, set **Bot mates** to 1, **Rivals** to 0, seed `1234`, START. You and one bot are tied together. Walk away from the bot and watch the rope go green, yellow, red.

### 5.1 Change the title

| | |
|---|---|
| **Predict** | The big word at the top of the main menu changes |
| **Where** | `scenes/main_menu.tscn`, the node `VBox/Title` |
| **In the Godot editor** | In the FileSystem panel double-click `scenes/main_menu.tscn`. In the Scene panel click **Title**. In the Inspector change **Text**. Save with Ctrl+S |
| **In a text editor** | Find `text = "FOGBOUND"` and change the words inside the quotes |
| **See it** | Press F5. The menu shows your title |
| **Watch out** | Do **not** change the first word of the three buttons ("Play offline", "Host game", "Join game"): a test checks that each starts with those words. If you want other words, change the test in `tests/boot_game_smoketest.gd` too |
| **Undo** | `git restore scenes/main_menu.tscn` |

### 5.2 Make the player faster

| | |
|---|---|
| **Predict** | You cross the room quicker. Ropes get easier to snap, because you outrun your neighbour sooner |
| **Where** | `autoload/game_state.gd`: `const MOVE_SPEED := 64.0` |
| **Edit** | `64.0` to `96.0` (pixels per second: 64 = 4 tiles a second, 96 = 6) |
| **See it** | F5, offline, seed `1234`. Walk in a straight line and count seconds to cross the fog room, before and after |
| **Verified** | With `96.0` the whole test suite still passes. Bots scale with it (they use a fraction of `MOVE_SPEED`) |
| **Watch out** | `tests/test_bots.gd` has its own copy (`const MOVE := 64.0`) for its rope simulations. If you keep the new speed, update that copy too |
| **Undo** | `git restore autoload/game_state.gd` |

### 5.3 Make the fog easier to see in

| | |
|---|---|
| **Predict** | The small circle of light in the fog room gets bigger |
| **Where** | `autoload/game_state.gd`: `VISION_FOG := 24.0` (pixels; 24 px = 1.5 tiles). `VISION_NORMAL := 80.0` is the radius outside the fog room |
| **Edit** | `24.0` to `40.0` |
| **See it** | F5, offline: start in the fog room and compare the light circle |
| **Verified** | With `40.0` the whole test suite passes |
| **Undo** | `git restore autoload/game_state.gd` |

Why it works: the light on each player is scaled from these radii in `Player._update_light_radius()`. The game's darkness is Godot's `CanvasModulate` plus a `PointLight2D` on each player.

### 5.4 Make the rope longer

| | |
|---|---|
| **Predict** | You can walk further from your neighbour before the rope turns yellow, red, and snaps |
| **Where** | `autoload/game_state.gd`: `TETHER_L0 := 48.0` (the rope starts pulling here) and `TETHER_DMAX := 96.0` (it snaps here) |
| **Edit** | `TETHER_L0` to `64.0` and `TETHER_DMAX` to `128.0`. **Change both, keeping DMAX about double L0**, because the colours are fractions of DMAX (green below 50 %, yellow 50 to 80 %, red 80 to 100 %). If DMAX moves and L0 does not, the rope turns yellow before it starts pulling |
| **See it** | F5, offline, 1 bot mate, 0 rivals: walk away from the bot. Before: it snaps at about 96 px. After: about 128 px |
| **Verified** | With both edits the whole test suite passes. Changing only DMAX to 128 also passes |
| **Watch out** | `tests/test_bots.gd` keeps its own copy of `DMAX` (`const DMAX := 96.0`) |
| **Undo** | `git restore autoload/game_state.gd` |

### 5.5 Make the corner grace period longer

| | |
|---|---|
| **Predict** | When the rope is wrapped around a wall corner and fully stretched, you get longer before it snaps |
| **Where** | `autoload/game_state.gd`: `TETHER_SNAG_BUFFER := 1.5` (seconds) |
| **Edit** | `1.5` to `3.0` |
| **See it** | Hard to test by hand. Stretch the rope around a corner and watch the dark-red state last longer |
| **Why it exists** | A rope hooked on a corner looks longer than it really is. Without a grace period you are punished for the maze's shape. This is one of the developer commentary notes (`tether_snag_buffer` in `commentary_data.gd`) |
| **Undo** | `git restore autoload/game_state.gd` |

After each change, run the tests (`./tests/run_all_tests.sh`). You are checking two things: that the game still starts, and that your change did not surprise something else.

### 5.6 Your first real code change: a match timer

Everything so far was a number. This one is a few lines of code, so you learn what code looks like here. Goal: the top-left text becomes `Pod 3 | Tablets 2/5 | Find the tablets | 1:07`.

The text comes from `hud_text()` in `scripts/game_controller.gd`. We add a variable that counts seconds and print it.

**Step 1.** Near the other `_hud` variables at the top of the file, add one variable:

```gdscript
var _hud_t := 0.0
var _elapsed := 0.0              # seconds since the match started   <-- new
```

**Step 2.** At the very top of `_physics_process`, add one line that adds the time since the last tick (this function runs 60 times a second; `delta` is that tiny slice of time):

```gdscript
func _physics_process(delta: float) -> void:
	_elapsed += delta            # <-- new
	_update_tether_lines()
	...
```

**Step 3.** At the end of `hud_text()`, replace the last line (the `return`) with:

```gdscript
	var clock := "%d:%02d" % [floori(_elapsed / 60.0), int(_elapsed) % 60]
	return "Pod %d | Tablets %d/%d | %s | %s" % [_local_pod_size(), _revealed.size(), total, objective, clock]
```

How to read it: `"%d:%02d"` is a format string (like Python's `%`): the first number is minutes, the second is seconds padded to two digits. `floori(x / 60.0)` rounds down; `% 60` is the remainder.

**See it:** F5, offline, start a match. The clock runs in the top-left corner.

**Verified:** with exactly this change the full test suite passes (the HUD test only checks the beginning and a few phrases).

**Undo:** `git restore scripts/game_controller.gd`

Congratulations: you have changed a number, a scene and code, and checked all of it with tests.

---

## 6. Changing the rules

### 6.1 Every number, in one table

All live in `autoload/game_state.gd` unless noted. Units: pixels and seconds. One tile = 16 px.

| Constant | Default | Meaning |
|---|---|---|
| `MOVE_SPEED` | 64.0 | Walking speed (px/s) |
| `VISION_NORMAL` | 80.0 | Light radius outside the fog room (5 tiles) |
| `VISION_FOG` | 24.0 | Light radius inside the fog room (1.5 tiles) |
| `LANTERN_BONUS`, `LANTERN_LINK_BONUS` | 24.0, 12.0 | Reserved for a lantern item that is **not in the game yet**; nothing sets `carrying_lantern` today |
| `TETHER_L0` | 48.0 | Rope rest length: no pull until you stretch past it |
| `TETHER_DMAX` | 96.0 | Snap distance |
| `TETHER_K` | 10.0 | Spring stiffness: higher = stronger pull |
| `TETHER_C` | 6.3 | Damping: resists the rope bouncing |
| `TETHER_SNAG_BUFFER` | 1.5 | Seconds of grace for a rope wrapped around a corner |
| `TETHER_PULL_FRICTION` | 10.0 | How fast leftover pull fades |
| `TETHER_PULL_CAP` | `[0.0, 0.25, 0.8, 0.8]` | How hard the rope may drag you, as a fraction of `MOVE_SPEED`, in green, yellow, red, critical |
| `MIN_TEAM_SIZE` | 2 | Smallest allowed pod; smaller pods are eliminated |
| `MAX_PLAYERS` | 16 | Players per match |
| Rope thresholds `EDGES` | `[0.50, 0.80, 1.00]` | In `scripts/tether_system.gd`: where green/yellow/red/critical begin, as fractions of `TETHER_DMAX` |

Everything is in **pixels**, so the game's units are consistent with the comments in the file (`# px, 5 m`). A "metre" in the comments is one tile.

### 6.2 How the rope works, in plain words

1. Two neighbours are joined by a rope with a rest length of 48 px. While they are closer than that, nothing happens (green).
2. Past 48 px the rope acts like a spring: it pulls both players toward each other, in proportion to the stretch (`TETHER_K`) and resists bouncing (`TETHER_C`).
3. How much of that pull actually moves you is capped by the rope's state: none in green, a quarter of your walking speed in yellow, 80 % in red. Moving at full speed away from a stationary mate still gains on the pull, so a sprint can break the rope.
4. When the stretch reaches `TETHER_DMAX` the rope is critical. It snaps at once, unless it is wrapped around a wall corner: then it gets `TETHER_SNAG_BUFFER` seconds, and snaps only if it is still stretched at the end.
5. A snap is permanent. The graph of who is connected to whom is recomputed (`pod_graph.gd`), and any pod smaller than `MIN_TEAM_SIZE` is eliminated.

The whole thing is `scripts/tether_system.gd` (about 170 lines). Reading it is a great week-3 exercise.

### 6.3 Change the scoring

The tiers are one array in `autoload/score_table.gd`:

```gdscript
const TIERS := [
	{"min_ratio": 1.0,   "points": 1200},  # complete, unbroken team
	{"min_ratio": 0.5,   "points": 500},   # half team
	{"min_ratio": 0.25,  "points": 200},   # half of the half
	{"min_ratio": 0.125, "points": 50},    # further split
	{"min_ratio": 0.0,   "points": 10},    # bare-minimum 2-player squad
]
```

`min_ratio` is "this fraction of your original team or more". The function above the array adds one special case: a tiny team (original size at most twice `MIN_TEAM_SIZE`) that is down to the minimum scores the bottom tier, rather than a ratio tier. Read its comment; it is a good example of a rule decided by thinking about edge cases.

**Example: make the half-team tier 600.**

1. Change `500` to `600` in `TIERS`.
2. Run `./tests/run_all_tests.sh`. **Expected:** it fails with `FAIL: half team (8 of 16) scores 500`. That is the test doing its job.
3. Open `tests/test_pod_graph.gd`, find that line (about line 75) and change `500` to `600` (also in the label text).
4. Run the tests again: they pass. Commit **both files together**.

**Verified:** changing the top tier from 1200 to 2000 fails two tests in `tests/test_pod_graph.gd` ("full team of 16 scores 1200", "full tiny team (2 of 2) still scores 1200").

**A trap:** the secret level unlocks when a pod scores the top tier, and `autoload/net_router.gd` (`_check_secret_level_unlock`) checks `points < 1200`. If you change the top tier's points, change that check too, and the smoketest that expects "unlocks after a 1200-point finish".

### 6.4 Change the minimum team size

`MIN_TEAM_SIZE` (default 2) is used by the lobby (every pod needs at least this many), by `_eliminate_small_pods` (smaller pods are eliminated) and by the scoring special case.

**Verified experiment:** setting it to `3` and running the tests produced exactly two failures, both because tests assume a pod of 2:

| Failing check | Why |
|---|---|
| `offline: losing a rival pod does not end the match` | The test builds a rival pod of 2, which is now below the minimum |
| `host: a lone player cannot start (pod needs 2)` | The test looks for the words "at least 2" in the lobby message |

To make the change properly: raise `MIN_TEAM_SIZE`, raise `OfflineSetup.MIN_RIVAL_SIZE` in `scripts/offline_setup.gd` to match (the setup screen would otherwise let you make rival pods that are already too small), and update the two tests to use the constant (`GameState.MIN_TEAM_SIZE`) instead of the number 2. Then run everything again.

This is a good example of an important lesson: **a rule is usually written down in more than one place.** Search the project for the constant's name (`MIN_TEAM_SIZE`) and for the bare number.

### 6.5 Change the number of tablets or the code symbols

- **How many tablets:** the level table (part 7). In `LevelDef.new(id, name, difficulty, width, height, FRAGMENTS, ...)` the number after the size is the tablet count. Puzzle room *i* holds tablet *i*, so keep the number of rooms at or below the tablet count (extra rooms would hold nothing).
- **Which symbols:** in `scripts/game_controller.gd`, the line `var symbols := ["#", "%", "@", "&", "*", "+", "=", "?"]`. Add or replace characters. The exit code is built from the seed on **every** device, so everyone agrees without sending it.
- **The exit rules:** when any member of a pod walks into the console, the pod unlocks the exit if its members, between them, have read every tablet (`_on_console_body_entered` in `game_controller.gd`). To escape, **every** member of the pod must then be standing in the exit gate at once (`_on_exit_body_entered`). The *order* of symbols does not matter today. Making it matter is practice-ladder task 13.

### 6.6 Change the bots

`scripts/bot_brain.gd` has the skill table:

```gdscript
const SKILLS := [
	{"name": "Easy",   "speed": 0.70, "sight": 2, "slack": 0.62},
	{"name": "Normal", "speed": 0.85, "sight": 3, "slack": 0.50},
	{"name": "Hard",   "speed": 1.00, "sight": 4, "slack": 0.42},
]
```

| Field | Meaning |
|---|---|
| `speed` | Top speed as a fraction of `MOVE_SPEED` |
| `sight` | How many tiles ahead the bot looks when exploring |
| `slack` | How tight the rope may get before a bot leader starts slowing (lower = more careful) |

Add a fourth row and the setup screen's Skill dropdown and the tests pick it up. The tests simulate whole matches, so a very reckless skill (high speed, high slack) may snap ropes and fail the "no rope snapped" checks. That is also a way to tune: if the test fails, your bot is too careless.

### 6.7 Offline and match limits

| What | Where | Default |
|---|---|---|
| Most players in a match | `GameState.MAX_PLAYERS` | 16 (the host plus 15) |
| Most rival pods, rival pod size range | `OfflineSetup.MAX_RIVAL_PODS`, `MIN_RIVAL_SIZE`, `MAX_RIVAL_SIZE` | 3, 2, 5 |
| How often the host sends positions | `SNAPSHOT_INTERVAL` in `game_controller.gd` | 1/20 s |
| Game and room-finding ports | `NetLocal.DEFAULT_GAME_PORT`, `DEFAULT_DISCOVERY_PORT` | 7777, 7778 |

### 6.8 Changing how the rope looks

`_tension_color()` in `scripts/game_controller.gd` returns a colour for each state. Colours are `Color(red, green, blue)` with each from 0.0 to 1.0:

```gdscript
TetherSystem.TensionState.GREEN:  return Color(0.3, 0.85, 0.3)
TetherSystem.TensionState.YELLOW: return Color(0.9, 0.85, 0.2)
TetherSystem.TensionState.RED:    return Color(0.9, 0.2, 0.2)
```

The line width is `line.width = 2.0` where the lines are created (`_update_tether_lines` and `_update_client_tether_lines`).

---

## 7. Changing and adding levels

### 7.1 What a level is

A level is **not** a hand-drawn map. It is a row in a table that says how big the maze is, how many tablets, and what colours. The maze itself is generated fresh from the match **seed**. Same level + same seed = same maze, on every device. A different seed gives a different maze of the same size.

The table is the `levels` array in `autoload/level_data.gd`:

```gdscript
LevelDef.new(2, "The Understreets", "Medium", 31, 31, 8,
	"The original proving ground -- enough corridors that a snapped link really costs you.") \
	.with_theme(Color(0.24, 0.22, 0.19), Color(0.35, 0.38, 0.44), Color(0.03, 0.03, 0.05)) \
	.with_puzzles(4, 3),
```

| Part | Meaning |
|---|---|
| `2` | The level id. Must be unique. The lobby sends this number to everyone |
| `"The Understreets"`, `"Medium"` | Name and difficulty label shown in the pickers |
| `31, 31` | Maze width and height in tiles. Use **odd** numbers (the generator rounds even ones up) |
| `8` | Number of tablets (fragments) |
| The sentence | Description shown in the pickers |
| `.with_theme(floor, wall, ambient)` | Floor colour, wall colour, and the darkness `CanvasModulate` multiplies by (keep it near black or the fog loses its menace) |
| `.with_puzzles(4, 3)` | 4 small rooms of 3 x 3 tiles, joined by tunnels, each holding a tablet |

The backslash `\` at the end of a line just continues the expression on the next line.

### 7.2 Recipe: add a level

1. Open `autoload/level_data.gd`.
2. Find the comment `# Secret level. Not shown in the lobby picker` and add **above** it:

```gdscript
	LevelDef.new(6, "Mirror Maze", "Hard", 41, 41, 10,
		"A new level added while learning.") \
		.with_theme(Color(0.20, 0.20, 0.30), Color(0.40, 0.40, 0.60), Color(0.04, 0.04, 0.08)) \
		.with_puzzles(4, 3),

```

3. Run the game, **Play offline**, open the **Level** dropdown: "Mirror Maze (Hard)" is there. Start it with seed `1234`.
4. Run the tests: the level-table pass in the smoketest generates a maze for every entry in the table and checks it can be solved (`tests/test_maze_generator.gd` separately checks reachability and that rooms fit across many seeds).

**Verified:** this exact level (id 6, 41 x 41, 10 tablets, 4 rooms) was added in a throwaway copy and the whole suite passed.

Rules of thumb (the maze tests check most of them):

| Rule | Why |
|---|---|
| The id is unique | Otherwise two levels collide |
| Puzzle rooms <= tablets | Room i holds tablet i; extra rooms would be empty |
| Odd sizes are best | The grid alternates walls and corridors |
| The theme stays dark | Brightness is part of the game's feel |

The level also appears in a hosted lobby's dropdown with no further work. Every device has the same table, which is why only the id is sent.

### 7.3 The secret level

Level `99` (`"???"`) is hidden from the pickers until it is unlocked on your device. It unlocks when your pod escapes level `5` (The Labyrinth Proper) with the **whole team still attached** (the top score tier, 1200 points). The unlock is stored in the save file (`user://fogbound_save.cfg`; in the Godot editor use **Project > Open User Data Folder** to find it).

To look at it without winning, open `autoload/level_data.gd`, find the level `99` row and change the `true,` that follows its description to `false,` (that is the `secret` flag). The level then appears in the picker. **Put it back to `true` before you commit**: the smoketest checks that the level really is hidden until unlocked.

---

### 7.4 Change what the maze looks like

| Want | Where |
|---|---|
| A bigger or smaller maze | The level's width/height |
| More loops (fewer dead ends) | `_add_loops(w * h / 40)` in `scripts/maze_generator.gd`; a smaller divisor knocks out more walls |
| A bigger fog room | `_carve_fog_room()` in the same file |
| Different tile colours per level | The two colours in `.with_theme` |
| Real tile art | Part 8.3 |

If you change the generator, run `tests/test_maze_generator.gd`: it checks that the same seed gives the same maze and that every special cell is reachable. A generator that makes unreachable exits is a broken game.

---

## 8. Changing the art, sound and UI

Rule of thumb: **repaint the files, keep the layout, and code rarely needs to move.** `docs/ART_WALKTHROUGH.md` is the detailed reference; this part gives you the recipes in order of effort.

### 8.1 Re-colour a character (easiest, uses Python)

The four characters are drawn by `tools/make_sprites.py`. In its `CHARACTERS` list each one has a few colours as `(red, green, blue, alpha)` from 0 to 255.

1. Install Pillow once: `pip install pillow`.
2. Open `tools/make_sprites.py` and find the Warden:

```python
dict(name="warden", skin=(158, 110, 78, 255), cloth=(150, 64, 64, 255), shade=(112, 44, 48, 255)),
```

3. Change `cloth` to green and `shade` to a darker green, for example `cloth=(40, 160, 90, 255), shade=(28, 112, 63, 255)`.
4. Run `python3 tools/make_sprites.py`. It rewrites the four PNGs in `assets/sprites/characters/`.
5. Focus the Godot editor (or run `godot --headless --path . --import`) so the PNGs re-import, then press F5.

**See it:** which character you are depends on your player id modulo 4: `peer_id % 4`. Offline you are id 1, which is character 1 (the Tinker). Bots are 2, 3, 4...: the Sprout, the Warden, the Wanderer. In a hosted game ids are random numbers, so players get random looks.

**Verified:** the Warden's tunic was changed this way in a throwaway copy and the whole suite passed (the tests check that every sheet is 96 x 128, keeps the magenta scarf marker, and has every animation).

`python3 tools/make_sprites.py --preview` also writes a scaled contact sheet to `/tmp/fogbound_sprite_preview.png` (a Linux/macOS path: on Windows edit the `out =` line in the script first).

**Undo:** `git restore assets/sprites tools/make_sprites.py`

### 8.2 Draw your own character

1. Open Aseprite, LibreSprite or Piskel. Make a canvas **96 x 128 pixels** and turn on a 16 x 16 grid.
2. Draw frames in the layout the code expects (6 columns by 8 rows of 16 x 16):

| Row | Animation | Frames |
|---|---|---|
| 0 | `idle_down` | 2 |
| 1 | `walk_down` | 4 |
| 2 | `idle_up` | 2 |
| 3 | `walk_up` | 4 |
| 4 | `idle_side` (face **right**) | 2 |
| 5 | `walk_side` (face right) | 4 |
| 6 | `pulled` | 2 |
| 7 | `eliminated` | 3 |

3. **The scarf must be pure magenta `#FF00FF`** (shadow side `#B400B4`). A shader (`shaders/team_palette.gdshader`) swaps those two colours for the player's team colour. Do not use those magentas anywhere else, and do not anti-alias the scarf, or you will get pink edges.
4. Export as PNG with transparency and save it **over** `assets/sprites/characters/char_1_tinker.png` (keep the name).
5. Re-import and press F5.

**Adding a fifth character:** save `char_4_name.png` in the same folder, add its file name to `SHEETS` in `scripts/player_sprites.gd`, and re-import. The smoketest loops over `PlayerSprites.character_count()`, so it checks your new sheet's size and scarf marker automatically.

**Team colours** are in `PlayerSprites.TEAM_COLORS` (16 colours, one per possible team).

### 8.3 Floor and wall tiles

Today the tiles are flat colours made in code by `scripts/maze_tileset_builder.gd`. To use your own: draw a **48 x 16** strip (floor | wall | puzzle-room floor), save it as `assets/tilesets/maze_tiles.png`, then follow **Option A** in `docs/ART_WALKTHROUGH.md` section 3 (replace the body of `_make_atlas_texture`). Walls keep their collision and light-blocking because `build()` adds them.

**Not tested here:** I verified the placeholder tiles and the description of the swap, but did not swap in real tile art. Use the "see it change" check in the art walkthrough. Two things the guide cannot stress enough:

- Keep the atlas coordinates `(0,0)` floor, `(1,0)` wall, `(2,0)` puzzle floor.
- With Option A the per-level floor and wall colours stop applying (the picture is fixed), but the level's darkness still does.

### 8.4 Clue, console, exit and pickup pictures

They are plain coloured rectangles. For each, add a `Sprite2D`, give it your texture, and delete the `ColorRect`.

| Visual | Scene | Node to replace |
|---|---|---|
| Clue tablet (blue) | `scenes/clue.tscn` | `ColorRect` (an empty `Sprite2D` is already waiting) |
| Console, exit gate | `scenes/game.tscn` | `ConsoleVisual`, `ExitVisual` |
| Commentary pickup (yellow) | `scenes/commentary_node.tscn` | `ColorRect` |
| On-screen joystick | `scenes/touch_joystick.tscn` | the `ColorRect`s |

Keep the picture centred on the node's origin; the collision shape is centred there. Use 16 x 16 for tablets and 32 x 32 for console and exit.

### 8.5 Menu wording, fonts and UI size

| Want | How |
|---|---|
| Change a menu word | `scenes/main_menu.tscn` (part 5.1). Other screens build their text in code: search for `.text = "` in `scripts/lobby.gd`, `join_screen.gd`, `offline_setup.gd` |
| Make all UI text bigger or smaller | `CompactTheme.make(font_size: int = 10)` in `scripts/compact_theme.gd`. Screens call `CompactTheme.make()`; change the default `10`. The screen is only 320 x 180, so text over about 12 overflows |
| Use a custom font | Put a `.ttf` in `assets/fonts/`, make a Theme that uses it and set it in Project Settings > GUI > Theme > Custom (see `docs/ART_WALKTHROUGH.md` section 6) |
| Window size on your laptop | `window_width_override` / `window_height_override` in `project.godot` (1280 x 720) |
| The game's drawing resolution | `viewport_width` / `viewport_height` (320 x 180). Changing it changes how much of the maze is visible, and the whole look |
| Developer commentary text | `autoload/commentary_data.gd`: add `Note.new("a_unique_id", "Title", "Body text")`. Keep ids unique and never rename an existing one (saves remember them) |

### 8.6 Add a sound (a snap sound)

Nothing plays sound today. This recipe adds a short crack when a rope snaps. You need a short sound file: generate one with the Python below, or download a free `.wav` (check its licence) or make one with sfxr/jsfxr.

**Step 1.** Make a test sound (`python3 make_snap.py`, run from the project folder):

```python
import wave, struct, math, os
os.makedirs("assets/audio", exist_ok=True)
w = wave.open("assets/audio/snap.wav", "wb")
w.setnchannels(1); w.setsampwidth(2); w.setframerate(22050)
frames = b""
for i in range(int(22050 * 0.25)):
    t = i / 22050
    v = int(32000 * math.exp(-t * 18) * math.sin(2 * math.pi * (900 - 2500 * t) * t))
    frames += struct.pack("<h", max(-32767, min(32767, v)))
w.writeframes(frames); w.close()
```

**Step 2.** Let Godot import it (focus the editor or `godot --headless --path . --import`).

**Step 3.** In `scripts/game_controller.gd` add one helper function, and call it from **two** places. There are two because the host learns about a snap in `_on_host_link_snapped`, while other devices learn about it from a network message handled by `_on_link_snapped_visual`. The host never gets that message, so a sound added only to the second function would play on joiners but not on the host.

```gdscript
## One short sound, played by a player created on the spot and removed when it ends.
func _play_snap_sound() -> void:
	var sfx := AudioStreamPlayer.new()
	sfx.stream = load("res://assets/audio/snap.wav")
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
```

and as the **first line** of both `_on_host_link_snapped(...)` and `_on_link_snapped_visual(...)`:

```gdscript
	_play_snap_sound()
```

**See it:** F5, offline, snap a rope (run away from your bot). You hear the sound.

**Verified:** with this change the whole test suite passes. Because the tests run without a sound card, the two-process test's host prints one harmless line at the very end, `ERROR: 1 resources still in use at exit` (most likely a sound that was still playing when the program quit, since the host's rope snaps when the joiner leaves). You can ignore it.

Other natural hooks, from `docs/ART_WALKTHROUGH.md` section 6: the tension states (`tether_system.gd`), reading a tablet, the exit unlocking.

### 8.7 The icon

`tools/make_icon.py` draws the icon and writes `icon.svg`, `assets/icon/fogbound_icon_512.png` and `assets/icon/fogbound_icon_192.png`. To use your own artwork, replace those three files and keep the names. For an Android build also set **Project > Export > Android > Icons**.

### 8.8 Getting the game onto a phone

**Not tested here.** The outline, from the Godot documentation ("Exporting for Android"):

1. In the Godot editor: **Editor > Manage Export Templates**, download the templates for 4.3.
2. Install the Android SDK and a JDK, and point **Editor Settings > Export > Android** at them.
3. **Project > Export > Add... > Android**. Tick **Internet** under Permissions (needed for the game connection).
4. Plug in a phone with USB debugging on and use the one-click deploy button, or export an APK and copy it over.

Plan an afternoon for this the first time. Android setup problems are about the tools, not about Fogbound.

---
## 9. Network play

### 9.1 What actually happens (so the problems make sense)

Wi-Fi is set up **outside the game**, in the phones' settings. After that:

1. The host taps **Host game**. The game opens the port **UDP 7777** (the game connection) and listens on **UDP 7778** (room finding), then shows the lobby.
2. A joiner taps **Join game**. Every second or so it sends a tiny question ("any Fogbound here?") to this machine, to the broadcast address, and to every address in its own `x.y.z.1` to `x.y.z.254` range. Nobody types an address; the list fills itself.
3. The host answers each question with one line: room name, players, level, port. The joiner lists it.
4. Tapping the room opens the game connection to port 7777. The host puts the new player in Pod A and sends the whole lobby to everyone.

If step 2 or 3 is blocked by the network, the room list stays empty. There is no address box to fall back on: the fix is a different network (part 9.3). The screen re-reads the phone's addresses on every search, so joining the hotspot while it is open works, and **Search again** restarts the search by hand.

### 9.2 Test on one laptop (no phones)

```bash
GODOT=/path/to/godot tools/run_instances.sh 2        # Windows: set GODOT=..., then tools\run_instances.bat
```

| Step | Do | Expect |
|---|---|---|
| 1 | Run the command | Two windows open, each 640 x 360. Window 1 is already in a lobby named "Host's room" |
| 2 | Look at window 2 | It is on the join screen, finds the room, and joins by itself. You now see two names in the lobby |
| 3 | In window 2 tap **Ready** | The host's status line changes to "Everyone is ready. Press START." |
| 4 | In the host window pick a level from the dropdown | Window 2's level line changes at once |
| 5 | Host presses **START** | Both windows load the maze |
| 6 | **Click inside a window**, then use WASD or the arrows | Only the window you clicked moves. You can see the other window's player move too |

Use `tools/run_instances.sh 3` or `4` for more players. Everybody lands in Pod A, so they start as one team; use **New pod** in a window to split off and test several pods.

**Doing it by hand** (no script): run the game twice (in the Godot editor use *Debug > Customize Run Instances*, or start the exported game twice). In the first press **Host game**; in the second press **Join game** and click the room that appears.

Things that trip people up:

| Problem | Reason | Fix |
|---|---|---|
| "Could not host: port 7777 is busy" | A second host on the same machine (the ports are fixed) | Only one hosting window per machine. Close the other game |
| The firewall asks for permission | Normal: you are opening a network port | Allow on private networks |
| Pressing keys moves nothing | The other window has the keyboard focus | Click inside the window you want to drive |
| Window 2 does not join | The host window had not opened its room yet | Run the script again; the script waits 2 seconds, a slow machine may need more |

### 9.3 Test on real phones

**Not tested here:** I could not use real phones or a real hotspot from where this guide was written. The two-process test proves the game's side works; only a real network tells you whether your hotspot lets phones talk to each other.

**Before you start:** export an Android build (part 8.8) or run the game on laptops that share the phone's hotspot. Both devices need the game's network permission; on Android the export preset must have **Internet** ticked (Project > Export > Android > Permissions).

| # | Do | Expect | If not |
|---|---|---|---|
| 1 | Phone A: turn on the hotspot | Hotspot is on | - |
| 2 | Phone B (and C ...): connect to A's Wi-Fi in the phone settings | Wi-Fi shows connected, no internet is fine | Turn off mobile data on B; some phones prefer it over a Wi-Fi with no internet |
| 3 | Phone A: open Fogbound, tap **Host game** | Lobby appears. Banner reads `Name's room  (1/16)` | If the joiners never see the room, check step 1 and the table below |
| 4 | Phone B: tap **Join game** | Within a few seconds the room appears in the list. Until then the screen says what it is waiting for (not on a Wi-Fi, or searching) | Tap **Search again**; see the table below |
| 5 | Tap the room | You land in the lobby; Phone A sees your name | If it says "The host did not answer": a firewall or the phone is blocking UDP 7777 |
| 6 | B: tap **Ready**. A: tap **START** | Everyone loads the maze | Read the status line on A; it says exactly what is missing |
| 7 | Walk around | Each phone moves its own character and sees the others | If movement looks jumpy, the Wi-Fi is weak; try standing closer |

**The room list stays empty:**

| Likely cause | Check | Fix |
|---|---|---|
| Not on the same network | Both devices show the same Wi-Fi name | Reconnect |
| Mobile data is winning over the hotspot | The hotspot has no internet and the phone quietly uses mobile data for apps | Turn off mobile data on the joining phone, then tap **Search again** |
| The network isolates devices from each other ("AP isolation" or "client isolation", common on public Wi-Fi, guest networks and some hotspots) | A laptop on that network cannot ping a phone | Use a different hotspot, or a home router without isolation |
| A firewall on a laptop host | Windows/macOS firewall asks and was denied | Allow the game on private networks |
| The host is not hosting | Host phone is still on the menu | Tap **Host game** |
| The match already started | The row says `[in progress]` | Wait or ask the host to open a new room |

**There is no typing fallback any more.** If the table above does not fix it, the network is blocking phone-to-phone traffic; use a different hotspot, or a home router without isolation.

### 9.4 What the network does not do (yet)

| Not built | Meaning |
|---|---|
| Online room codes | Playing over the internet; scaffolded in `server/` and `autoload/net_online.gd`, not connected. `docs/WALKTHROUGH.md` section 11 lists the steps |
| Bots in hosted matches | Bot ids (2, 3, ...) could collide with real player ids |
| Reconnect | If a player disconnects mid-match, their rope is treated as snapped |
| Host leaving | Ends the match for everyone |

---

## 10. Tests: what they protect

### 10.1 Why you want tests

Think of a test as a tiny script that plays one rule and shouts if the answer is wrong. This project has hundreds of checks. They exist because many bugs only show far from where you changed something: change a rope number and a bot test fails because the bots now snap their ropes.

### 10.2 Run them

```bash
GODOT=/path/to/godot ./tests/run_all_tests.sh        # everything, about a minute
```

| Suite | Run alone with | Protects |
|---|---|---|
| Pod graph and scoring | `$GODOT --headless --path . --script res://tests/test_pod_graph.gd` | Who is connected, who scores what |
| Maze generator | `... --script res://tests/test_maze_generator.gd` | Same seed gives same maze; the maze is solvable; rooms and tunnels are placed |
| Room finding | `... --script res://tests/test_net_discovery.gd` | The message format and address maths |
| Bots | `... --script res://tests/test_bots.gd` | Bots navigate, stay fair, finish every level |
| Scene smoketest | `$GODOT --headless --fixed-fps 60 --path . res://tests/boot_smoketest.tscn` | Real scenes: menu, lobby rules, game wiring, snapshots, HUD, sprites, whole simulated matches |
| Two-process game | `./tests/net_e2e.sh` | Host and joiner really talk |

The last lines tell you the result: `ALL TESTS PASSED`, or `FAIL: <what>` for each failure.

### 10.3 When a test fails after your change

Do not panic and do not delete the test. Ask:

| Question | If yes |
|---|---|
| Did I **mean** to change this behaviour? | Update the test to expect the new behaviour, in the same commit |
| Did I change a number that a test **copied**? | Update the copy (see the table below) |
| Did I break something I did not mean to? | Undo your change (`git restore <file>`) and look again |

Places where a test (or other code) **holds its own copy of a number** and so will not follow you automatically (**Verified** by experiment, see part 6):

| If you change | Also look at |
|---|---|
| Top score `1200` | `tests/test_pod_graph.gd` (expects 1200) and `autoload/net_router.gd` `_check_secret_level_unlock` (checks for 1200) |
| Other score tiers | `tests/test_pod_graph.gd` |
| `MIN_TEAM_SIZE` | `OfflineSetup.MIN_RIVAL_SIZE`, the smoketest's rival pod of 2, and the lobby test's text "at least 2" |
| `MOVE_SPEED` or `TETHER_DMAX` | `MOVE` and `DMAX` at the top of `tests/test_bots.gd` (a copy, used for its rope simulations) |

### 10.4 Write a new test

The simplest pattern is `tests/test_net_discovery.gd`. A test file is a script that calls a function and checks the answer:

```gdscript
extends SceneTree

var failures := 0

func _init() -> void:
    _check("2 + 2 is 4", 2 + 2 == 4)
    quit(0 if failures == 0 else 1)

func _check(label: String, condition: bool) -> void:
    print(("PASS: " if condition else "FAIL: ") + label)
    if not condition:
        failures += 1
```

Run it with `$GODOT --headless --path . --script res://tests/my_test.gd`, then add one line to `tests/run_all_tests.sh` so it runs with the rest. Scripts run this way **cannot see autoloads** (`GameState`, `LevelData` ...). If you need them, add your check to `tests/boot_game_smoketest.gd` instead (follow the `_run_lan_lobby_pass` function).

---

## 11. Git: saving your work and undoing mistakes

Git is the safety net that makes experimenting free.

### 11.1 The everyday cycle

```bash
git switch -c my-change              # new branch for this idea (once)
# ... edit, run, test ...
git status                           # what changed?
git diff                             # exactly what changed, line by line
git add -A                           # stage everything (or: git add path/to/file)
git commit -m "Make the rope longer"
git push -u origin my-change         # upload the branch
```

Then open a **pull request** on GitHub (the "Compare & pull request" button). **Check the "base" branch at the top says `main`.** A pull request merged into any other branch does not reach `main`; that is exactly why the Offline button once went missing.

### 11.2 Undo table

| I want to... | Command | Notes |
|---|---|---|
| Throw away my unsaved edits to one file | `git restore path/to/file` | Cannot be undone, so check with `git diff` first |
| Throw away all unsaved edits | `git restore .` | Same warning |
| Un-stage a file I added | `git restore --staged path/to/file` | The edits stay |
| Set my work aside to try something else | `git stash`, later `git stash pop` | Like a clipboard for edits |
| Undo a commit I already made, safely | `git revert <commit-id>` | Makes a new commit that cancels the old one |
| Go back to the game as it was on main | `git switch main` | Your branch stays safe |
| Delete a failed experiment completely | `git switch main` then `git branch -D my-change` | Gone for good |
| See what I did before | `git log --oneline` | |
| Update my copy with the latest | `git switch main && git pull` | |

### 11.3 What is never committed

`.godot/` (Godot's cache), `*.import` files and exported builds are ignored (`.gitignore`). On a fresh clone Godot rebuilds the cache, and `run_all_tests.sh` and the launcher scripts run the import for you.

### 11.4 Commit habits that help future you

- One idea per commit. "Make rope longer" and "Add new level" are two commits.
- Commit when the tests pass. Then every commit is a place you can safely go back to.
- Write the message as "what it does": "Add Mirror Maze level", not "stuff".

---

## 12. When something breaks

### 12.1 Where Godot shows you the problem

| Where | What it shows |
|---|---|
| **Output** panel (bottom of the editor) | `print()` text and warnings |
| **Debugger > Errors** tab | Red errors with the file and line (click to jump) |
| **Debugger > Remote** (while the game runs) | The live node tree, like DevTools' Elements tab |
| The terminal, if you ran `godot --path .` | The same messages |

Add your own message anywhere:

```gdscript
print("speed is ", GameState.MOVE_SPEED)
```

### 12.2 Error decoder

| Message (shortened) | Meaning | Fix |
|---|---|---|
| `Parse Error: ... Unexpected "Indent"` / `Mixed use of tabs and spaces` | The indentation is inconsistent | The project uses **tabs**. Let your editor insert tabs in `.gd` files |
| `Identifier "xyz" not declared` | A typo, or the variable is declared somewhere else | Check spelling and where it is declared |
| `Invalid access to property or key ... on a base object of type 'null instance'` | You used something that does not exist (yet): a wrong node path, or a node not created at that moment | Print it before using it; check the `$Path` |
| `Invalid call. Nonexistent function 'foo'` | The function name is wrong or lives on a different object | Search for the real name |
| `Could not host: port 7777 is busy` | Another game is already hosting on this machine | Close it |
| Changes to a PNG do not show | The art was not re-imported | Focus the Godot editor window, or run `godot --headless --path . --import` |
| The whole game is a black screen | The darkness is working; or the level theme is too dark | Walk; check `ambient_color` in `level_data.gd` |
| A test run never finishes | A script has a parse error and its scene idles | The runner times out after 300 s; run the suite's command by hand and read the error |

### 12.3 Debugging method (the same one every programmer uses)

1. **Reproduce it** with a fixed seed so it happens every time.
2. **Shrink it**: what is the smallest change that causes it? `git stash` your other edits to find out.
3. **Look at the first error**, not the last. Later errors are usually consequences.
4. **Print** values near the problem; check your assumptions one by one.
5. **Ask the tests.** If a test already covers it, run only that one (part 10.2).
6. **Undo and redo in small steps** if you cannot find it: `git restore`, then re-apply changes one at a time.

---

## 13. A four-week learning roadmap

About an hour a day is plenty. The weeks build on each other; do not skip ahead.

| Week | Goal | Do | You can now |
|---|---|---|---|
| 1. Play and poke | Feel comfortable | Part 1; play every offline setting; do the five changes in part 5; read the top comments of `game_state.gd`, `score_table.gd`, `level_data.gd` | Change any number in the game and predict the effect |
| 2. Content | Make it yours | Part 7 (a new level); part 8 (re-colour a character, change tiles); change the menu wording and the commentary notes | Add levels and art without touching logic |
| 3. Read the code | Understand how it works | Read in this order: `pod_graph.gd` (short), `score_table.gd`, `maze_generator.gd`, `tether_system.gd`, then `game_controller.gd`. Open `docs/WALKTHROUGH.md` side by side | Explain how a snapped rope becomes two pods |
| 4. Build a feature | Write your own code | Pick one from the ladder below (start with the HUD timer) and finish it with a test | Add a rule and test it |

While you learn GDScript and Godot, these are good, free, official starting points: the Godot documentation at **docs.godotengine.org** (read "Getting started", especially *Your first 2D game*, and the *GDScript reference*). Keep it open in a tab while you work.

### Practice ladder

Each rung is a complete small project. Do them in order.

| # | Task | Where | Skills |
|---|---|---|---|
| 1 | Change the menu title and a button label (keep the button's first word) | `scenes/main_menu.tscn` | Scenes, the Inspector |
| 2 | Make the player faster, then slower; find a value you like | `game_state.gd` | Constants, play-testing |
| 3 | Make the fog easier (part 5.3), then find the radius you like | `game_state.gd` | Tuning |
| 4 | Re-colour the Warden's tunic | `tools/make_sprites.py` | Running a script, the import step |
| 5 | Add a new level with its own colours | `level_data.gd` | Data tables |
| 6 | Add three new commentary notes | `commentary_data.gd` | Data, writing |
| 7 | Show a match timer in the top-left text (part 5.6) | `game_controller.gd` | Variables, `delta`, string formatting |
| 8 | Play a sound when a rope snaps (part 8.6) | `game_controller.gd`, `assets/audio/` | Nodes created from code, assets |
| 9 | Change the rope colours | `_tension_color` | Reading a function |
| 10 | Add a fifth character | `make_sprites.py`, `player_sprites.gd` | Two files that must agree |
| 11 | Change scoring and update the tests that cover it | `score_table.gd`, `tests/test_pod_graph.gd` | Tests as a safety net |
| 12 | Show the rope's tension percent next to the pod size in the HUD | `game_controller.gd` | Reading host/client data paths |
| 13 | Make the console need the right symbol order (not just "all read") | `game_controller.gd`, `net_router.gd` | A real rule change, networking |
| 14 | Add a "ping" message that shows a marker for your pod | `net_router.gd`, `game_controller.gd` | RPCs; the host/client split |
| 15 | Wire in online room codes | `docs/WALKTHROUGH.md` section 11 | The big one; do it last |

---

## 14. Glossary and cheat sheet

### Glossary

| Word | Meaning |
|---|---|
| Pod | A group of players still connected by unbroken ropes. A snap can split a team into several pods |
| Team | The group you formed in the lobby. Its size at the start decides your score |
| Link / rope / tether | The connection between two neighbours in a pod |
| Tension | Rope length divided by the snap distance (0 to 100 %) |
| Fog room | The dark starting room in the middle |
| Fragment / tablet | A clue holding one symbol of the exit code |
| Console | Where a pod "types" the code (by walking in once the pod has read everything) |
| Host | The device that runs the rules |
| Snapshot | The host's 20-times-a-second summary of positions and ropes |
| RPC | "Remote procedure call": a function that runs on another device (`@rpc` in `net_router.gd`) |
| Seed | A number that decides the "random" maze |
| Autoload | A script Godot keeps loaded for the whole run |
| Signal | An event a node announces; other code connects to it |
| Import | Godot converting your PNG/WAV into its internal format |
| Export | Building a phone or PC app |
| Headless | Running Godot without a window (how the tests run) |

### Cheat sheet

| I want to change... | File | Look for |
|---|---|---|
| Player speed | `autoload/game_state.gd` | `MOVE_SPEED` |
| How far you see | `autoload/game_state.gd` | `VISION_NORMAL`, `VISION_FOG` |
| Rope feel | `autoload/game_state.gd` | `TETHER_L0`, `TETHER_DMAX`, `TETHER_K`, `TETHER_C`, `TETHER_PULL_CAP`, `TETHER_SNAG_BUFFER` |
| Rope colour thresholds | `scripts/tether_system.gd` | `EDGES` |
| Rope colours | `scripts/game_controller.gd` | `_tension_color` |
| Minimum team | `autoload/game_state.gd` | `MIN_TEAM_SIZE` |
| Points | `autoload/score_table.gd` | `TIERS` |
| A level | `autoload/level_data.gd` | the `levels` array |
| Number of tablets | `autoload/level_data.gd` | the number right after the width and height in each `LevelDef.new(...)` |
| Code symbols | `scripts/game_controller.gd` | `var symbols := [...]` |
| Commentary notes | `autoload/commentary_data.gd` | `Note.new(...)` |
| Bots | `scripts/bot_brain.gd` | `SKILLS` |
| Offline limits | `scripts/offline_setup.gd` | `MAX_RIVAL_PODS`, `MIN_RIVAL_SIZE`, `MAX_RIVAL_SIZE` |
| Menu words | `scenes/main_menu.tscn` | `text = ...` |
| Top-left text | `scripts/game_controller.gd` | `hud_text` |
| Characters | `tools/make_sprites.py`, `scripts/player_sprites.gd` | `CHARACTERS`, `SHEETS` |
| Team colours | `scripts/player_sprites.gd` | `TEAM_COLORS` |
| UI font size | `scripts/compact_theme.gd` | `make(font_size)` |
| Window size | `project.godot` | `window_width_override` |
| Network ports | `autoload/net_local.gd` | `DEFAULT_GAME_PORT`, `DEFAULT_DISCOVERY_PORT` |
| Max players | `autoload/game_state.gd` | `MAX_PLAYERS` |

### If you break everything

```bash
git status                  # see what you changed
git stash -u                # put ALL your edits aside (including new files)
./tests/run_all_tests.sh    # confirm the original works
git stash pop               # bring your edits back when you are ready
```

Or throw it all away: `git switch main`, then `git branch -D my-experiment`. Your computer, and the game, are fine.
