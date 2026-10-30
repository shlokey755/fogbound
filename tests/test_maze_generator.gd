extends SceneTree
## test_maze_generator.gd
## Smoke test for MazeGenerator: determinism across repeated runs with
## the same seed (critical for host/client agreement), basic structural
## sanity (every special cell is actually floor, fog room is carved,
## maze stays enclosed), and that fragment cells never collide with
## the exit or the fog room. Run with:
##   godot --headless --script res://tests/test_maze_generator.gd

var failures := 0


func _init() -> void:
	_test_deterministic_for_same_seed()
	_test_different_seeds_differ()
	_test_special_cells_are_floor()
	_test_fragments_outside_fog_room_and_not_on_exit()
	_test_border_is_fully_wall()
	_test_dead_ends_have_exactly_one_floor_neighbour()
	_test_commentary_nodes_dont_overlap_fragments_or_exit()
	_test_commentary_count_degrades_gracefully_when_too_few_dead_ends()
	_test_puzzle_rooms_are_deterministic_per_seed()
	_test_puzzle_rooms_vary_with_seed()
	_test_puzzle_rooms_zero_count_changes_nothing()
	_test_puzzle_rooms_structure_across_seeds()
	_test_tunnels_are_connected_floor_paths()
	_test_fragments_follow_the_tunnel_chain()
	_test_every_level_places_its_puzzle_rooms()

	if failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("%d TEST(S) FAILED" % failures)
		quit(1)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		failures += 1


func _grid_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for y in range(a.size()):
		if a[y] != b[y]:
			return false
	return true


func _test_deterministic_for_same_seed() -> void:
	var m1 := MazeGenerator.new()
	m1.generate(12345, 21, 21, 6)
	var m2 := MazeGenerator.new()
	m2.generate(12345, 21, 21, 6)
	_check("same seed produces identical grid", _grid_equal(m1.grid, m2.grid))
	_check("same seed produces identical exit cell", m1.exit_cell == m2.exit_cell)
	_check("same seed produces identical fragment cells", m1.fragment_cells == m2.fragment_cells)


func _test_different_seeds_differ() -> void:
	var m1 := MazeGenerator.new()
	m1.generate(1, 21, 21, 6)
	var m2 := MazeGenerator.new()
	m2.generate(2, 21, 21, 6)
	_check("different seeds produce different grids", not _grid_equal(m1.grid, m2.grid))


func _test_special_cells_are_floor() -> void:
	var m := MazeGenerator.new()
	m.generate(999, 25, 25, 8)
	_check("spawn cell is floor", m.is_floor(m.spawn_cell.x, m.spawn_cell.y))
	_check("console cell is floor", m.is_floor(m.console_cell.x, m.console_cell.y))
	_check("exit cell is floor", m.is_floor(m.exit_cell.x, m.exit_cell.y))
	for cell in m.fragment_cells:
		if not m.is_floor(cell.x, cell.y):
			_check("fragment cell %s is floor" % cell, false)
			return
	_check("all fragment cells are floor", true)


func _test_fragments_outside_fog_room_and_not_on_exit() -> void:
	var m := MazeGenerator.new()
	m.generate(42, 25, 25, 8)
	var ok := true
	for cell in m.fragment_cells:
		if m.fog_room_rect.has_point(cell):
			ok = false
		if cell == m.exit_cell:
			ok = false
	_check("no fragment lands inside the fog room or on the exit", ok)


func _test_border_is_fully_wall() -> void:
	var m := MazeGenerator.new()
	m.generate(7, 19, 19, 4)
	var ok := true
	for x in range(m.w):
		if m.is_floor(x, 0) or m.is_floor(x, m.h - 1):
			ok = false
	for y in range(m.h):
		if m.is_floor(0, y) or m.is_floor(m.w - 1, y):
			ok = false
	_check("outer border is entirely wall (maze stays enclosed)", ok)


func _test_dead_ends_have_exactly_one_floor_neighbour() -> void:
	var m := MazeGenerator.new()
	m.generate(321, 31, 31, 8)
	var ok := true
	for cell in m.dead_end_cells():
		var neighbours := 0
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			if m.is_floor(cell.x + d.x, cell.y + d.y):
				neighbours += 1
		if neighbours != 1:
			ok = false
		if m.fog_room_rect.has_point(cell):
			ok = false
	_check("every dead-end cell has exactly 1 floor neighbour and sits outside the fog room", ok)
	_check("a 31x31 maze has at least one dead end to place commentary nodes in", m.dead_end_cells().size() > 0)


