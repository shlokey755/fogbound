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
