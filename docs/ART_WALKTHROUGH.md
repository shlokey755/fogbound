# Fogbound: Art Implementation Walkthrough

How to replace Fogbound's placeholder art with your own so that the change shows up in the game. Every section ends with a **See it change** step, so you can check each swap before moving on.

Rule of thumb: **repaint the files, keep the layout, and code rarely needs to move.** Each art slot below says which file to replace, what layout the code expects, and the one or two lines to edit if you want a different layout.

---

## 0. The art slots

| Slot | Today | Where it lives | Code you may need to touch |
|---|---|---|---|
| Characters (4 looks, 8 animations each) | Generated pixel art, PNG sheets | `assets/sprites/characters/*.png` | None if you keep the sheet layout |
| Team colour | Palette-swap shader on the scarf | `shaders/team_palette.gdshader` | None if you keep the magenta markers |
| Floor, wall, puzzle-room floor | Flat colours built in code | `scripts/maze_tileset_builder.gd` | Replace the builder (section 3) |
| Clue tablet | Blue `ColorRect` (empty `Sprite2D` waiting) | `scenes/clue.tscn` | Set a texture (section 4) |
| Console, exit gate | `ColorRect`s | `scenes/game.tscn` | Swap node (section 4) |
| Commentary pickup | Yellow `ColorRect` | `scenes/commentary_node.tscn` | Swap node (section 4) |
| Game icon | Generated pixel art | `icon.svg`, `assets/icon/*.png` | None (section 5) |
| Touch joystick | `ColorRect`s | `scenes/touch_joystick.tscn` | Swap nodes |
| Audio, fonts | Nothing yet | `assets/audio/`, `assets/fonts/` | New code (section 6) |

Per-level colours (floor, wall, ambient darkness) come from `autoload/level_data.gd`, not from art files. They keep working when you add real tiles (section 3 shows how to keep them).

---

## 1. Pixel-art settings (already configured)

Fogbound is 16×16 pixel art on a 320×180 viewport. `project.godot` already sets what pixel art needs, so there is nothing to change unless you alter the resolution:

- `rendering/textures/canvas_textures/default_texture_filter = 0` (Nearest, so pixels stay crisp)
- `display/window/stretch/mode = "viewport"` with `aspect = "keep"` (the 320×180 image is scaled up as a whole, so pixels stay square)

At that size a 16×16 tile is 1/20th of the screen width, so keep detail bold and low-count.

New PNGs must be imported before the game can load them. The editor does this automatically when it has focus. Headless or in CI, run:

```bash
godot --headless --path . --import
```

`.import` files and the `.godot/` folder are git-ignored, so a fresh clone always needs this step once. `tests/run_all_tests.sh` already does it.

---

## 2. Replacing the character sprites

### The layout the code expects

Each character is one PNG, **96×128 px**: 6 columns × 8 rows of 16×16 frames.

| Row | Animation | Frames | Notes |
|---|---|---|---|
| 0 | `idle_down` | 2 | |
| 1 | `walk_down` | 4 | |
| 2 | `idle_up` | 2 | |
| 3 | `walk_up` | 4 | |
| 4 | `idle_side` | 2 | Face **right**; facing left is flipped at runtime |
| 5 | `walk_side` | 4 | Face right |
| 6 | `pulled` | 2 | Shown when the tether yanks the player |
| 7 | `eliminated` | 3 | Plays once, holds the last frame |

Unused cells in a row (for example columns 2–5 of an `idle` row) stay transparent. The table lives in code as `PlayerSprites.ANIMS` in `scripts/player_sprites.gd`, and it is the single source of truth.

### The team-colour markers

The scarf is drawn in two flat marker colours, and `shaders/team_palette.gdshader` swaps them for the player's team colour at runtime:

| Marker | Becomes |
|---|---|
| `#FF00FF` (pure magenta) | Team colour |
| `#B400B4` (dark magenta) | Team colour × 0.7 (the shadow side) |

Paint whatever you want recoloured in those two colours, and keep them out of every other part of the sprite. The shader matches within a small tolerance, so **do not anti-alias or blur marker pixels**. A soft edge will leave pink fringes.

### Swap in your own art

