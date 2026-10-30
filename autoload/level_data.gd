extends Node
## LevelData
## Table of selectable levels. A "level" in Fogbound is just a named
## bundle of MazeGenerator parameters (size, fragment count) plus a
## difficulty label for the lobby UI -- the maze itself is still
## freshly seeded per match (design doc section 3: "all numbers in
## this document are starting values for playtesting"), so a level
## is a size/difficulty class, not a fixed hand-authored layout.
##
## Kept as a flat array indexed by id (not a Dictionary) so level
## order in the lobby's OptionButton is stable and so `net_start_match`
## can send a level_id as a single int instead of re-serializing the
## whole level definition over the wire -- every client has this same
## table loaded locally and just looks the id up.

class LevelDef:
	var id: int
	var name: String
	var difficulty: String  # shown in the lobby picker
	var width: int
	var height: int
	var fragment_count: int
	var description: String
	var secret: bool = false          # hidden from the picker until SaveData.is_unlocked(id)
	var unlock_hint: String = ""      # shown in place of the description while still locked

	# Visual theme. Purely cosmetic, applied identically on every
	# client (see game_controller.gd _paint_tilemap / _build_maze), so
	# nothing here needs syncing over the network beyond the level id.
	# ambient_color is what CanvasModulate multiplies everything by --
	# keep it near-black or the fog loses its menace.
	var floor_color: Color = Color(0.24, 0.22, 0.19)
	var wall_color: Color = Color(0.35, 0.38, 0.44)
	var ambient_color: Color = Color(0.03, 0.03, 0.05)

	# Seeded puzzle rooms joined by a tunnel chain (see MazeGenerator).
	# Room i holds fragment i, so this is also how many fragments are
	# "earned" by finding a room rather than a random dead end.
	var puzzle_rooms: int = 0
	var puzzle_room_size: int = 3

	func _init(p_id: int, p_name: String, p_difficulty: String, p_w: int, p_h: int, p_frags: int, p_desc: String,
			p_secret: bool = false, p_unlock_hint: String = "") -> void:
		id = p_id
		name = p_name
		difficulty = p_difficulty
		width = p_w
		height = p_h
		fragment_count = p_frags
		description = p_desc
		secret = p_secret
		unlock_hint = p_unlock_hint

	## Fluent setters so each table entry below can stay one expression.
	func with_puzzles(p_rooms: int, p_size: int) -> LevelDef:
		puzzle_rooms = p_rooms
		puzzle_room_size = p_size
		return self

	func with_theme(p_floor: Color, p_wall: Color, p_ambient: Color) -> LevelDef:
		floor_color = p_floor
		wall_color = p_wall
		ambient_color = p_ambient
		return self


## Levels get larger and denser with more fragments to track as
## difficulty rises, which also means a longer, riskier walk back to
## the console for a pod trying to keep every link intact. Each level
## also gets a few seeded puzzle rooms (with_puzzles) joined to the fog
## room by a tunnel chain; their positions come from the match seed.
var levels: Array = [
	LevelDef.new(0, "The Antechamber", "Easy", 19, 19, 5,
		"A small maze for learning the ropes -- short walks back to the console, few fragments to lose track of.") \
		.with_theme(Color(0.30, 0.26, 0.21), Color(0.42, 0.36, 0.30), Color(0.05, 0.04, 0.04)) \
		.with_puzzles(2, 3),
	LevelDef.new(1, "Hollow Row", "Easy", 23, 23, 6,
		"A bit more room to get turned around in, still forgiving if your pod splits.") \
		.with_theme(Color(0.18, 0.24, 0.18), Color(0.28, 0.38, 0.26), Color(0.03, 0.05, 0.04)) \
		.with_puzzles(3, 3),
	LevelDef.new(2, "The Understreets", "Medium", 31, 31, 8,
		"The original proving ground -- enough corridors that a snapped link really costs you.") \
		.with_theme(Color(0.24, 0.22, 0.19), Color(0.35, 0.38, 0.44), Color(0.03, 0.03, 0.05)) \
		.with_puzzles(4, 3),
	LevelDef.new(3, "Deep Lattice", "Medium", 37, 37, 10,
		"A wider lattice of loops and dead ends. Expect to split up to cover it.") \
		.with_theme(Color(0.17, 0.17, 0.28), Color(0.30, 0.30, 0.48), Color(0.03, 0.03, 0.07)) \
		.with_puzzles(5, 3),
	LevelDef.new(4, "The Long Fog", "Hard", 45, 45, 12,
		"A sprawling maze with a lot of fragments to coordinate. Losing your pod here hurts.") \
		.with_theme(Color(0.22, 0.27, 0.28), Color(0.36, 0.44, 0.46), Color(0.06, 0.08, 0.09)) \
		.with_puzzles(6, 3),
	LevelDef.new(5, "The Labyrinth Proper", "Hard", 51, 51, 14,
		"The biggest map. A full 16-player team will want to split on purpose -- just don't let it happen by accident.") \
		.with_theme(Color(0.26, 0.17, 0.15), Color(0.45, 0.26, 0.22), Color(0.05, 0.02, 0.02)) \
		.with_puzzles(7, 5),

	# Secret level. Not shown in the lobby picker (lobby.gd filters on
	# .secret) until SaveData.is_unlocked(SECRET_LEVEL_ID) -- see
	# net_router.gd's _check_secret_level_unlock() for the unlock
	# condition itself (escape The Labyrinth Proper with every member
	# of a full-size team, i.e. a 1200-point finish on level id 5).
	# Its theme is inverted on purpose: pale floors, dark walls, where
	# every other level is dark floors and lighter walls.
	LevelDef.new(99, "???", "???", 41, 41, 16,
		"A maze built entirely out of dead ends that aren't. Every fragment here was left by someone who already got out.",
		true, "Escape The Labyrinth Proper with your whole team still holding hands.") \
		.with_theme(Color(0.52, 0.52, 0.56), Color(0.20, 0.20, 0.26), Color(0.10, 0.10, 0.14)) \
		.with_puzzles(8, 3),
]

const SECRET_LEVEL_ID := 99
const SECRET_LEVEL_UNLOCK_SOURCE_ID := 5  # "The Labyrinth Proper"


func get_level(id: int) -> LevelDef:
	for lvl in levels:
		if lvl.id == id:
			return lvl
	return levels[0]


## Mirrors GameState.DEFAULT_LEVEL_ID. Duplicated rather than shared
## because GameState must stay referenceable from contexts where no
## [autoload] singleton exists yet (some headless test runs -- see
## that constant's own comment); a cross-check in
## tests/boot_game_smoketest.gd keeps the two from drifting apart.
func default_level_id() -> int:
	return 2  # "The Understreets"


## Levels a local player can currently pick from in the lobby: every
## non-secret level, plus the secret level once SaveData says it's
## unlocked. SaveData is a per-device local file (see
## autoload/save_data.gd) -- this intentionally does NOT go through
## networking, so only the host's own unlock state decides whether
## the secret level is offered as a choice for a given match.
func selectable_levels() -> Array:
	var out: Array = []
	for lvl in levels:
		if not lvl.secret or SaveData.is_unlocked(lvl.id):
			out.append(lvl)
	return out