func _test_commentary_nodes_dont_overlap_fragments_or_exit() -> void:
	var m := MazeGenerator.new()
	m.generate(654, 31, 31, 8, 3)
	var ok := true
	for cell in m.commentary_cells:
		if m.fragment_cells.has(cell):
			ok = false
		if cell == m.exit_cell:
			ok = false
	_check("commentary nodes never land on a fragment or the exit", ok)
	_check("commentary_count=3 places up to 3 nodes", m.commentary_cells.size() <= 3)


func _test_commentary_count_degrades_gracefully_when_too_few_dead_ends() -> void:
	# Ask for far more commentary nodes than any maze this size could
	# possibly have dead ends for -- must not crash or index out of
	# range, and must simply place as many as actually fit.
	var m := MazeGenerator.new()
	m.generate(987, 19, 19, 2, 999)
	_check("asking for more commentary nodes than exist doesn't crash or over-place",
		m.commentary_cells.size() <= m.dead_end_cells().size())

	var m_zero := MazeGenerator.new()
	m_zero.generate(1, 19, 19, 2, 0)
	_check("commentary_count=0 places nothing", m_zero.commentary_cells.is_empty())


# ---------------------------------------------------------------------------
# Puzzle rooms + seeded tunnel chain
# ---------------------------------------------------------------------------

func _rooms_as_strings(m: MazeGenerator) -> Array:
	return m.puzzle_rooms.map(func(r: Rect2i): return str(r))


func _test_puzzle_rooms_are_deterministic_per_seed() -> void:
	var a := MazeGenerator.new()
	a.generate(4242, 31, 31, 8, 3, 4, 3)
	var b := MazeGenerator.new()
	b.generate(4242, 31, 31, 8, 3, 4, 3)
	_check("same seed -> identical grid with puzzle rooms", _grid_equal(a.grid, b.grid))
	_check("same seed -> identical room order", _rooms_as_strings(a) == _rooms_as_strings(b))
	_check("same seed -> identical tunnel paths", a.tunnel_paths == b.tunnel_paths)
	_check("same seed -> identical fragment cells", a.fragment_cells == b.fragment_cells)


func _test_puzzle_rooms_vary_with_seed() -> void:
	var layouts := {}
	for seed_value in range(1, 21):
		var m := MazeGenerator.new()
		m.generate(seed_value, 31, 31, 8, 0, 4, 3)
		layouts[str(_rooms_as_strings(m))] = true
	_check("20 different seeds give at least 15 distinct room layouts (got %d)" % layouts.size(),
		layouts.size() >= 15)


func _test_puzzle_rooms_zero_count_changes_nothing() -> void:
	# puzzle_room_count = 0 must not consume any RNG, so seeds that
	# existed before this feature still build exactly the same maze.
	var plain := MazeGenerator.new()
	plain.generate(999, 31, 31, 8, 3)
	var zero := MazeGenerator.new()
	zero.generate(999, 31, 31, 8, 3, 0, 5)
	_check("0 puzzle rooms leaves the grid exactly as before", _grid_equal(plain.grid, zero.grid))
	_check("0 puzzle rooms leaves fragment cells exactly as before", plain.fragment_cells == zero.fragment_cells)
	_check("0 puzzle rooms leaves commentary cells exactly as before", plain.commentary_cells == zero.commentary_cells)
	_check("0 puzzle rooms means no rooms or tunnels", zero.puzzle_rooms.is_empty() and zero.tunnel_paths.is_empty())


func _test_puzzle_rooms_structure_across_seeds() -> void:
	var ok_floor := true
	var ok_border := true
	var ok_fog := true
	var ok_overlap := true
	var ok_reach := true
	for seed_value in range(1, 41):
		var m := MazeGenerator.new()
		m.generate(seed_value, 37, 37, 10, 0, 5, 3)
		var reach := m.reachable_from(m.spawn_cell)
		for i in range(m.puzzle_rooms.size()):
			var room: Rect2i = m.puzzle_rooms[i]
			for y in range(room.position.y, room.position.y + room.size.y):
				for x in range(room.position.x, room.position.x + room.size.x):
					if not m.is_floor(x, y):
						ok_floor = false
					if not reach.has(Vector2i(x, y)):
						ok_reach = false
			if room.position.x < 2 or room.position.y < 2 \
					or room.end.x > m.w - 2 or room.end.y > m.h - 2:
				ok_border = false
			if room.intersects(m.fog_room_rect):
				ok_fog = false
			for j in range(i + 1, m.puzzle_rooms.size()):
				if room.intersects(m.puzzle_rooms[j]):
					ok_overlap = false
		if not reach.has(m.exit_cell):
			ok_reach = false
		for f in m.fragment_cells:
			if not reach.has(f):
				ok_reach = false
	_check("every puzzle-room cell is floor (40 seeds)", ok_floor)
	_check("puzzle rooms stay off the outer border (40 seeds)", ok_border)
	_check("puzzle rooms never overlap the fog room (40 seeds)", ok_fog)
	_check("puzzle rooms never overlap each other (40 seeds)", ok_overlap)
	_check("rooms, fragments and exit are all reachable from the spawn (40 seeds)", ok_reach)


