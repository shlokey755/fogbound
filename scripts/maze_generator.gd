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
##
## Puzzle rooms and tunnels: after the base maze is carved, N small open
## rooms are placed at seeded positions and joined by a chain of
## straight L-shaped tunnels that starts at the fog room. The first
## fragments sit at those rooms' centres in chain order, so the tunnel
## trail is also the order the exit code is read in. Everything is drawn
## from the same seeded RNG as the rest of the maze, so every client
## builds an identical layout from the match seed alone. With
## puzzle_room_count = 0 no extra RNG is consumed, so existing seeds
## produce exactly the maze they always did.

var rng := RandomNumberGenerator.new()
var w: int
var h: int
var grid: Array = []  # grid[y][x] -> 0 floor, 1 wall

# Populated by generate()
var fog_room_rect: Rect2i
var spawn_cell: Vector2i
var console_cell: Vector2i
var exit_cell: Vector2i
var fragment_cells: Array = []     # Array[Vector2i]
var commentary_cells: Array = []   # Array[Vector2i], see _place_commentary_nodes()
var puzzle_rooms: Array = []       # Array[Rect2i], in tunnel-chain order (see _carve_puzzle_rooms)
var tunnel_paths: Array = []       # Array[Array[Vector2i]]; tunnel i links room i-1 (or the fog room) to room i


func generate(seed_value: int, width: int, height: int, fragment_count: int = 8, commentary_count: int = 0,
		puzzle_room_count: int = 0, puzzle_room_size: int = 3) -> void:
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
	_carve_puzzle_rooms(puzzle_room_count, puzzle_room_size)
	_place_special_cells(fragment_count)
	_place_commentary_nodes(commentary_count)


