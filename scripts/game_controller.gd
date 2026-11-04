extends Node2D
## GameController
## Wires together MazeGenerator, TetherSystem, PodGraph, ClueSpawner
## and the Player nodes for a single match. Host-only logic is guarded
## with GameState.is_host(); clients render replicated state instead.
##
## This is the "MVP" slice from docs/WALKTHROUGH.md phases 1-5: seeded
## maze + fog, chain tether with tension/snap, pod splitting + the
## 2-member elimination rule, one clue type, one exit, tiered scoring.

const PlayerScene := preload("res://scenes/player.tscn")

@onready var maze_layer: TileMapLayer = $Maze
@onready var clues_node: Node2D = $Clues
@onready var exit_gate: Area2D = $ExitGate
@onready var console_area: Area2D = $Console
@onready var players_node: Node2D = $Players
@onready var tether_lines: Node2D = $TetherLines
@onready var fog_controller: Node2D = $FogLayer

var maze: MazeGenerator
var pod_graph: PodGraph
var tether_system: TetherSystem
var clue_spawner: ClueSpawner
var commentary_spawner: CommentarySpawner
var player_nodes: Dictionary = {}  # peer_id -> Player
var link_lines: Dictionary = {}    # "a_id:b_id" -> Line2D

const COMMENTARY_NODES_PER_MATCH := 3  # how many dev-commentary notes appear per maze, out of the full pool

var _snapshot_accum := 0.0
const SNAPSHOT_INTERVAL := 1.0 / 20.0

var _console_entered_pods: Dictionary = {}  # pod key -> true, once unlocked
var _scored_pods: Dictionary = {}           # pod key -> true, to avoid double scoring
var _commentary_popup_token: int = 0        # guards against two notes' auto-hide timers racing each other


func _ready() -> void:
	NetRouter.register_game_node(self)
	NetRouter.link_snapped_visual.connect(_on_link_snapped_visual)
	NetRouter.fragment_revealed.connect(_on_fragment_revealed)
	NetRouter.match_finished.connect(_on_match_finished)

	_build_maze()

	if GameState.is_host() or not multiplayer.has_multiplayer_peer():
		_host_spawn_players()
		_host_setup_tether_and_pods()
		exit_gate.body_entered.connect(_on_exit_body_entered)
		console_area.body_entered.connect(_on_console_body_entered)


func _physics_process(delta: float) -> void:
	_update_tether_lines()

	if GameState.is_host() or not multiplayer.has_multiplayer_peer():
		_snapshot_accum += delta
		if _snapshot_accum >= SNAPSHOT_INTERVAL:
			_snapshot_accum = 0.0
			_broadcast_snapshot()


# ---------------------------------------------------------------------------
# Maze / fog / clues (shared, since every client rebuilds the identical
# seeded maze locally rather than receiving tile data over the wire)
# ---------------------------------------------------------------------------

func _build_maze() -> void:
	var level: LevelData.LevelDef = LevelData.get_level(GameState.level_id)
	var commentary_count: int = mini(COMMENTARY_NODES_PER_MATCH, CommentaryData.total_count())
	maze = MazeGenerator.new()
	maze.generate(GameState.match_seed, level.width, level.height, level.fragment_count, commentary_count,
			level.puzzle_rooms, level.puzzle_room_size)

	_paint_tilemap()
	fog_controller.get_node("CanvasModulate").color = level.ambient_color

	var fog_room_area: Area2D = fog_controller.get_node("FogRoomArea")
	var room_shape: CollisionShape2D = fog_room_area.get_node("CollisionShape2D")
	var rect := RectangleShape2D.new()
	rect.size = Vector2(maze.fog_room_rect.size) * GameState.TILE_SIZE
	room_shape.shape = rect
	fog_room_area.position = (
		Vector2(maze.fog_room_rect.position) * GameState.TILE_SIZE
		+ Vector2(maze.fog_room_rect.size) * GameState.TILE_SIZE * 0.5
	)
	fog_controller.setup()

	exit_gate.position = (Vector2(maze.exit_cell) + Vector2(0.5, 0.5)) * GameState.TILE_SIZE
	console_area.position = (Vector2(maze.console_cell) + Vector2(0.5, 0.5)) * GameState.TILE_SIZE

	# Build the shared exit sequence deterministically from the seed so
	# every client agrees on it even though only the host enforces it.
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.match_seed + 1
	var symbols := ["#", "%", "@", "&", "*", "+", "=", "?"]
	GameState.exit_sequence.clear()
	for i in range(maze.fragment_cells.size()):
		GameState.exit_sequence.append(symbols[rng.randi() % symbols.size()])

	clue_spawner = ClueSpawner.new()
	add_child(clue_spawner)
	clue_spawner.spawn_fragments(maze)

	commentary_spawner = CommentarySpawner.new()
	add_child(commentary_spawner)
	commentary_spawner.note_activated.connect(_on_commentary_activated)
	commentary_spawner.spawn(maze, GameState.match_seed)