1. Draw a 96×128 sheet to the layout above. Aseprite, LibreSprite and Piskel all work. Export as PNG with transparency.
2. Save it over an existing file, for example `assets/sprites/characters/char_0_wanderer.png`. Keep the file name and nothing else needs to change.
3. Run `godot --headless --path . --import` (or just focus the editor).

**See it change:** run the game. Character *N* is used by every peer id where `peer_id % 4 == N`. The host is peer id 1, so replace `char_1_tinker.png` (character 1) to see yourself change first.

### Adding a fifth character

1. Add the PNG to `assets/sprites/characters/`.
2. Add its file name to `PlayerSprites.SHEETS` in `scripts/player_sprites.gd`.
3. Re-import. Characters are picked by `peer_id % SHEETS.size()`, so the new look appears automatically.
4. Update the count in `tests/boot_game_smoketest.gd` only if you assert it. The test loops over `character_count()` and will check your new sheet for the right size and the magenta marker.

### Adding or changing an animation

Edit `PlayerSprites.ANIMS` (name → `[row, frame count, fps, loops]`), add the row to every sheet, and update the sheet-height check in the smoketest (it multiplies `FRAME` by the number of animations). Choosing *when* to play an animation is in `Player._update_animation()` in `scripts/player.gd`.

One current limitation: `pulled` triggers from the tether's pull velocity, which only the host (and offline play) knows. Clients see walk/idle in that moment. Syncing a "pulled" flag in the host's snapshot is the fix if you want it on clients too.

### Regenerating the built-in art instead

The shipped sheets come from `tools/make_sprites.py`, which draws them procedurally. If you would rather tweak colours or outfits than paint by hand:

```bash
pip install pillow
python3 tools/make_sprites.py --preview   # also writes a scaled contact sheet
python3 tools/make_icon.py                # icon reuses the same character frames
```

---

## 3. Replacing floor and wall tiles

Today, `MazeTileSetBuilder.build()` makes a `TileSet` in code from three flat colours:

| Atlas coord | Tile | Collision |
|---|---|---|
| `(0, 0)` | Floor | None |
| `(1, 0)` | Wall | Full tile + light occluder |
| `(2, 0)` | Puzzle-room floor | None (just a lighter tint) |

`game_controller._paint_tilemap()` picks the coordinate for each grid cell, and only builds the placeholder `TileSet` if `Maze.tile_set` is still empty.

### Option A: keep the code-built TileSet, swap the pixels (quickest)

Replace the three `fill_rect` calls in `MazeTileSetBuilder._make_atlas_texture()` with a load of your own 48×16 strip (floor | wall | puzzle floor):

```gdscript
static func _make_atlas_texture(_floor: Color, _wall: Color) -> Texture2D:
    return load("res://assets/tilesets/maze_tiles.png")
```

The collision and occlusion are already wired in `build()`, so walls still block movement and cast shadows. The per-level floor/wall colours stop applying in this option, because the texture is fixed; the level's ambient darkness (`CanvasModulate`) still does.

### Option B: author a TileSet in the editor (best for auto-tiling walls)

1. Create `assets/tilesets/maze.tres` as a `TileSet`: tile size 16×16, add one **Physics Layer** (layer 0, collision layer 1, mask 1) and one **Occlusion Layer**.
2. Add your atlas PNG as a source. Create three tiles at atlas coords `(0,0)` floor, `(1,0)` wall, `(2,0)` puzzle floor, with the same meaning as the table above. **Keep those coordinates.** `_paint_tilemap()` and the smoketest depend on them.
3. On the wall tile, draw a full-tile collision polygon and a full-tile occluder polygon.
4. Assign the `TileSet` to the `Maze` node in `scenes/game.tscn`. The `if maze_layer.tile_set == null` check then skips the placeholder builder automatically.

If you want terrain auto-tiling (wall corners that join), add more wall tiles to the atlas and replace the `Vector2i(1, 0)` choice in `_paint_tilemap()` with a Terrain-aware call such as `set_cells_terrain_connect()`. The maze grid is available as `maze.grid[y][x]`.

**See it change:** open `scenes/game.tscn`, press **F6**. The floor and walls change immediately. The lighter puzzle-room tiles mark the seeded rooms (next section).

