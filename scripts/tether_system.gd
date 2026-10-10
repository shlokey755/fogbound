class_name TetherSystem
extends Node
## TetherSystem
## Host-only physics for the "holding hands" tether links between
## teammates. Implements the spring-damper rope model, the four-state
## tension machine (green/yellow/red/critical), rope wrapping around
## wall corners via AStarGrid2D, and the snag buffer that delays a
## snap while the rope is caught on geometry.
##
## See design doc section 3.3-3.5 for the derivation of these numbers.
## Run this only on the host: `if not GameState.is_host(): return`
## in the owning scene before adding this node to the tree.

enum TensionState { GREEN, YELLOW, RED, CRITICAL }

const EDGES := [0.50, 0.80, 1.00]  # upper bound of GREEN, YELLOW, RED (fraction of D_max)
const HYST := 0.02

signal link_tension_changed(a_id: int, b_id: int, tension: float, state: int)
signal link_snapped(a_id: int, b_id: int)

class Link:
	var a: Node2D       # player node, must expose .position, .velocity, .pull_velocity
	var a_id: int
	var b: Node2D
	var b_id: int
	var alive: bool = true
	var tension: float = 0.0
	var state: int = TensionState.GREEN
	var snagged: bool = false
	var snap_timer: float = 0.0
	var path: PackedVector2Array = PackedVector2Array()

var links: Array = []  # Array[Link]
var astar_grid: AStarGrid2D
var pod_graph: PodGraph

var _snag_check_counter: int = 0


func setup(maze: MazeGenerator, pod_graph_ref: PodGraph) -> void:
	pod_graph = pod_graph_ref
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(0, 0, maze.w, maze.h)
	astar_grid.cell_size = Vector2(GameState.TILE_SIZE, GameState.TILE_SIZE)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update()
	for y in range(maze.h):
		for x in range(maze.w):
			astar_grid.set_point_solid(Vector2i(x, y), not maze.is_floor(x, y))


func add_link(a_node: Node2D, a_id: int, b_node: Node2D, b_id: int) -> void:
	var link := Link.new()
	link.a = a_node
	link.a_id = a_id
	link.b = b_node
	link.b_id = b_id
	links.append(link)
	pod_graph.add_link(a_id, b_id)


func _physics_process(delta: float) -> void:
	_snag_check_counter += 1
	var do_snag_check := _snag_check_counter % 3 == 0  # throttle A* to every 3rd tick

	for link in links:
		if link.alive:
			_step_link(link, delta, do_snag_check)


func _step_link(link: Link, delta: float, do_snag_check: bool) -> void:
	var from: Vector2 = link.a.position
	var to: Vector2 = link.b.position

	if do_snag_check or link.path.is_empty():
		link.path = _rope_path(from, to)
	link.snagged = link.path.size() > 2

	var d := _path_length(link.path)
	link.tension = clampf(d / GameState.TETHER_DMAX, 0.0, 2.0)

	var prev_state := link.state
	link.state = _next_state(link.tension, link.state)
	if link.state != prev_state:
		link_tension_changed.emit(link.a_id, link.b_id, link.tension, link.state)

	var stretch: float = maxf(d - GameState.TETHER_L0, 0.0)
	if stretch > 0.0 and link.path.size() >= 2:
		var dir_a: Vector2 = (link.path[1] - from).normalized()
		var dir_b: Vector2 = (link.path[link.path.size() - 2] - to).normalized()
		var v_rel: float = -link.a.velocity.dot(dir_a) - link.b.velocity.dot(dir_b)
		var force: float = maxf(GameState.TETHER_K * stretch + GameState.TETHER_C * v_rel, 0.0)
		link.a.pull_velocity += dir_a * force * delta
		link.b.pull_velocity += dir_b * force * delta

	var cap: float = GameState.TETHER_PULL_CAP[link.state]
	link.a.pull_cap = maxf(link.a.pull_cap, cap)
	link.b.pull_cap = maxf(link.b.pull_cap, cap)

	if link.state == TensionState.CRITICAL:
		link.snap_timer += delta
		var grace: float = GameState.TETHER_SNAG_BUFFER if link.snagged else 0.0
		if link.snap_timer >= grace:
			_snap(link)
	else:
		link.snap_timer = maxf(link.snap_timer - delta * 2.0, 0.0)


func _snap(link: Link) -> void:
	link.alive = false
	pod_graph.snap_link(link.a_id, link.b_id)
	link_snapped.emit(link.a_id, link.b_id)


func _next_state(t: float, cur: int) -> int:
	var s := cur
	while s < TensionState.CRITICAL and t >= EDGES[s]:
		s += 1
	while s > TensionState.GREEN and t < EDGES[s - 1] - HYST:
		s -= 1
	return s


func _rope_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if _clear_line(from, to):
		return PackedVector2Array([from, to])
	var from_cell := _to_cell(from)
	var to_cell := _to_cell(to)
	var raw: PackedVector2Array = astar_grid.get_point_path(from_cell, to_cell)
	if raw.is_empty():
		return PackedVector2Array([from, to])  # fallback: no path found, treat as straight
	return _pull_taut(from, raw, to)


func _pull_taut(from: Vector2, pts: PackedVector2Array, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array([from])
	var anchor := from
	var i := 0
	var all_pts := PackedVector2Array(pts)
	while i < all_pts.size():
		var j: int = all_pts.size() - 1
		while j > i and not _clear_line(anchor, all_pts[j]):
			j -= 1
		anchor = all_pts[j]
		out.append(anchor)
		i = j + 1
	out.append(to)
	return out


func _clear_line(from: Vector2, to: Vector2) -> bool:
	# Simple DDA walk across the maze grid checking for solid cells.
	var steps: int = int(from.distance_to(to) / (GameState.TILE_SIZE * 0.5)) + 1
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var p: Vector2 = from.lerp(to, t)
		var cell := _to_cell(p)
		if astar_grid.is_point_solid(cell):
			return false
	return true


func _to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x / GameState.TILE_SIZE), int(p.y / GameState.TILE_SIZE))


func _path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total
