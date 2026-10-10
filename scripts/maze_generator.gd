class_name MazeGenerator
extends RefCounted
## MazeGenerator
## Seeded maze generation: recursive backtracker (DFS) carved onto an
## odd-sized grid, with a central "fog room" cleared as an open area
## before corridors are carved outward, plus a handful of extra walls
## knocked out afterwards so the maze isn't a perfect (loop-free) tree.
##
## Grid convention: cell (x, y) is WALL if grid[y][x] == 1, FLOOR if 0.
## Width and height should be odd numbers so walls/cells alternate
## cleanly (standard grid-maze convention).

var rng := RandomNumberGenerator.new()
var w: int
var h: int
var grid: Array = []  # grid[y][x] -> 0 floor, 1 wall

# Populated by generate()
var fog_room_rect: Rect2i
var spawn_cell: Vector2i
var console_cell: Vector2i
var exit_cell: Vector2i
var fragment_cells: Array = []  # Array[Vector2i]


func generate(seed_value: int, width: int, height: int, fragment_count: int = 8) -> void:
	rng.seed = seed_value
	w = width if width % 2 == 1 else width + 1
	h = height if height % 2 == 1 else height + 1

	grid.clear()
	for y in range(h):
		var row := []
		row.resize(w)
		row.fill(1)
		grid.append(row)

	_carve_fog_room()
	_carve_corridors_from_fog_room_edge()
	_add_loops(w * h / 40)  # knock out a handful of extra walls
	_place_special_cells(fragment_count)


func is_floor(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return grid[y][x] == 0


## Seeded Fisher-Yates shuffle. Godot's built-in Array.shuffle() draws
## from the engine's global RNG and can't be seeded, which would make
## the maze layout diverge between host and clients -- so every
## shuffle in this file must go through this helper and our own
## seeded `rng` instead.
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _carve_fog_room() -> void:
	# Open a room roughly 1/5th the maze size at dead centre, snapped
	# to odd coordinates so it aligns with the corridor grid.
	var room_w: int = maxi(5, int(w / 5.0)) | 1
	var room_h: int = maxi(5, int(h / 5.0)) | 1
	var cx := int(w / 2.0)
	var cy := int(h / 2.0)
	var x0 := cx - int(room_w / 2.0)
	var y0 := cy - int(room_h / 2.0)
	x0 -= x0 % 2  # keep even top-left so interior cells land on odd coords
	y0 -= y0 % 2

	for y in range(y0, y0 + room_h):
		for x in range(x0, x0 + room_w):
			if x > 0 and y > 0 and x < w - 1 and y < h - 1:
				grid[y][x] = 0

	fog_room_rect = Rect2i(x0, y0, room_w, room_h)


func _carve_corridors_from_fog_room_edge() -> void:
	# Seed the DFS from every odd cell on the fog room's perimeter so
	# corridors radiate outward in multiple directions, then run a
	# randomized DFS (recursive backtracker) over the remaining grid.
	var visited := {}
	_mark_room_visited(visited)

	var starts: Array = []
	for x in range(fog_room_rect.position.x, fog_room_rect.position.x + fog_room_rect.size.x):
		for y in [fog_room_rect.position.y - 1, fog_room_rect.position.y + fog_room_rect.size.y]:
			if x % 2 == 1 and y % 2 == 1 and y > 0 and y < h - 1:
				starts.append(Vector2i(x, y))
	for y in range(fog_room_rect.position.y, fog_room_rect.position.y + fog_room_rect.size.y):
		for x in [fog_room_rect.position.x - 1, fog_room_rect.position.x + fog_room_rect.size.x]:
			if y % 2 == 1 and x % 2 == 1 and x > 0 and x < w - 1:
				starts.append(Vector2i(x, y))

	_shuffle(starts)

	for start in starts:
		if visited.has(start):
			continue
		_dfs_from(start, visited)


func _mark_room_visited(visited: Dictionary) -> void:
	for y in range(fog_room_rect.position.y, fog_room_rect.position.y + fog_room_rect.size.y):
		for x in range(fog_room_rect.position.x, fog_room_rect.position.x + fog_room_rect.size.x):
			visited[Vector2i(x, y)] = true


func _dfs_from(start: Vector2i, visited: Dictionary) -> void:
	var stack: Array = [start]
	grid[start.y][start.x] = 0
	visited[start] = true

	while stack.size() > 0:
		var cur: Vector2i = stack[-1]
		var dirs := [Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0)]
		_shuffle(dirs)

		var advanced := false
		for d in dirs:
			var next: Vector2i = cur + d
			if next.x <= 0 or next.y <= 0 or next.x >= w - 1 or next.y >= h - 1:
				continue
			if visited.has(next):
				continue
			var wall: Vector2i = cur + d / 2
			grid[wall.y][wall.x] = 0
			grid[next.y][next.x] = 0
			visited[next] = true
			stack.append(next)
			advanced = true
			break

		if not advanced:
			stack.pop_back()


func _add_loops(count: int) -> void:
	# Remove a few interior walls at random to create loops, so the
	# maze isn't a perfect (single-path) tree. Skip anything touching
	# the outer border so the maze stays enclosed.
	var attempts := 0
	var removed := 0
	while removed < count and attempts < count * 20:
		attempts += 1
		var x := rng.randi_range(2, w - 3)
		var y := rng.randi_range(2, h - 3)
		if grid[y][x] != 1:
			continue
		# Only remove walls with floor on exactly two opposite sides
		# (horizontal or vertical corridor walls), never carve diagonally.
		var n := is_floor(x, y - 1)
		var s := is_floor(x, y + 1)
		var e := is_floor(x + 1, y)
		var wv := is_floor(x - 1, y)
		if (n and s and not e and not wv) or (e and wv and not n and not s):
			grid[y][x] = 0
			removed += 1


func _place_special_cells(fragment_count: int) -> void:
	spawn_cell = Vector2i(
		fog_room_rect.position.x + int(fog_room_rect.size.x / 2.0),
		fog_room_rect.position.y + int(fog_room_rect.size.y / 2.0)
	)
	console_cell = spawn_cell  # console sits in the fog room, see design doc section 2 / assumption A1

	# Exit: pick a floor cell as close to the outer border as possible.
	var best: Vector2i = Vector2i(1, 1)
	var best_dist := -1.0
	for y in range(h):
		for x in range(w):
			if not is_floor(x, y):
				continue
			var edge_dist: float = min(min(x, w - 1 - x), min(y, h - 1 - y))
			if edge_dist > best_dist and edge_dist <= 1:
				best_dist = edge_dist
				best = Vector2i(x, y)
	exit_cell = best

	# Fragments: random floor cells, excluding the fog room and exit.
	var candidates: Array = []
	for y in range(h):
		for x in range(w):
			if not is_floor(x, y):
				continue
			if fog_room_rect.has_point(Vector2i(x, y)):
				continue
			if Vector2i(x, y) == exit_cell:
				continue
			candidates.append(Vector2i(x, y))
	_shuffle(candidates)
	fragment_cells = candidates.slice(0, min(fragment_count, candidates.size()))
