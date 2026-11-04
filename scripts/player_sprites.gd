class_name PlayerSprites
extends RefCounted
## PlayerSprites
## Builds SpriteFrames for a character from its sprite sheet, and owns
## the character / team-colour tables. This is the ONE place that knows
## the sheet layout -- to change art, repaint the PNGs (same layout) and
## nothing in code needs to move; to add an animation or a character,
## edit ANIMS / SHEETS below. See docs/ART_WALKTHROUGH.md.
##
## The row layout mirrors tools/make_sprites.py (keep them in sync).

const FRAME := 16
const SHEET_DIR := "res://assets/sprites/characters/"
const SHEETS := [
	"char_0_wanderer.png",
	"char_1_tinker.png",
	"char_2_sprout.png",
	"char_3_warden.png",
]

# animation name -> [row, frame count, fps, loops]
const ANIMS := {
	"idle_down": [0, 2, 2.0, true],
	"walk_down": [1, 4, 8.0, true],
	"idle_up": [2, 2, 2.0, true],
	"walk_up": [3, 4, 8.0, true],
	"idle_side": [4, 2, 2.0, true],
	"walk_side": [5, 4, 8.0, true],
	"pulled": [6, 2, 6.0, true],
	"eliminated": [7, 3, 3.0, false],
}

## Up to 16 players can each be on their own team, so this needs 16
## distinguishable colours. Index with team_id % TEAM_COLORS.size().
const TEAM_COLORS := [
	Color(0.90, 0.35, 0.25), Color(0.25, 0.60, 0.95), Color(0.35, 0.80, 0.40), Color(0.95, 0.80, 0.25),
	Color(0.70, 0.40, 0.90), Color(0.25, 0.85, 0.85), Color(0.95, 0.55, 0.20), Color(0.90, 0.45, 0.70),
	Color(0.60, 0.75, 0.25), Color(0.55, 0.55, 0.95), Color(0.80, 0.25, 0.45), Color(0.20, 0.55, 0.45),
	Color(0.85, 0.70, 0.55), Color(0.50, 0.50, 0.55), Color(0.95, 0.95, 0.95), Color(0.45, 0.30, 0.20),
]

static var _frames_cache: Dictionary = {}  # character index -> SpriteFrames


static func character_count() -> int:
	return SHEETS.size()


## Deterministic from the peer id, so every client agrees on who looks
## like what without any extra networking.
static func character_for_peer(peer_id: int) -> int:
	return absi(peer_id) % SHEETS.size()


static func team_color(team_id: int) -> Color:
	return TEAM_COLORS[absi(team_id) % TEAM_COLORS.size()]


static func sheet_path(character: int) -> String:
	return SHEET_DIR + SHEETS[character % SHEETS.size()]


## False when the PNG hasn't been imported yet (fresh clone that has
## never been opened in the editor or run with --import). Callers fall
## back to the flat-colour placeholder instead of crashing.
static func has_art(character: int) -> bool:
	return ResourceLoader.exists(sheet_path(character))


static func build_frames(character: int) -> SpriteFrames:
	if _frames_cache.has(character):
		return _frames_cache[character]
	var tex: Texture2D = load(sheet_path(character))
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim_name in ANIMS:
		var spec: Array = ANIMS[anim_name]
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, spec[2])
		sf.set_animation_loop(anim_name, spec[3])
		for f in range(spec[1]):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(f * FRAME, spec[0] * FRAME, FRAME, FRAME)
			sf.add_frame(anim_name, atlas)
	_frames_cache[character] = sf
	return sf