func is_floor(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return grid[y][x] == 0


func is_puzzle_room_cell(x: int, y: int) -> bool:
	var p := Vector2i(x, y)
	for room in puzzle_rooms:
		if room.has_point(p):
			return true
	return false


## Flood fill over floor cells from `from`; used by tests and as a
## solvability check that every room, fragment and the exit connect.
func reachable_from(from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var queue: Array = [from]
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n: Vector2i = cur + d
			if is_floor(n.x, n.y) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


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

	# Fragments: the first ones sit at the centres of the puzzle rooms,
	# in tunnel-chain order (so fragment i is the i-th symbol of the exit
	# code AND the i-th room along the tunnel trail); any remainder go on
	# random floor cells outside the fog room, the exit and the rooms.
	fragment_cells = []
	for room in puzzle_rooms:
		if fragment_cells.size() < fragment_count:
			fragment_cells.append(room.get_center())

	var candidates: Array = []
	for y in range(h):
		for x in range(w):
			if not is_floor(x, y):
				continue
			if fog_room_rect.has_point(Vector2i(x, y)):
				continue
			if Vector2i(x, y) == exit_cell:
				continue
			if is_puzzle_room_cell(x, y):
				continue
			candidates.append(Vector2i(x, y))
	_shuffle(candidates)
	var remaining: int = fragment_count - fragment_cells.size()
	fragment_cells.append_array(candidates.slice(0, mini(remaining, candidates.size())))


# ---------------------------------------------------------------------------
# Puzzle rooms + tunnels
# ---------------------------------------------------------------------------

## Random odd integer in [lo, hi] (inclusive), or -1 if none fits. Rooms
## start on odd coordinates so they line up with the corridor lattice.
func _odd_between(lo: int, hi: int) -> int:
	if lo % 2 == 0:
		lo += 1
	if hi % 2 == 0:
		hi -= 1
	if hi < lo:
		return -1
	return lo + 2 * rng.randi_range(0, (hi - lo) / 2)


## Places up to `count` size x size rooms (size is forced odd), keeping at
## least two cells clear of the border, the fog room and each other, then
## orders them into a nearest-neighbour chain starting from the fog room
## (randomly taking the nearest or second-nearest each hop, so the trail
## isn't always the obvious one) and carves a tunnel along that chain.
func _carve_puzzle_rooms(count: int, size: int) -> void:
	puzzle_rooms.clear()
	tunnel_paths.clear()
	if count <= 0:
		return
	size = maxi(3, size | 1)

	var placed: Array = []
	var attempts := 0
	while placed.size() < count and attempts < count * 80:
		attempts += 1
		var x0 := _odd_between(3, w - 3 - size)
		var y0 := _odd_between(3, h - 3 - size)
		if x0 < 0 or y0 < 0:
			break  # maze too small for rooms this big
		var rect := Rect2i(x0, y0, size, size)
		if rect.intersects(fog_room_rect.grow(2)):
			continue
		var clear := true
		for other in placed:
			if rect.intersects(other.grow(2)):
				clear = false
				break
		if clear:
			placed.append(rect)

	for rect in placed:
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				grid[y][x] = 0

	# Order rooms into a chain, hopping to the nearest (or 2nd nearest) next.
	var cursor: Vector2i = fog_room_rect.get_center()
	var remaining: Array = placed.duplicate()
	while remaining.size() > 0:
		var from := cursor
		remaining.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
			return (a.get_center() - from).length_squared() < (b.get_center() - from).length_squared())
		var pick: int = rng.randi_range(0, mini(1, remaining.size() - 1))
		var room: Rect2i = remaining.pop_at(pick)
		puzzle_rooms.append(room)
		cursor = room.get_center()

	_carve_tunnels()


## Anchor = a cell inside the room with odd coordinates, so a tunnel that
## runs along its row/column stays on the corridor lattice and comes out
## one cell wide instead of fusing with the corridors beside it.
func _anchor_of(rect: Rect2i) -> Vector2i:
	var c := rect.get_center()
	if c.x % 2 == 0:
		c.x += 1
	if c.y % 2 == 0:
		c.y += 1
	return c


func _carve_tunnels() -> void:
	var from: Vector2i = _anchor_of(fog_room_rect)
	for room in puzzle_rooms:
		var to: Vector2i = _anchor_of(room)
		var path: Array = []
		var horizontal_first: bool = rng.randi_range(0, 1) == 0
		var corner: Vector2i = Vector2i(to.x, from.y) if horizontal_first else Vector2i(from.x, to.y)
		_carve_line(from, corner, path)
		_carve_line(corner, to, path)
		tunnel_paths.append(path)
		from = to


func _carve_line(a: Vector2i, b: Vector2i, path: Array) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var cur := a
	while true:
		grid[cur.y][cur.x] = 0
		if path.is_empty() or path[-1] != cur:
			path.append(cur)
		if cur == b:
			break
		cur += step


## A "dead end" is a floor cell with exactly one floor neighbour
## (north/south/east/west) -- i.e. a corridor that terminates there.
## Developer-commentary nodes are tucked into dead ends on purpose
## (see commentary_node.gd / docs/WALKTHROUGH.md "Developer
## commentary"): they're meant to reward actually exploring the
## maze's corners rather than sitting on the direct path to anywhere,
## the same way real commentary nodes in other games tend to hide off
## the critical path.
func dead_end_cells() -> Array:
	var out: Array = []
	for y in range(h):
		for x in range(w):
			if not is_floor(x, y):
				continue
			if fog_room_rect.has_point(Vector2i(x, y)):
				continue  # the fog room is wide open, never a "dead end"
			var neighbours := 0
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				if is_floor(x + d.x, y + d.y):
					neighbours += 1
			if neighbours == 1:
				out.append(Vector2i(x, y))
	return out


func _place_commentary_nodes(count: int) -> void:
	commentary_cells.clear()
	if count <= 0:
		return
	var candidates: Array = dead_end_cells()
	# Exclude anything that would overlap a fragment or the exit gate,
	# so no two pickups/interactables ever visually stack on one tile
	# (the exit is frequently itself a dead end, since _place_special_cells
	# puts it as close to the border as possible).
	candidates = candidates.filter(func(c): return not fragment_cells.has(c) and c != exit_cell)
	_shuffle(candidates)
	commentary_cells = candidates.slice(0, min(count, candidates.size()))