func _paint_tilemap() -> void:
	# Atlas coord (0,0) = floor, (1,0) = wall, (2,0) = puzzle-room floor
	# (same collision as floor, just a different tint). The TileSet itself is
	# built procedurally by MazeTileSetBuilder so the project runs
	# without any editor-authored tile resource; swap in real art by
	# assigning Maze.tile_set in the editor instead (see
	# docs/WALKTHROUGH.md "Sprites") and deleting the line below.
	if maze_layer.tile_set == null:
		var level: LevelData.LevelDef = LevelData.get_level(GameState.level_id)
		maze_layer.tile_set = MazeTileSetBuilder.build(level.floor_color, level.wall_color)
	maze_layer.clear()
	for y in range(maze.h):
		for x in range(maze.w):
			var coord := Vector2i(0, 0)
			if not maze.is_floor(x, y):
				coord = Vector2i(1, 0)
			elif maze.is_puzzle_room_cell(x, y):
				coord = Vector2i(2, 0)
			maze_layer.set_cell(Vector2i(x, y), 0, coord)


# ---------------------------------------------------------------------------
# Players, tether, pods (host authoritative)
# ---------------------------------------------------------------------------

func _host_spawn_players() -> void:
	var spawn_pos: Vector2 = (Vector2(maze.spawn_cell) + Vector2(0.5, 0.5)) * GameState.TILE_SIZE
	var i := 0
	for team_id in GameState.teams:
		var team: Dictionary = GameState.teams[team_id]
		for peer_id in team["member_order"]:
			var p: Player = PlayerScene.instantiate()
			p.peer_id = peer_id
			p.team_id = team_id
			p.position = spawn_pos + Vector2(i * 4 - 20, 0)
			players_node.add_child(p)
			player_nodes[peer_id] = p
			i += 1


func _host_setup_tether_and_pods() -> void:
	pod_graph = PodGraph.new()
	tether_system = TetherSystem.new()
	add_child(tether_system)
	tether_system.setup(maze, pod_graph)
	tether_system.link_snapped.connect(_on_host_link_snapped)

	for team_id in GameState.teams:
		var order: Array = GameState.teams[team_id]["member_order"]
		for i in range(order.size() - 1):
			var a_id: int = order[i]
			var b_id: int = order[i + 1]
			tether_system.add_link(player_nodes[a_id], a_id, player_nodes[b_id], b_id)

	GameState.pods = pod_graph.recompute_pods()


func apply_input(peer_id: int, dir: Vector2) -> void:
	if player_nodes.has(peer_id):
		player_nodes[peer_id].set_input(dir)


func _on_host_link_snapped(a_id: int, b_id: int) -> void:
	GameState.pods = pod_graph.recompute_pods()
	NetRouter.broadcast_link_snapped(a_id, b_id)
	_eliminate_small_pods()


func _eliminate_small_pods() -> void:
	var any_removed := false
	for pod in GameState.pods:
		if pod.size() < GameState.MIN_TEAM_SIZE:
			for peer_id in pod:
				if player_nodes.has(peer_id):
					player_nodes[peer_id].eliminated = true
				pod_graph.remove_player(peer_id)
			any_removed = true
	if any_removed:
		GameState.pods = pod_graph.recompute_pods()


func on_player_disconnected(peer_id: int) -> void:
	if not GameState.is_host():
		return
	for link in tether_system.links:
		if (link.a_id == peer_id or link.b_id == peer_id) and link.alive:
			tether_system._snap(link)  # treat disconnect like a snap, per design doc 4.9
	pod_graph.remove_player(peer_id)
	GameState.pods = pod_graph.recompute_pods()
	_eliminate_small_pods()


# ---------------------------------------------------------------------------
# Console unlock + exit + scoring (host authoritative)
# ---------------------------------------------------------------------------

func _on_console_body_entered(body: Node) -> void:
	if not (GameState.is_host() or not multiplayer.has_multiplayer_peer()):
		return
	if not (body is Player):
		return
	var peer_id: int = body.peer_id
	var pod: Array = pod_graph.pod_of(peer_id, GameState.pods)
	var key: String = _pod_key(pod)
	if _console_entered_pods.has(key):
		return

	# Unlock only if the pod's combined notebook covers every fragment.
	var known := {}
	for member in pod:
		for frag_id in GameState.notebook.get(member, {}):
			known[frag_id] = true
	if known.size() >= GameState.exit_sequence.size():
		_console_entered_pods[key] = true
		exit_gate.modulate = Color(1, 1, 1, 1)  # cosmetic: "unlocked" state; swap sprite frame in a real build


func _on_exit_body_entered(body: Node) -> void:
	if not (GameState.is_host() or not multiplayer.has_multiplayer_peer()):
		return
	if not (body is Player):
		return
	var peer_id: int = body.peer_id
	var pod: Array = pod_graph.pod_of(peer_id, GameState.pods)
	var key: String = _pod_key(pod)
	if not _console_entered_pods.has(key) or _scored_pods.has(key):
		return

	# All pod members must be standing in the exit zone simultaneously.
	var overlapping: Array = exit_gate.get_overlapping_bodies()
	for member in pod:
		if not player_nodes.has(member) or not overlapping.has(player_nodes[member]):
			return

	_scored_pods[key] = true
	var team_id: int = player_nodes[peer_id].team_id
	var original_size: int = GameState.teams[team_id]["original_size"]
	var points: int = ScoreTable.score_for(pod.size(), original_size)
	GameState.final_scores.append({"pod": pod, "team_id": team_id, "points": points})

	_check_match_finished()