### Puzzle rooms and tunnels: what the art should show

`MazeGenerator` places seeded puzzle rooms and carves a tunnel chain from the fog room through each room in order. These are exposed for art and UI:

| Field / method | Use |
|---|---|
| `maze.puzzle_rooms` | `Array[Rect2i]` in chain order; draw room decals, doors, rugs |
| `maze.tunnel_paths` | `Array[Array[Vector2i]]`; tunnel *i* links room *i−1* (or the fog room) to room *i*; draw lanterns, chalk marks, floor arrows |
| `maze.is_puzzle_room_cell(x, y)` | Pick a different tile for room floor |

Because everything comes from the match seed, every client computes the same layout, so decor that is placed from these fields needs no networking.

---

## 4. Replacing clue, console, exit and commentary visuals

These are simple placeholder rectangles. Swap each for a sprite:

**Clue tablet** (`scenes/clue.tscn`) already has an empty `Sprite2D` waiting. Assign a texture to it in the Inspector and delete the `ColorRect` sibling. `Clue.show_symbol()` writes the revealed symbol into the `Label`, which keeps working.

**Console and exit gate** (`scenes/game.tscn`): add a `Sprite2D` under `Console` / `ExitGate`, set its texture, and delete `ConsoleVisual` / `ExitVisual`. The gate is dimmed with `modulate` while locked and reset to white when unlocked (`game_controller.gd`, near the line commented "cosmetic: 'unlocked' state"). A dimmed sprite already reads as "locked". If you want a distinct open frame, swap the texture on that line instead of changing `modulate`.

**Commentary pickup** (`scenes/commentary_node.tscn`): same swap, replace `ColorRect` with a `Sprite2D`.

For animated props, use `AnimatedSprite2D` with a `SpriteFrames` resource. Keep the sprite centred on the node origin, since the collision shape is centred there.

**See it change:** run the game; the console is in the middle of the fog room, the exit is at the outer edge, and clue tablets sit in the puzzle rooms first.

---

## 5. The game icon

The icon is generated by `tools/make_icon.py` from the same character frames as the in-game art, and writes three files:

- `icon.svg`: the project icon (`config/icon` in `project.godot`)
- `assets/icon/fogbound_icon_512.png`: store / README size
- `assets/icon/fogbound_icon_192.png`: Android launcher size

To use your own artwork, replace those three files and keep the names. For an Android export, also set **Project → Export → Android → Icons** (main 192×192, plus the adaptive foreground/background if you want them).

---

## 6. Audio and fonts (not wired yet)

Nothing plays sound yet, and the default Godot font is used. When you add them:

- **Audio:** put files under `assets/audio/` (OGG for music/ambience, WAV for short effects). The cleanest hooks are the tether tension states (`tether_system.gd` already computes green/yellow/red/critical), the snap event, clue pickup, and exit unlock.
- **Fonts:** put a `.ttf`/`.otf` under `assets/fonts/`, create a `Theme` resource that sets it as the default font, and assign it in **Project Settings → GUI → Theme → Custom**. For pixel art, disable font anti-aliasing and hinting in the font's import settings.

---

## 7. A checklist before you commit art

- [ ] Character sheets are 96×128 and the scarf is the only magenta
- [ ] Tile atlas keeps floor `(0,0)`, wall `(1,0)`, puzzle floor `(2,0)`
- [ ] `godot --headless --path . --import` runs without errors
- [ ] `GODOT=/path/to/godot ./tests/run_all_tests.sh` still passes (it checks character sheet sizes, the magenta marker, animation frame counts, and that the placeholder `MazeTileSetBuilder` still has its three tiles and wall collision; it does not inspect a hand-made `TileSet`, so check that one by eye)
- [ ] Art looks crisp (Nearest filtering) at the zoom you ship at
- [ ] You own the rights to every asset you commit. Only the generated art in this repo is original to the project

---

## 8. Suggested order

1. Characters first, since every player sees them all the time, and the pipeline is finished.
2. Tiles next, because they cover most of the screen.
3. Clue, console and exit sprites.
4. Icon and store images.
5. Audio, which has the biggest effect on the tension feel.
