extends Node
## GameState
## Central, host-authoritative game state: match seed, teams, pods,
## clue notebooks and score. Non-host clients read replicated copies
## of these same fields (see net_router.gd for sync points) but only
## the host (multiplayer.is_server()) ever mutates them directly.

# ---------------------------------------------------------------------------
# Tunable constants (see docs/WALKTHROUGH.md and the design doc, section 3.1)
# ---------------------------------------------------------------------------
const TILE_SIZE := 16.0
const MOVE_SPEED := 64.0            # px/s, ~4 m/s
const VISION_NORMAL := 80.0         # px, 5 m
const VISION_FOG := 24.0            # px, 1.5 m
const LANTERN_BONUS := 24.0         # px, +1.5 m for the carrier
const LANTERN_LINK_BONUS := 12.0    # px, +0.75 m for a linked neighbour

const TETHER_L0 := 48.0             # px, rest length (3 m)
const TETHER_DMAX := 96.0           # px, snap distance (6 m)
const TETHER_K := 10.0              # spring stiffness
const TETHER_C := 6.3                # damping, ~critical damping
const TETHER_SNAG_BUFFER := 1.5     # seconds of grace while rope is wrapped on a corner
const TETHER_PULL_FRICTION := 10.0
const TETHER_PULL_CAP := [0.0, 0.25, 0.8, 0.8]  # GREEN, YELLOW, RED, CRITICAL as fraction of MOVE_SPEED

const MIN_TEAM_SIZE := 2
const MAX_PLAYERS := 16

# ---------------------------------------------------------------------------
# Match state (host sets these; clients receive them via RPC)
# ---------------------------------------------------------------------------
## Mirrors LevelData.default_level_id() (id 2, "The Understreets") as
## a plain constant rather than a call into the LevelData singleton.
## reset_match() runs in some headless test contexts (`godot --headless
## --script ...`) where [autoload] singletons are never instantiated
## at all -- see docs/WALKTHROUGH.md "Testing" -- so a call out to
## another autoload's method here would fail to even compile in that
## context. Kept in sync with LevelData's own default by a test
## assertion (tests/test_maze_generator.gd) rather than by sharing code.
const DEFAULT_LEVEL_ID := 2

var match_seed: int = 0
var level_id: int = DEFAULT_LEVEL_ID
var maze_w: int = 31    # derived from the chosen level; kept as a field for anything reading it directly
var maze_h: int = 31

# teams[team_id] = { "name": String, "original_size": int, "member_order": [peer_id, ...] }
var teams: Dictionary = {}

# pods: Array of Array[int] (peer_ids), recomputed by PodGraph after every snap/disconnect
var pods: Array = []

# player_team[peer_id] = team_id
var player_team: Dictionary = {}

# notebook[peer_id] = { fragment_id: true } -- fragments *this player* has personally read
var notebook: Dictionary = {}

# fragment answer sequence, revealed progressively as fragments are read
var exit_sequence: Array = []

var match_started: bool = false
var match_over: bool = false

# final_scores: Array of { "pod": [peer_ids], "team_id": int, "points": int }
var final_scores: Array = []


func reset_match() -> void:
	match_seed = 0
	level_id = DEFAULT_LEVEL_ID
	teams.clear()
	pods.clear()
	player_team.clear()
	notebook.clear()
	exit_sequence.clear()
	match_started = false
	match_over = false
	final_scores.clear()


func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()