func _check_match_finished() -> void:
	# Match ends once every surviving pod has either scored or been eliminated.
	for pod in GameState.pods:
		var key := _pod_key(pod)
		if not _scored_pods.has(key) and pod.size() >= GameState.MIN_TEAM_SIZE:
			return
	NetRouter.broadcast_match_finished()


func _pod_key(pod: Array) -> String:
	var sorted_pod := pod.duplicate()
	sorted_pod.sort()
	return ",".join(sorted_pod.map(func(x): return str(x)))


# ---------------------------------------------------------------------------
# Snapshot broadcast / apply
# ---------------------------------------------------------------------------

func _broadcast_snapshot() -> void:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(player_nodes.size())
	for peer_id in player_nodes:
		var p: Player = player_nodes[peer_id]
		buf.put_u32(peer_id)
		buf.put_float(p.position.x)
		buf.put_float(p.position.y)
		buf.put_u8(1 if p.eliminated else 0)
	NetRouter.broadcast_snapshot(buf.data_array)


func apply_snapshot(packed: PackedByteArray) -> void:
	if GameState.is_host():
		return  # host is authoritative, never overwrite with its own echo
	var buf := StreamPeerBuffer.new()
	buf.data_array = packed
	var count := buf.get_u8()
	for i in range(count):
		var peer_id := buf.get_u32()
		var x := buf.get_float()
		var y := buf.get_float()
		var eliminated := buf.get_u8() == 1
		if player_nodes.has(peer_id):
			var p: Player = player_nodes[peer_id]
			if not p.is_local:
				p.position = p.position.lerp(Vector2(x, y), 0.3)
			p.eliminated = eliminated


# ---------------------------------------------------------------------------
# Visuals: tether lines + remote link-snap feedback
# ---------------------------------------------------------------------------

func _update_tether_lines() -> void:
	if GameState.is_host() or not multiplayer.has_multiplayer_peer():
		for link in tether_system.links:
			var key: String = "%d:%d" % [link.a_id, link.b_id]
			if not link.alive:
				if link_lines.has(key):
					link_lines[key].queue_free()
					link_lines.erase(key)
				continue
			if not link_lines.has(key):
				var line := Line2D.new()
				line.width = 2.0
				tether_lines.add_child(line)
				link_lines[key] = line
			var line: Line2D = link_lines[key]
			line.points = link.path if link.path.size() > 0 else PackedVector2Array([link.a.position, link.b.position])
			line.default_color = _tension_color(link.state)


func _tension_color(state: int) -> Color:
	match state:
		TetherSystem.TensionState.GREEN:
			return Color(0.3, 0.85, 0.3)
		TetherSystem.TensionState.YELLOW:
			return Color(0.9, 0.85, 0.2)
		TetherSystem.TensionState.RED:
			return Color(0.9, 0.2, 0.2)
		TetherSystem.TensionState.CRITICAL:
			return Color(0.4, 0.0, 0.0)
	return Color.WHITE


func _on_link_snapped_visual(a_id: int, b_id: int) -> void:
	var key: String = "%d:%d" % [a_id, b_id]
	if link_lines.has(key):
		link_lines[key].queue_free()
		link_lines.erase(key)


func _on_fragment_revealed(fragment_id: int, symbol: String) -> void:
	clue_spawner.reveal_symbol(fragment_id, symbol)


func _on_match_finished() -> void:
	get_tree().change_scene_to_file("res://scenes/score_screen.tscn")


# ---------------------------------------------------------------------------
# Developer commentary popup (purely cosmetic, local-only -- see
# commentary_node.gd / commentary_spawner.gd)
# ---------------------------------------------------------------------------

func _on_commentary_activated(note: CommentaryData.Note) -> void:
	var popup: PanelContainer = $HUD/CommentaryPopup
	var title_label: Label = $HUD/CommentaryPopup/VBox/TitleLabel
	var body_label: Label = $HUD/CommentaryPopup/VBox/BodyLabel
	title_label.text = note.title
	body_label.text = note.body
	popup.visible = true

	# Auto-hide after a few seconds rather than requiring a dismiss
	# button -- this is flavor text, not something blocking play. The
	# token guards against walking into a second note before the
	# first one's timer fires: only the MOST RECENT timer is allowed
	# to hide the popup, so an early note can't blank out a later one.
	_commentary_popup_token += 1
	var my_token := _commentary_popup_token
	var timer := get_tree().create_timer(6.0)
	timer.timeout.connect(func():
		if is_instance_valid(popup) and my_token == _commentary_popup_token:
			popup.visible = false)