func _test_tunnels_are_connected_floor_paths() -> void:
	var ok_len := true
	var ok_floor := true
	var ok_step := true
	var ok_join := true
	for seed_value in range(1, 41):
		var m := MazeGenerator.new()
		m.generate(seed_value, 45, 45, 12, 0, 6, 3)
		if m.tunnel_paths.size() != m.puzzle_rooms.size():
			ok_len = false
		for i in range(m.tunnel_paths.size()):
			var path: Array = m.tunnel_paths[i]
			if path.is_empty():
				ok_len = false
				continue
			for k in range(path.size()):
				var c: Vector2i = path[k]
				if not m.is_floor(c.x, c.y):
					ok_floor = false
				if k > 0:
					var d: Vector2i = c - path[k - 1]
					if absi(d.x) + absi(d.y) != 1:
						ok_step = false
			# the last cell of tunnel i is inside room i, and the first
			# cell of tunnel i+1 is that same cell
			if not m.puzzle_rooms[i].has_point(path[-1]):
				ok_join = false
			if i + 1 < m.tunnel_paths.size() and m.tunnel_paths[i + 1][0] != path[-1]:
				ok_join = false
		if not m.tunnel_paths.is_empty() and not m.fog_room_rect.has_point(m.tunnel_paths[0][0]):
			ok_join = false
	_check("one non-empty tunnel per puzzle room (40 seeds)", ok_len)
	_check("every tunnel cell is floor (40 seeds)", ok_floor)
	_check("tunnel cells step one tile at a time (40 seeds)", ok_step)
	_check("tunnels chain fog room -> room 0 -> room 1 -> ... (40 seeds)", ok_join)


func _test_fragments_follow_the_tunnel_chain() -> void:
	var ok_order := true
	var ok_count := true
	for seed_value in range(1, 41):
		var m := MazeGenerator.new()
		m.generate(seed_value, 37, 37, 10, 0, 5, 3)
		if m.fragment_cells.size() != 10:
			ok_count = false
		for i in range(m.puzzle_rooms.size()):
			if m.fragment_cells[i] != m.puzzle_rooms[i].get_center():
				ok_order = false
		# no fragment is duplicated
		var seen := {}
		for f in m.fragment_cells:
			if seen.has(f):
				ok_count = false
			seen[f] = true
	_check("fragment i sits at the centre of puzzle room i (40 seeds)", ok_order)
	_check("fragment_count is honoured with rooms and no duplicates (40 seeds)", ok_count)

	# fewer fragments than rooms: extra rooms stay empty rather than overflowing
	var few := MazeGenerator.new()
	few.generate(5, 37, 37, 2, 0, 5, 3)
	_check("fragment_count smaller than room count caps fragments at fragment_count", few.fragment_cells.size() == 2)


func _test_every_level_places_its_puzzle_rooms() -> void:
	# LevelData is an autoload, which does not exist in --script mode, so
	# the same numbers are checked via the real level table in the boot
	# smoketest. Here: the table's size classes, hard-coded, must be able
	# to fit their rooms for a spread of seeds.
	var classes := [[19, 2, 3], [23, 3, 3], [31, 4, 3], [37, 5, 3], [45, 6, 3], [51, 7, 5], [41, 8, 3]]
	for c in classes:
		var short := 0
		for seed_value in range(1, 31):
			var m := MazeGenerator.new()
			m.generate(seed_value, c[0], c[0], 16, 0, c[1], c[2])
			if m.puzzle_rooms.size() < c[1]:
				short += 1
		_check("%dx%d maze fits %d rooms of size %d on at least 28 of 30 seeds (short on %d)" % [c[0], c[0], c[1], c[2], short],
			short <= 2)
